# ============================================================================
# SPQSP_PDAC simulation environment
#
# Build:
#   docker build -t spqsp-pdac:latest .
#   docker build --build-arg CUDA_ARCH=89 -t spqsp-pdac:l40s .
#
# Run (Docker):
#   docker run --gpus all -it spqsp-pdac:latest
#   docker run --gpus all -v ./results:/outputs spqsp-pdac:latest \
#       pdac -p resource/param_all_test.xml -s 500 --seed 42
#
# Run (Apptainer on HPC):
#   apptainer pull docker://ghcr.io/jeliason/spqsp-pdac:latest
#   apptainer exec --nv --bind ./results:/outputs spqsp-pdac_latest.sif \
#       pdac -p /workspace/resource/param_all_test.xml -s 500
#
# Sweep (SLURM array job):
#   apptainer exec --nv --bind ./results_${SLURM_ARRAY_TASK_ID}:/outputs \
#       spqsp-pdac_latest.sif pdac \
#       -p /workspace/resource/param_all_test.xml \
#       -s 500 --seed ${SLURM_ARRAY_TASK_ID}
# ============================================================================

FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        cmake g++ git ca-certificates curl \
        libboost-serialization-dev \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# SUNDIALS 6.3.0
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

# Clone and build (FLAMEGPU2 fetched via CMake FetchContent)
ARG CUDA_ARCH=80
ARG BRANCH=main

WORKDIR /workspace
RUN git clone --branch ${BRANCH} https://github.com/jeliason/SPQSP_PDAC.git && \
    cd SPQSP_PDAC/PDAC/sim && \
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
        -DSUNDIALS_DIR=/usr/local && \
    cmake --build build --parallel $(nproc)

# Put binary on PATH
RUN ln -s /workspace/SPQSP_PDAC/PDAC/sim/build/bin/pdac /usr/local/bin/pdac

# Output mount point
RUN mkdir -p /outputs
VOLUME /outputs

WORKDIR /workspace/SPQSP_PDAC/PDAC/sim
CMD ["/bin/bash"]

LABEL org.opencontainers.image.source="https://github.com/jeliason/SPQSP_PDAC"
LABEL org.opencontainers.image.description="SPQSP_PDAC GPU simulation (FLAMEGPU2 + QSP/SUNDIALS)"