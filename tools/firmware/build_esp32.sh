#!/usr/bin/env bash
# Run in the pinned build container with the prepared archive root mounted at /src.
set -euo pipefail
cd /src
export JOOKI_SOURCE_DIR=/src MACHINE=ml-j2000
export ADF_PATH=/src/build-src/esp-adf
export IDF_PATH="${JOOKI_IDF_PATH:-$ADF_PATH/esp-idf}"
export SOURCE_DATE_EPOCH=1669852800 TZ=UTC PYTHONHASHSEED=0
mkdir -p generated/holtek
(cd register-map-tools && PYTHONPATH=$PWD python3 bin/generate-c-header.py ../config/jooki-v2-register-map.json ../generated/regmap.h)
export PIP_CONSTRAINT=/work/tools/firmware/python-constraints.txt
(cd "$IDF_PATH" && ./install.sh esp32)
# ESP-IDF's environment helper reads optional, unset shell variables.
set +u
source "$IDF_PATH/export.sh"
set -u
cd esp32-code/jooki_v2
# Compile dates in ESP-IDF respect SOURCE_DATE_EPOCH; always use the same /src path.
idf.py -B "${JOOKI_BUILD_DIR:-build}" -DPROJECT_VER=0x020C-oj-volume2 build
