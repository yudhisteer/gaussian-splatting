# Stage 1: COLMAP builder
FROM ubuntu:22.04 AS colmap-builder
ENV DEBIAN_FRONTEND=noninteractive

# Base packages and CUDA installation
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget ca-certificates gnupg && \
    wget --no-check-certificate https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb && \
    dpkg -i cuda-keyring_1.0-1_all.deb && \
    apt-get update && apt-get install -y --no-install-recommends cuda-11-8 && \
    rm -rf /var/lib/apt/lists/* *.deb

# Set CUDA environment
ENV PATH="/usr/local/cuda-11.8/bin:${PATH}"
ENV LD_LIBRARY_PATH=/usr/local/cuda-11.8/lib64
ENV CUDA_HOME=/usr/local/cuda-11.8

# Install COLMAP dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    ninja-build \
    git \
    libboost-all-dev \
    libeigen3-dev \
    libflann-dev \
    libfreeimage-dev \
    libgoogle-glog-dev \
    libgtest-dev \
    libsqlite3-dev \
    libglew-dev \
    qtbase5-dev \
    libqt5opengl5-dev \
    libcgal-dev \
    libceres-dev \
    libopencv-dev \
    libglfw3-dev \
    freeglut3-dev \
    libmetis-dev \
    libassimp-dev \
    libgtk-3-dev \
    libavdevice-dev \
    libavcodec-dev \
    libxxf86vm-dev \
    libembree-dev \
    gcc-10 \
    g++-10 \
    python3 \
    python3-pip \
    ffmpeg \
    libtiff-dev \
    libtiff5 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Set GCC-10
ENV CC=/usr/bin/gcc-10 \
    CXX=/usr/bin/g++-10 \
    CUDAHOSTCXX=/usr/bin/g++-10

# Build COLMAP
RUN cd /tmp && \
    git clone --depth 1 https://github.com/colmap/colmap.git && \
    cd colmap && \
    mkdir build && \
    cd build && \
    cmake .. -GNinja \
    -DCMAKE_CUDA_ARCHITECTURES="75;80;86" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON && \
    ninja && \
    ninja install

# Stage 2: Final image
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/cuda-11.8/bin:/root/miniconda3/bin:${PATH}"
ENV LD_LIBRARY_PATH=/usr/local/cuda-11.8/lib64
ENV CUDA_HOME=/usr/local/cuda-11.8
ENV TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6"
ENV FORCE_CUDA=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    git \
    cmake \
    libcgal-dev \
    libceres-dev \
    freeglut3-dev \
    qtbase5-dev \ 
    libqt5opengl5-dev \
    build-essential \
    ninja-build \
    gcc-10 \
    g++-10 \
    libglew-dev \
    libassimp-dev \
    libboost-all-dev \
    libgtk-3-dev \
    libopencv-dev \
    libglfw3-dev \
    libavdevice-dev \
    libavcodec-dev \
    libeigen3-dev \
    libxxf86vm-dev \
    libembree-dev \
    imagemagick && \
    rm -rf /var/lib/apt/lists/*

# Copy COLMAP from builder
COPY --from=colmap-builder /usr/local/bin/colmap /usr/local/bin/
COPY --from=colmap-builder /usr/local/lib/ /usr/local/lib/
COPY --from=colmap-builder /usr/local/cuda-11.8 /usr/local/cuda-11.8

# Install Miniconda
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /root/miniconda3 && \
    rm /tmp/miniconda.sh

# Set working directory and clone repository
WORKDIR /workspace
RUN git clone --recursive https://github.com/graphdeco-inria/gaussian-splatting && \
    git clone https://github.com/DepthAnything/Depth-Anything-V2.git

# Setup Conda environment
WORKDIR /workspace/gaussian-splatting
COPY environment.yml .
RUN conda env create -f environment.yml && \
    echo "conda activate gaussian_splatting" >> ~/.bashrc

# Build SIBR viewers
WORKDIR /workspace/gaussian-splatting/SIBR_viewers
RUN . /root/miniconda3/etc/profile.d/conda.sh && \
    conda activate gaussian_splatting && \
    cmake -Bbuild . -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j$(nproc) --target install

# Install accelerated rasterizer
WORKDIR /workspace/gaussian-splatting
RUN . /root/miniconda3/etc/profile.d/conda.sh && \
    conda activate gaussian_splatting && \
    pip uninstall diff-gaussian-rasterization -y && \
    cd submodules/diff-gaussian-rasterization && \
    rm -rf build && \
    git checkout 3dgs_accel && \
    pip install . && \
    cd .. && \
    cd simple-knn && \
    pip install .

WORKDIR /workspace/gaussian-splatting

CMD ["/bin/bash", "-c", "source /root/miniconda3/etc/profile.d/conda.sh && conda activate gaussian_splatting && /bin/bash"]