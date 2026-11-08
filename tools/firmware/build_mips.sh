#!/usr/bin/env bash
set -euo pipefail
cd /src
export SOURCE_DATE_EPOCH=1669852800 TZ=UTC
mkdir -p mips-build
cd mips-build
if [ ! -d musl-1.2.3 ]; then tar -xzf ../musl-1.2.3.tar.gz; fi
cd musl-1.2.3
if [ ! -f /opt/oj-mips/lib/libc.a ]; then
./configure --target=mipsel-linux-musl --prefix=/opt/oj-mips --disable-shared CC=mipsel-linux-gnu-gcc AR=mipsel-linux-gnu-ar RANLIB=mipsel-linux-gnu-ranlib CFLAGS='-Os -march=mips32r2 -mfp32'
make -j6
make install
fi
export CC=/opt/oj-mips/bin/musl-gcc
export AR=mipsel-linux-gnu-ar RANLIB=mipsel-linux-gnu-ranlib
export CFLAGS='-Os -march=mips32r2 -mfp32'
cd /src/mips-build
if [ ! -d protobuf-c-1.3.3 ]; then tar -xzf ../protobuf-c-v1.3.3.tar.gz; fi
cd protobuf-c-1.3.3
if [ ! -f /opt/oj-mips/lib/libprotobuf-c.a ]; then
./autogen.sh
./configure --host=mipsel-linux-musl --prefix=/opt/oj-mips --disable-shared --enable-static --disable-protoc
make -j6
make install
fi
cd /src/mips-build
if [ ! -d mosquitto-1.6.12 ]; then tar -xzf ../mosquitto-1.6.12.tar.gz; fi
cd mosquitto-1.6.12/lib
make -j6 libmosquitto.a WITH_TLS=no WITH_TLS_PSK=no WITH_SRV=no WITH_STATIC_LIBRARIES=yes
cp libmosquitto.a /opt/oj-mips/lib/
cp mosquitto.h /opt/oj-mips/include/
cd /src/mips-build
mkdir -p proto
protoc-c -I /src/esp32-code/jooki_v2/api --c_out=proto /src/esp32-code/jooki_v2/api/esp_hosted_config.proto /src/esp32-code/jooki_v2/api/esp_hosted_notif.proto
cd /src/ml-yocto-jooki/sw/controllers/esp32_ctrl
"$CC" $CFLAGS -static -DUSE_SYSLOG -D_GNU_SOURCE -D__FILENAME__=__FILE__ '-DMACHINE_H="./bsp/ml-j2000.h"' -I/opt/oj-mips/include -I/src/mips-build/proto -I. \
 esp32_ctrl.c ../common/mqtt_client.c ../common/logging.c ../common/utils.c platform_wrapper.c transport_pserial.c commands.c \
 /src/mips-build/proto/esp_hosted_config.pb-c.c /src/mips-build/proto/esp_hosted_notif.pb-c.c \
 -L/opt/oj-mips/lib -lmosquitto -lprotobuf-c -lpthread -lrt -lm -o /src/mips-build/esp32_ctrl
mipsel-linux-gnu-strip /src/mips-build/esp32_ctrl
mipsel-linux-gnu-readelf -h /src/mips-build/esp32_ctrl
mipsel-linux-gnu-readelf -d /src/mips-build/esp32_ctrl
sha256sum /src/mips-build/esp32_ctrl
