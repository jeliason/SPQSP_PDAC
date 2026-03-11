# Running I/O Benchmarks on Rockfish (JHU HPC)

## Prerequisites

- Access to a GPU allocation on Rockfish (`<PI_NAME>_gpu`)
- SSH access to Rockfish login nodes
- Your fork: `git@github.com:jeliason/SPQSP_PDAC.git`

## 1. Start an Interactive GPU Session

From a Rockfish login node:

```bash
interact -p a100 -g 1 -n 6 -t 01:00:00 -a apopel1_gpu -q qos_gpu
```

Replace `<PI_NAME>` with your PI's allocation name. To check your available accounts:

```bash
sacctmgr show assoc user=$USER format=account%30
```

### GPU Partition Options

| Partition | GPU    | VRAM  | Max Time |
|-----------|--------|-------|----------|
| `a100`    | A100   | 40 GB | 72 hrs   |
| `ica100`  | A100   | 80 GB | 72 hrs   |
| `l40s`    | L40s   | 48 GB | 24 hrs   |

## 2. Load Modules and Clone

```bash
module purge
module load GCC/12.3.0 CUDA/12.1.1 cmake sundials/6.3.0 Boost/1.82.0-GCC-12.3.0
git clone git@github.com:jeliason/SPQSP_PDAC.git
cd SPQSP_PDAC/PDAC/sim
```

If already cloned, just pull:

```bash
cd SPQSP_PDAC
git fetch origin
git checkout io-optimization
git pull
cd PDAC/sim
```

## 3. Build

First time (full build, ~5 min):

```bash
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_ARCHITECTURES=80 \
  -DSUNDIALS_DIR=/data/apps/extern/sundials/6.3.0 \
  -DBOOST_ROOT=/data/apps/extern/easybuild/Boost/1.82.0-GCC-12.3.0
cmake --build build --parallel $(nproc)
```

After code changes (incremental, ~10 sec):

```bash
cmake --build build --parallel $(nproc)
```

## 4. Run A/B Benchmark (old vs new)

```bash
./benchmark_io.sh --ab HEAD~1 --steps 50 --cuda-arch 80
```

This will:
1. Create a git worktree at the previous commit (old code)
2. Build the old binary in that worktree
3. Build the new binary from the current working tree
4. Run both through 3 I/O configs: `no_io`, `io_every_step`, `io_interval_5`
5. Print a head-to-head comparison report

Results are saved to `benchmark_results/ab_<timestamp>/`.

### Benchmark Options

```bash
# Compare against a specific commit
./benchmark_io.sh --ab adfa78e2 --steps 50 --cuda-arch 80

# More steps for more stable averages
./benchmark_io.sh --ab HEAD~1 --steps 100 --cuda-arch 80

# Custom output interval
./benchmark_io.sh --ab HEAD~1 --steps 50 --interval 10 --cuda-arch 80

# Re-run without rebuilding
./benchmark_io.sh --ab HEAD~1 --skip-build --steps 50

# Run current binary only (no A/B comparison)
./benchmark_io.sh --binary ./build/bin/pdac --steps 50
```

## 5. View Results

```bash
cat benchmark_results/ab_*/benchmark_report.txt
```

Or analyze a single run:

```bash
python3 analyze_benchmark.py --single benchmark_results/ab_*/new_working/io_every_step
```

## 6. Copy Results Off Cluster

From your local machine:

```bash
scp -r <user>@login.rockfish.jhu.edu:~/SPQSP_PDAC/PDAC/sim/benchmark_results ./
```
