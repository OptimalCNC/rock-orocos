FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG OROCOS_ROCK_PREFIX=/opt/orocos

ENV LANG=C.UTF-8
ENV OROCOS_ROCK_PREFIX=${OROCOS_ROCK_PREFIX}
ENV SHELL=/bin/bash

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
        xz-utils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/orocos-rock
COPY . .

SHELL ["/bin/bash", "-lc"]

RUN ./tools/install-autoproj.sh
RUN ./tools/check-autoproj-policy.rb
RUN ./tools/bootstrap.sh --prefix "$OROCOS_ROCK_PREFIX"
RUN ./tools/install.sh --prefix "$OROCOS_ROCK_PREFIX"
RUN ./tools/validate-install.sh --prefix "$OROCOS_ROCK_PREFIX"
CMD ["bash", "-lc", "source \"$OROCOS_ROCK_PREFIX/dev-env.sh\" && exec bash"]
