ARG OROCOS_ROCK_BASE_IMAGE=ubuntu:24.04
ARG OROCOS_PREFIX=/opt/orocos

FROM ${OROCOS_ROCK_BASE_IMAGE} AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG OROCOS_PREFIX

USER root

ENV LANG=C.UTF-8
ENV OROCOS_PREFIX=${OROCOS_PREFIX}
ENV SHELL=/bin/bash
# Keep Orocos/Rock package builds on their own CMake discovery path even when
# the caller provides a base image with a toolchain file configured.
ENV CMAKE_TOOLCHAIN_FILE=

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        libboost-dev \
        libboost-filesystem-dev \
        libboost-graph-dev \
        libboost-iostreams-dev \
        libboost-program-options-dev \
        libboost-regex-dev \
        libboost-system-dev \
        libboost-thread-dev \
        libncurses5-dev \
        libomniorb4-dev \
        libxml2-dev \
        libxml-xpath-perl \
        lsb-release \
        omniidl \
        pkg-config \
        python3 \
        python3-dev \
        python3-pip \
        ruby \
        ruby-dev \
        sudo \
        xz-utils && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash ubuntu && \
    printf 'ubuntu ALL=(ALL) NOPASSWD:ALL\n' >/etc/sudoers.d/ubuntu && \
    chmod 0440 /etc/sudoers.d/ubuntu

WORKDIR /opt/orocos-rock
COPY --chown=ubuntu:ubuntu . .
RUN mkdir -p "$OROCOS_PREFIX" && \
    chown -R ubuntu:ubuntu /opt/orocos-rock "$OROCOS_PREFIX"

SHELL ["/bin/bash", "-lc"]

USER ubuntu

RUN ./tools/install-autoproj.sh
RUN ./tools/check-autoproj-policy.rb
RUN ./tools/bootstrap.sh --prefix "$OROCOS_PREFIX"
RUN ./tools/install.sh --prefix "$OROCOS_PREFIX"
RUN ./tools/validate-install.sh --prefix "$OROCOS_PREFIX"

FROM ${OROCOS_ROCK_BASE_IMAGE} AS final

ARG DEBIAN_FRONTEND=noninteractive
ARG OROCOS_PREFIX

USER root

ENV LANG=C.UTF-8
ENV OROCOS_PREFIX=${OROCOS_PREFIX}
ENV SHELL=/bin/bash

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        git \
        libboost-dev \
        libboost-filesystem-dev \
        libboost-graph-dev \
        libboost-iostreams-dev \
        libboost-program-options-dev \
        libboost-regex-dev \
        libboost-system-dev \
        libboost-thread-dev \
        libncurses5-dev \
        libomniorb4-dev \
        libxml2-dev \
        libxml-xpath-perl \
        omniidl \
        pkg-config \
        python3 \
        python3-dev \
        ruby \
        ruby-dev \
        sudo && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash ubuntu && \
    printf 'ubuntu ALL=(ALL) NOPASSWD:ALL\n' >/etc/sudoers.d/ubuntu && \
    chmod 0440 /etc/sudoers.d/ubuntu

COPY --from=builder --chown=ubuntu:ubuntu ${OROCOS_PREFIX} ${OROCOS_PREFIX}

SHELL ["/bin/bash", "-lc"]

USER ubuntu
WORKDIR /home/ubuntu

RUN test ! -e /opt/orocos-rock && \
    source "$OROCOS_PREFIX/dev-env.sh" && \
    ! command -v autoproj && \
    command -v deployer-gnulinux && \
    command -v orogen && \
    command -v typegen

CMD ["bash", "-lc", "source \"$OROCOS_PREFIX/dev-env.sh\" && exec bash"]
