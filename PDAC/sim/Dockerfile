# ============================================================================
# SPQSP_PDAC simulation environment
#
# Layer structure (top = changes least, bottom = changes most):
#   1. CUDA + system deps + SUNDIALS + Boost  (rarely changes)
#   2. FLAMEGPU2 library build                (only on FLAMEGPU version bump)
#   3. Clone + build simulation code          (changes with each code update)
#
# Build:
#   docker build -t spqsp-pdac:latest .
#   docker build --build-arg CUDA_ARCH=89 -t spqsp-pdac:l40s .
#
# Run (Docker):
#   docker run --gpus all -it spqsp-pdac:latest
#   docker run --gpus all -v ./results:/outputs spqsp-pdac:latest \
#       ./build/bin/pdac -p resource/param_all_test.xml -s 500 --seed 42
#
# Run (Apptainer/Singularity on HPC):
#   apptainer pull docker://ghcr.io/jeliason/spqsp-pdac:latest
#   apptainer run --nv spqsp-pdac_latest.sif
#   apptainer exec --nv --bind ./results:/outputs spqsp-pdac_latest.sif \
#       /workspace/SPQSP_PDAC/PDAC/sim/build/bin/pdac -p resource/param_all_test.xml -s 500
#
# Sweep example (SLURM array job):
#   apptainer exec --nv --bind ./results_${SLURM_ARRAY_TASK_ID}:/outputs \
#       spqsp-pdac_latest.sif \
#       /workspace/SPQSP_PDAC/PDAC/sim/build/bin/pdac \
#       -p resource/param_all_test.xml -s 500 --seed ${SLURM_ARRAY_TASK_ID}
# ============================================================================

# ==========================================================================
# Stage 1: Build everything
# ==========================================================================
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# ---- Layer 1: System dependencies ----
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        cmake g++ git ca-certificates curl \
        libboost-serialization-dev \
    && rm -rf /var/lib/apt/lists/*

# Build SUNDIALS 6.3.0 from source
ARG SUNDIALS_VER=6.3.0
RUN cd /tmp && \
    curl -sL "https://github.com/LLNL/sundials/releases/download/v${SUNDIALS_VER}/sundials-${SUNDIALS_VER}.tar.gz" | tar xz && \
    cd sundials-${SUNDIALS_VER} && \
    cmake -S . -B build \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DEXAMPLES_ENABLE_C=OFF \
        -DEXAMPLES_ENABLE_CXX=OFF && \
    cmake --build build --parallel $(nproc) && \
    cmake --install build && \
    rm -rf /tmp/sundials-${SUNDIALS_VER}

# ---- Layer 2: FLAMEGPU2 build (cached until version tag changes) ----
ARG CUDA_ARCH=80
ARG FLAMEGPU_TAG=v2.0.0-rc.4

WORKDIR /opt/flamegpu
RUN git clone --branch ${FLAMEGPU_TAG} --depth 1 https://github.com/FLAMEGPU/FLAMEGPU2.git src && \
    mkdir build && cd build && \
    cmake ../src \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
        -DFLAMEGPU_BUILD_TESTS=OFF \
        -DFLAMEGPU_BUILD_PYTHON=OFF && \
    cmake --build . --parallel $(nproc)

# ---- Layer 3: Simulation code ----
ARG BRANCH=main

WORKDIR /workspace
RUN git clone --branch ${BRANCH} https://github.com/jeliason/SPQSP_PDAC.git && \
    cd SPQSP_PDAC/PDAC/sim && \
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
        -DSUNDIALS_DIR=/usr/local \
        -DFLAMEGPU_ROOT=/opt/flamegpu/src && \
    cmake --build build --parallel $(nproc)

# ==========================================================================
# Stage 2: Runtime image (much smaller — no compilers)
# ==========================================================================
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        libboost-serialization1.83.0 \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# Copy SUNDIALS shared libraries
COPY --from=builder /usr/local/lib/libsundials_* /usr/local/lib/
RUN ldconfig

# Copy the compiled binary and resource files
COPY --from=builder /workspace/SPQSP_PDAC/PDAC/sim/build/bin/pdac /usr/local/bin/pdac
COPY --from=builder /workspace/SPQSP_PDAC/PDAC/sim/resource /workspace/resource
COPY --from=builder /workspace/SPQSP_PDAC/PDAC/sim/benchmark_io.sh /workspace/benchmark_io.sh
COPY --from=builder /workspace/SPQSP_PDAC/PDAC/sim/analyze_benchmark.py /workspace/analyze_benchmark.py

# Output directory — mount a host volume here for results
RUN mkdir -p /outputs
VOLUME /outputs

# Non-root user (required by some HPC platforms)
RUN useradd -m -s /bin/bash simuser
USER simuser

WORKDIR /workspace
CMD ["/bin/bash"]

# Labels for traceability
LABEL org.opencontainers.image.source="https://github.com/jeliason/SPQSP_PDAC"
LABEL org.opencontainers.image.description="SPQSP_PDAC GPU simulation (FLAMEGPU2 + QSP/SUNDIALS)"