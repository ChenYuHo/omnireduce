#!/bin/bash

# FLAGS: INSTALL MLX5 COLOCATED LATENCIES TIMESTAMPS TIMERS DEBUG HOROVOD CONDA OFFLOAD_BITMAP NOSCALING PYTORCH ALGO2 COUNTERS NO_FILL_STORE RANDOMK
set -e
set -x

CWD=`pwd`
DPDK_ARGS='-fPIC '
DAIET_ARGS=''
EXP_ARGS=''
PS_ARGS=''
HOROVOD_ARGS=''

if [[ $@ == *'CONDA'* ]]; then
  echo "will install libraries to ${CONDA_PREFIX:-'/'}"
  read -p "Continue (y/N)? " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
  fi
  THIS_TIME=`date`
  echo "build_all.sh invoked at ${THIS_TIME} with $@" > ${CONDA_PREFIX}/build-info.txt
fi

if [[ $@ == *'MLX5'* ]]; then
  echo 'MLX5 SUPPORT'
  EXP_ARGS+='-DUSE_MLX5=1 '
fi
if [[ $@ == *'MLX4'* ]]; then
  echo 'MLX4 SUPPORT'
  EXP_ARGS+='-DUSE_MLX4=1 '
fi
if [[ $@ == *'COLOCATED'* ]]; then
  echo 'COLOCATED SET'
  DAIET_ARGS+='COLOCATED=ON '
fi
if [[ $@ == *'LATENCIES'* ]]; then
  echo 'LATENCIES SET'
  DAIET_ARGS+='LATENCIES=ON '
fi
if [[ $@ == *'TIMESTAMPS'* ]]; then
  echo 'TIMESTAMPS SET'
  DAIET_ARGS+='TIMESTAMPS=ON '
fi
if [[ $@ == *'COUNTERS'* ]]; then
  echo 'COUNTERS SET'
  DAIET_ARGS+='COUNTERS=ON '
fi
if [[ $@ == *'ALGO2'* ]]; then
  echo 'ALGO2 SET'
  DAIET_ARGS+='ALGO2=ON '
  PS_ARGS+='ALGO2=ON '
fi
if [[ $@ == *'TIMERS'* ]]; then
  echo 'TIMERS SET'
  DAIET_ARGS+='TIMERS=ON '
  PS_ARGS+='TIMERS=ON '
fi
if [[ $@ == *'NO_FILL_STORE'* ]]; then
  echo 'NO_FILL_STORE SET'
  DAIET_ARGS+='NO_FILL_STORE=ON '
fi
if [[ $@ == *'DEBUG'* ]]; then
  echo 'DEBUG SET'
  DAIET_ARGS+='DEBUG=ON COUNTERS=ON '
  DPDK_ARGS+='-g -O0 '
  PS_ARGS+='DEBUG=ON '
  EXP_ARGS+='-DDEBUG=1 '
fi
if [[ $@ == *'HOROVOD'* ]]; then
  echo 'HOROVOD SET'
  GLOO_CMAKE_ARGS+='-DUSE_REDIS=ON -DUSE_MPI=1 -DCMAKE_CXX_FLAGS="-D_GLIBCXX_USE_CXX11_ABI=1"'
  EXP_ARGS+='-DCMAKE_CXX_FLAGS="-D_GLIBCXX_USE_CXX11_ABI=1"'
fi
if [[ $@ == *'CONDA'* ]]; then
  GLOO_CMAKE_ARGS+="-DCMAKE_INSTALL_PREFIX=${CONDA_PREFIX}"
  EXP_ARGS+='-DCMAKE_CXX_FLAGS="-D_GLIBCXX_USE_CXX11_ABI=1"'
  DAIET_EXTRA_CXX_FLAGS+="-I${CONDA_PREFIX}/include -L${CONDA_PREFIX}/lib "
fi
if [[ $@ == *'OFFLOAD_BITMAP'* ]]; then
  echo 'OFFLOAD_BITMAP SET'
  DAIET_ARGS+='OFFLOAD_BITMAP=ON '
fi
if [[ $@ == *'NOSCALING'* ]]; then
  echo 'NOSCALING SET'
  DAIET_ARGS+='NOSCALING=ON '
  PS_ARGS+='NOSCALING=ON '
fi

# Build DPDK
cd daiet/lib/dpdk/

if [[ $@ != *'SKIP_DPDK'* ]]; then
  rm -rf build

  if [[ $@ == *'MLX5'* ]]; then
    sed -i 's/CONFIG_RTE_LIBRTE_MLX5_PMD=n/CONFIG_RTE_LIBRTE_MLX5_PMD=y/' config/common_base
  else
    sed -i 's/CONFIG_RTE_LIBRTE_MLX5_PMD=y/CONFIG_RTE_LIBRTE_MLX5_PMD=n/' config/common_base
  fi
  if [[ $@ == *'MLX4'* ]]; then
    sed -i 's/CONFIG_RTE_LIBRTE_MLX4_PMD=n/CONFIG_RTE_LIBRTE_MLX4_PMD=y/' config/common_base
  else
    sed -i 's/CONFIG_RTE_LIBRTE_MLX4_PMD=y/CONFIG_RTE_LIBRTE_MLX4_PMD=n/' config/common_base
  fi

  make defconfig T=x86_64-native-linuxapp-gcc
  make EXTRA_CFLAGS="${DPDK_ARGS}" -j

fi

if [[ $@ == *'INSTALL'* ]]; then
  if [[ $@ == *'CONDA'* ]]; then
    make install-sdk install-runtime prefix=${CONDA_PREFIX}
  else
    make install
  fi
fi

cd ../..

if [[ $@ != *'SKIP_DAIET'* ]]; then
  # Build DAIET
  make clean
  rm -rf build
  EXTRA_CXX_FLAGS=${DAIET_EXTRA_CXX_FLAGS} make ${DAIET_ARGS} -j
fi

if [[ $@ == *'INSTALL'* ]]; then
  if [[ $@ == *'CONDA'* ]]; then
    make libinstall PREFIX=${CONDA_PREFIX}
  else
    make libinstall
  fi
fi

cd ../gloo

if [[ $@ != *'SKIP_GLOO'* ]]; then
  # Build Gloo
  rm -rf build
  mkdir build
  cd build

  if [[ $@ == *'DEBUG'* ]]; then
    CXXFLAGS='-g -O0' cmake -DUSE_DAIET=1 -DUSE_REDIS=1 -DUSE_AVX=1 $GLOO_CMAKE_ARGS ..
  else
    cmake -DBUILD_TEST=OFF -DBUILD_BENCHMARK=OFF -DUSE_DAIET=1 -DUSE_REDIS=1 -DUSE_AVX=1 $GLOO_CMAKE_ARGS ..
  fi

  make -j
  cd ..
fi

if [[ $@ == *'INSTALL'* ]]; then
  cd build
  if [[ $@ == *'CONDA'* ]]; then
    cmake -DCMAKE_INSTALL_PREFIX=${CONDA_PREFIX} ..
  fi
  make install
  cd ..
fi

# Build experiments
cd ../daiet/experiments/exp1/
if [[ $@ != *'SKIP_EXPS'* ]]; then
  mkdir -p build
  cd build
  find . ! -name 'daiet.cfg'   ! -name '.'  ! -name '..' -exec rm -rf {} +

  cmake ${EXP_ARGS} ..

  make -j
  cd ..
fi

cd ../exp2
if [[ $@ != *'SKIP_EXPS'* ]]; then
  mkdir -p build
  cd build
  find . ! -name 'daiet.cfg'   ! -name '.'  ! -name '..' -exec rm -rf {} +

  cmake ${EXP_ARGS} ..

  make -j
  cd ..
fi

# Build example
cd ../../example/
if [[ $@ != *'SKIP_EXAMPLE'* ]]; then
  mkdir -p build
  cd build
  find . ! -name 'daiet.cfg'   ! -name '.'  ! -name '..' -exec rm -rf {} +

  cmake ${EXP_ARGS} ..

  make -j
  cd ..
fi

# Build dedicated PS
cd ../ps
if [[ $@ != *'SKIP_PS'* ]]; then
  make clean
  make ${PS_ARGS} -j
fi

if [[ $@ == *'PYTORCH'* ]]; then
  cd $CWD
  cd pytorch
  if [[ $@ == *'OFFLOAD_BITMAP'* ]]; then
    sed -i 's/#ifdef OFFLOAD_BITMAP/#ifndef OFFLOAD_BITMAP/' torch/lib/c10d/ProcessGroupGloo.cpp
    sed -i 's/#ifdef OFFLOAD_BITMAP/#ifndef OFFLOAD_BITMAP/' ${CONDA_PREFIX}/include/daiet/DaietContext.hpp
  else
    sed -i 's/#ifndef OFFLOAD_BITMAP/#ifdef OFFLOAD_BITMAP/' torch/lib/c10d/ProcessGroupGloo.cpp
    sed -i 's/#ifndef OFFLOAD_BITMAP/#ifdef OFFLOAD_BITMAP/' ${CONDA_PREFIX}/include/daiet/DaietContext.hpp
  fi
  if [[ $@ == *'RANDOMK'* ]]; then
    sed -i 's/#ifdef RANDOMK/#ifndef RANDOMK/' torch/lib/c10d/ProcessGroupNCCL.cpp
    sed -i 's/#ifdef RANDOMK/#ifndef RANDOMK/' torch/lib/c10d/ProcessGroupNCCL.hpp
    sed -i 's/#ifdef RANDOMK/#ifndef RANDOMK/' torch/lib/c10d/ProcessGroupGloo.cpp
    sed -i 's/#ifdef RANDOMK/#ifndef RANDOMK/' torch/lib/c10d/ProcessGroupGloo.hpp
    sed -i 's/#ifdef RANDOMK/#ifndef RANDOMK/' torch/lib/c10d/ProcessGroup.hpp
    sed -i 's/#ifdef RANDOMK/#ifndef RANDOMK/' torch/csrc/distributed/c10d/reducer.cpp
    sed -i 's/#ifdef RANDOMK/#ifndef RANDOMK/' torch/csrc/distributed/c10d/reducer.h
  else
    sed -i 's/#ifdef RANDOMK/#ifndef RANDOMK/' torch/lib/c10d/ProcessGroupNCCL.cpp
    sed -i 's/#ifdef RANDOMK/#ifndef RANDOMK/' torch/lib/c10d/ProcessGroupNCCL.hpp
    sed -i 's/#ifndef RANDOMK/#ifdef RANDOMK/' torch/lib/c10d/ProcessGroupGloo.cpp
    sed -i 's/#ifndef RANDOMK/#ifdef RANDOMK/' torch/lib/c10d/ProcessGroupGloo.hpp
    sed -i 's/#ifndef RANDOMK/#ifdef RANDOMK/' torch/lib/c10d/ProcessGroup.hpp
    sed -i 's/#ifndef RANDOMK/#ifdef RANDOMK/' torch/csrc/distributed/c10d/reducer.cpp
    sed -i 's/#ifndef RANDOMK/#ifdef RANDOMK/' torch/csrc/distributed/c10d/reducer.h
  fi
  USE_SYSTEM_NCCL=1 NCCL_INCLUDE_DIR=${CONDA_PREFIX}/include NCCL_LIB_DIR=${CONDA_PREFIX}/lib ${CONDA_PREFIX}/bin/python setup.py install --prefix=${CONDA_PREFIX} --record=`basename ${CONDA_PREFIX}`_files.txt
  cd $CWD/daiet
  if ${CONDA_PREFIX}/bin/python -c "import apex"; then
    echo "apex installed"
  else
    echo "install apex"
    cd $CWD
    cd apex
    ${CONDA_PREFIX}/bin/python setup.py install --cpp_ext --cuda_ext --prefix=${CONDA_PREFIX} --record=`basename ${CONDA_PREFIX}`_files.txt
  fi;
  cd $CWD/daiet
  if ${CONDA_PREFIX}/bin/python -c "import torchvision"; then
    echo "torchvision installed"
  else
    echo "install torchvision"
    cd $CWD
    cd torchvision
    ${CONDA_PREFIX}/bin/python setup.py install --prefix=${CONDA_PREFIX} --record=`basename ${CONDA_PREFIX}`_files.txt
  fi;
fi

if [[ $@ == *'HOROVOD'* ]]; then
    cd $CWD
    if [[ $@ == *'OFFLOAD_BITMAP'* ]]; then
      export OFFLOAD_BITMAP=1
    else
      export OFFLOAD_BITMAP=0
    fi
    if [[ $@ == *'HOROVOD_NCCL'* ]]; then
      export HOROVOD_NCCL_LINK=SHARED
      export HOROVOD_NCCL_HOME=${CONDA_PREFIX}
      export HOROVOD_CUDA_HOME=${CONDA_PREFIX}
      export HOROVOD_GPU_ALLREDUCE=NCCL
    else
      unset HOROVOD_NCCL_LINK
      unset HOROVOD_NCCL_HOME
      unset HOROVOD_CUDA_HOME
      unset HOROVOD_GPU_ALLREDUCE
    fi
    HOROVOD_WITH_GLOO=1 ${CONDA_PREFIX}/bin/pip install --no-cache-dir ./horovod
fi
unset OFFLOAD_BITMAP
cd $CWD

if ${CONDA_PREFIX}/bin/python -c "from nvidia import dali"; then
  echo "dali installed"
else
  ${CONDA_PREFIX}/bin/pip install --extra-index-url https://developer.download.nvidia.com/compute/redist/cuda/10.0 nvidia-dali
fi
if ${CONDA_PREFIX}/bin/python -c "import SSD"; then
  echo "SSD installed"
else
  ${CONDA_PREFIX}/bin/pip install -v ./scripts/nvidia-examples/PyTorch/Detection/SSD
fi
