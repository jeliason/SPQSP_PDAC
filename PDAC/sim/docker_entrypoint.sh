#!/bin/bash
# ============================================================================
# docker_entrypoint.sh — Pull latest code, incremental build, run benchmark
#
# FLAMEGPU2 is already compiled in the image. Only our source files recompile.
# For A/B worktree builds, the pre-built FLAMEGPU2 cache is copied in so the
# worktree build also only recompiles simulation code (~10 sec vs ~10 min).
# ============================================================================

set -euo pipefail

REPO_DIR="/opt/spqsp/SPQSP_PDAC"
SIM_DIR="${REPO_DIR}/PDAC/sim"
FLAMEGPU_CACHE="/opt/flamegpu_cache"
CUDA_ARCH="${CUDA_ARCH:-80}"
STEPS=200

# Parse args — pass everything through to benchmark_io.sh except what we handle
BENCHMARK_ARGS=()
SKIP_PULL=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --steps) STEPS="$2"; shift 2 ;;
        --skip-pull) SKIP_PULL=true; shift ;;
        *) BENCHMARK_ARGS+=("$1"); shift ;;
    esac
done

# Pull latest code
if ! $SKIP_PULL; then
    echo "=== Pulling latest code ==="
    cd "$REPO_DIR"
    git fetch origin
    git reset --hard origin/io-optimization
fi

cd "$SIM_DIR"

# Incremental rebuild of current tree (~10 sec, FLAMEGPU2 already built)
echo ""
echo "=== Rebuilding current tree (incremental) ==="
cmake --build build --parallel "$(nproc)"

echo ""
echo "=== Running A/B benchmark (${STEPS} steps) ==="

# Patch benchmark_io.sh build_binary to reuse FLAMEGPU2 cache for worktree builds
export FLAMEGPU_CACHE
export CUDA_ARCH

chmod +x benchmark_io.sh
./benchmark_io.sh \
    --ab HEAD~1 \
    --steps "$STEPS" \
    --cuda-arch "$CUDA_ARCH" \
    --sundials-dir /usr/local \
    "${BENCHMARK_ARGS[@]}"

echo ""
echo "=== Done! ==="
cat benchmark_results/ab_*/benchmark_report.txt 2>/dev/null || true