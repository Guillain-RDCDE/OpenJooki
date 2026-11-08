FROM ubuntu:20.04@sha256:8feb4d8ca5354def3d8fce243717141ce31e2c428701f6682bd2fafe15388214
ENV DEBIAN_FRONTEND=noninteractive TZ=UTC SOURCE_DATE_EPOCH=1669852800
RUN apt-get update -qq && apt-get install -y -qq git wget curl ca-certificates python3 python3-pip python3-venv cmake ninja-build make gcc g++ gperf bison flex ccache libffi-dev libssl-dev dfu-util libusb-1.0-0 libncurses5 protobuf-c-compiler libprotobuf-c-dev gcc-mipsel-linux-gnu libc6-dev-mipsel-cross autoconf automake libtool pkg-config zlib1g-dev xz-utils > /tmp/deps.log
WORKDIR /src
