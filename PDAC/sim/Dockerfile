# ============================================================================
# SPQSP_PDAC simulation environment
#
# Pre-built FLAMEGPU2 + SUNDIALS + Boost so incremental builds take ~10 sec.
#
# Build:
#   docker build -t spqsp-pdac:latest .
#   docker build --build-arg CUDA_ARCH=89 -t spqsp-pdac:l40s .
#
# Run (interactive shell):
#   docker run --gpus all -it spqsp-pdac:latest
#
# Run a simulation directly:
#   docker run --gpus all spqsp-pdac:latest ./build/bin/pdac -p resource/param_all_test.xml -s 200
# ============================================================================

FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        cmake g++ git ca-certificates curl \
        libboost-serialization-dev \
        vim less python3 \
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

# Clone repo and do a full build to cache FLAMEGPU2 compilation
ARG CUDA_ARCH=80
ARG BRANCH=io-optimization

WORKDIR /workspace
RUN git clone --branch ${BRANCH} https://github.com/jeliason/SPQSP_PDAC.git && \
    cd SPQSP_PDAC/PDAC/sim && \
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
        -DSUNDIALS_DIR=/usr/local && \
    cmake --build build --parallel $(nproc)

WORKDIR /workspace/SPQSP_PDAC/PDAC/sim
CMD ["/bin/bash"]