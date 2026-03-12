#!/bin/bash
# ============================================================================
# cloud_benchmark_setup.sh — One-shot setup for running I/O benchmarks on a
# fresh cloud GPU instance (Vast.ai, RunPod, Colab, etc.)
#
# Installs dependencies, clones the repo, builds, and runs the A/B benchmark.
#
# Usage:
#   curl -sSL <raw_url> | bash
#   # or
#   bash cloud_benchmark_setup.sh [--cuda-arch N]
#
# Assumes: Ubuntu-based image with CUDA toolkit already installed.
# ============================================================================

set -euo pipefail

# Auto-detect CUDA architecture from the GPU
detect_cuda_arch() {
    if command -v nvidia-smi &>/dev/null; then
        local gpu_name
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        case "$gpu_name" in
            *V100*)   echo 70 ;;
            *T4*)     echo 75 ;;
            *"RTX 20"*|*"RTX20"*) echo 75 ;;
            *A100*)   echo 80 ;;
            *A10*)    echo 80 ;;
            *"RTX 30"*|*"RTX30"*) echo 86 ;;
            *A40*)    echo 86 ;;
            *"RTX 40"*|*"RTX40"*) echo 89 ;;
            *L40*)    echo 89 ;;
            *"RTX 50"*|*"RTX50"*) echo 100 ;;
            *)
                echo "Unknown GPU: $gpu_name — defaulting to arch 80" >&2
                echo 80 ;;
        esac
    else
        echo "nvidia-smi not found — defaulting to arch 80" >&2
        echo 80
    fi
}

CUDA_ARCH=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --cuda-arch) CUDA_ARCH="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$CUDA_ARCH" ]]; then
    CUDA_ARCH=$(detect_cuda_arch)
fi

echo "============================================================"
echo "  Cloud GPU Benchmark Setup"
echo "  Detected CUDA architecture: $CUDA_ARCH"
echo "============================================================"

# ============================================================================
# 1. Install system dependencies
# ============================================================================
echo ""
echo "=== Installing dependencies ==="

apt-get update -qq
apt-get install -y -qq cmake g++ git libboost-serialization-dev > /dev/null 2>&1

# Install SUNDIALS 6 from source (not always in apt)
SUNDIALS_VER=6.3.0
SUNDIALS_PREFIX=/usr/local
if [[ ! -f "${SUNDIALS_PREFIX}/lib/libsundials_cvode.so" && \
      ! -f "${SUNDIALS_PREFIX}/lib/libsundials_cvode.a" && \
      ! -f "${SUNDIALS_PREFIX}/lib64/libsundials_cvode.so" && \
      ! -f "${SUNDIALS_PREFIX}/lib64/libsundials_cvode.a" ]]; then
    echo "  Building SUNDIALS ${SUNDIALS_VER} from source..."
    cd /tmp
    curl -sL "https://github.com/LLNL/sundials/releases/download/v${SUNDIALS_VER}/sundials-${SUNDIALS_VER}.tar.gz" | tar xz
    cd "sundials-${SUNDIALS_VER}"
    cmake -S . -B build \
        -DCMAKE_INSTALL_PREFIX="${SUNDIALS_PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DEXAMPLES_ENABLE_C=OFF \
        -DEXAMPLES_ENABLE_CXX=OFF \
        > /dev/null 2>&1
    cmake --build build --parallel "$(nproc)" > /dev/null 2>&1
    cmake --install build > /dev/null 2>&1
    echo "  SUNDIALS installed to ${SUNDIALS_PREFIX}"
    cd /
    rm -rf /tmp/sundials-${SUNDIALS_VER}
else
    echo "  SUNDIALS already installed."
fi

# ============================================================================
# 2. Clone and build
# ============================================================================
echo ""
echo "=== Cloning repository ==="

WORK_DIR="${HOME}/benchmark"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

if [[ -d "SPQSP_PDAC" ]]; then
    echo "  Repo already cloned, pulling latest..."
    cd SPQSP_PDAC
    git fetch origin
    git checkout io-optimization
    git pull origin io-optimization
else
    git clone --branch io-optimization https://github.com/jeliason/SPQSP_PDAC.git
    cd SPQSP_PDAC
fi

cd PDAC/sim

echo ""
echo "=== Building (CUDA arch ${CUDA_ARCH}) ==="

cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH" \
    -DSUNDIALS_DIR="${SUNDIALS_PREFIX}" \
    > build_config.log 2>&1

cmake --build build --parallel "$(nproc)" 2>&1 | tail -5

if [[ ! -x build/bin/pdac ]]; then
    echo "ERROR: Build failed. Check build_config.log"
    exit 1
fi

echo ""
echo "=== Build successful ==="
echo ""

# ============================================================================
# 3. Run benchmark
# ============================================================================
echo "=== Running A/B benchmark (HEAD~1 vs HEAD) ==="
echo ""

chmod +x benchmark_io.sh
./benchmark_io.sh --ab HEAD~1 --steps 50 --cuda-arch "$CUDA_ARCH"

echo ""
echo "=== Done! ==="
echo "Results in: $(pwd)/benchmark_results/"
echo ""
cat benchmark_results/ab_*/benchmark_report.txt 2>/dev/null || echo "Check benchmark_results/ for output."