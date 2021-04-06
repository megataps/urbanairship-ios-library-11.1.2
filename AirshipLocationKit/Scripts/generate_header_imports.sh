#!/bin/bash -ex

SCRIPT_DIRECTORY=`dirname "$0"`
ROOT_PATH="${SCRIPT_DIRECTORY}/.."

echo "${ROOT_PATH}"
TMP_LIB="${DERIVED_FILE_DIR}/GeneratedHeader"
TMP_LIB_HEADER="${TMP_LIB}/AirshipLocationLib.h"
SOURCE_LIB_HEADER="${ROOT_PATH}/AirshipLocationKit/AirshipLocationLib.h"

# Find all public headers, excluding AirshipLocationLib and UI
# Collect all headers as obj-c import statments into an umbrella header
rm "${TMP_LIB_HEADER}" 2>/dev/null || true
mkdir -p "${TMP_LIB}" && touch "${TMP_LIB_HEADER}"

echo "Generated file: ${TMP_LIB_HEADER}"

if [[ -d "${ROOT_PATH}"/AirshipLocationKit ]]; then
    find -s "${ROOT_PATH}"/AirshipLocationKit -type f -name '*.h' ! -name 'AirshipLocationLib.h' ! -name 'AirshipLocationKit.h' ! -name '*+Internal*.h' ! -path './UI/*' \
    -exec basename {} \; | awk '{print "#import \"" $1"\""}' >> "${TMP_LIB_HEADER}"
fi

# If there's already an AirshipLocationLib.h in the framework headers directory
if [ -a "${SOURCE_LIB_HEADER}" ]; then
    # If the contents haven't changed, exit early
    if diff -q "${SOURCE_LIB_HEADER}" "${TMP_LIB_HEADER}" > /dev/null; then
        exit 0
    fi
fi

echo "Generated file: ${SOURCE_LIB_HEADER}"

cp "${TMP_LIB_HEADER}" "${SOURCE_LIB_HEADER}"

