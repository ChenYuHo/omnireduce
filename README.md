# omnireduce

## prepare submodules
```bash
./prepare.sh [--depth=10] # optional --depth shallow copys submodules
```

## offload bitmap
```bash
conda env create --prefix ../env-pytorch --file environment.yml
conda activate env-pytorch
./build_all.sh MLX5 CONDA INSTALL OFFLOAD_BITMAP NOSCALING PYTORCH
```
