#!/bin/bash

# FLAGS: INSTALL MLX5 COLOCATED LATENCIES TIMESTAMPS TIMERS DEBUG HOROVOD CONDA OFFLOAD_BITMAP NOSCALING PYTORCH
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
fi
if [[ $@ == *'OFFLOAD_BITMAP'* ]]; then
  echo 'OFFLOAD_BITMAP SET'
  DAIET_ARGS+='OFFLOAD_BITMAP=ON '
  OFFLOAD_BITMAP=1
else
  OFFLOAD_BITMAP=0
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

  if [[ $@ == *'INSTALL'* ]]; then
    if [[ $@ == *'CONDA'* ]]; then
      make install-sdk install-runtime prefix=${CONDA_PREFIX}
    else
      make install
    fi
  fi
fi
cd ../..

# Build DAIET
make clean
rm -rf build
make ${DAIET_ARGS} -j

if [[ $@ == *'INSTALL'* ]]; then
  if [[ $@ == *'CONDA'* ]]; then
    make libinstall PREFIX=${CONDA_PREFIX}
  else
    make libinstall
  fi
fi

cd ../gloo

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

if [[ $@ == *'INSTALL'* ]] || [[ $@ == *'CONDA'* ]] ; then
  make install
fi

# Build experiments
cd ../../daiet/experiments/exp1/
mkdir -p build
cd build
find . ! -name 'daiet.cfg'   ! -name '.'  ! -name '..' -exec rm -rf {} +

cmake ${EXP_ARGS} ..

make -j

cd ../../exp2
mkdir -p build
cd build
find . ! -name 'daiet.cfg'   ! -name '.'  ! -name '..' -exec rm -rf {} +

cmake ${EXP_ARGS} ..

make -j

# Build example
cd ../../../example/
mkdir -p build
cd build
find . ! -name 'daiet.cfg'   ! -name '.'  ! -name '..' -exec rm -rf {} +

cmake ${EXP_ARGS} ..

make -j

# Build dedicated PS
cd ../../ps
make clean
make ${PS_ARGS} -j
cd $CWD


if [[ $@ == *'PYTORCH'* ]]; then
  find pytorch/ -name libc10d.a | xargs rm -f
  find pytorch/ -name libtorch_python.so | xargs rm -f
  cd pytorch
  OFFLOAD_BITMAP=${OFFLOAD_BITMAP} ${CONDA_PREFIX}/bin/python setup.py install
  cd $CWD
  if ! ${CONDA_PREFIX}/bin/python -c "import torchvision"; then
    echo "install torchvision"
    cd torchvision
    ${CONDA_PREFIX}/bin/python setup.py install
    cd $CWD
  fi
fi
