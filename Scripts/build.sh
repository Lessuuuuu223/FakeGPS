#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DYLIB_PATH="${BUILD_DIR}/FakeGPS.dylib"
ZIP_PATH="${BUILD_DIR}/FakeGPS.zip"
CHECKSUM_PATH="${BUILD_DIR}/SHA256SUMS.txt"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"

mkdir -p "${BUILD_DIR}"
rm -f "${DYLIB_PATH}" "${ZIP_PATH}" "${CHECKSUM_PATH}"

xcrun --sdk iphoneos clang \
    -arch arm64 \
    -miphoneos-version-min=13.0 \
    -isysroot "${SDK_PATH}" \
    -dynamiclib \
    -fobjc-arc \
    -fvisibility=hidden \
    -Wall \
    -Wextra \
    -Wno-unused-parameter \
    "${ROOT_DIR}"/Sources/*.m \
    -framework Foundation \
    -framework UIKit \
    -framework CoreGraphics \
    -framework CoreLocation \
    -framework MapKit \
    -Wl,-install_name,@executable_path/Frameworks/FakeGPS.dylib \
    -o "${DYLIB_PATH}"

file "${DYLIB_PATH}"
HEADER="$(otool -hv "${DYLIB_PATH}")"
printf '%s\n' "${HEADER}"
grep -Eq '(^|[[:space:]])(MH_)?DYLIB([[:space:]]|$)' <<< "${HEADER}"
grep -q 'ARM64' <<< "${HEADER}"

LOAD_COMMANDS="$(otool -l "${DYLIB_PATH}")"
MIN_VERSION="$(awk '
    /LC_VERSION_MIN_IPHONEOS/ { getline; getline; print $2; exit }
    /LC_BUILD_VERSION/ {
        while ((getline) > 0) {
            if ($1 == "minos") { print $2; exit }
            if ($1 == "cmd") { exit }
        }
    }
' <<< "${LOAD_COMMANDS}")"
if [[ "${MIN_VERSION}" != "13.0" ]]; then
    printf 'Expected iOS 13.0 minimum version, found: %s\n' "${MIN_VERSION:-missing}" >&2
    exit 1
fi

INSTALL_NAME="$(otool -D "${DYLIB_PATH}" | awk 'NR == 2 {print $1}')"
if [[ "${INSTALL_NAME}" != "@executable_path/Frameworks/FakeGPS.dylib" ]]; then
    printf 'Unexpected install name: %s\n' "${INSTALL_NAME:-missing}" >&2
    exit 1
fi

DEPENDENCIES="$(otool -L "${DYLIB_PATH}")"
printf '%s\n' "${DEPENDENCIES}"
if grep -Eiq 'CydiaSubstrate|libsubstrate|theos' <<< "${DEPENDENCIES}"; then
    printf 'Substrate/Theos dependency is not allowed.\n' >&2
    exit 1
fi

UNDEFINED_SYMBOLS="$(nm -u "${DYLIB_PATH}")"
if grep -q '_MSHookMessageEx' <<< "${UNDEFINED_SYMBOLS}"; then
    printf 'Unexpected Substrate symbol found.\n' >&2
    exit 1
fi

zip -q -j "${ZIP_PATH}" "${DYLIB_PATH}"
(
    cd "${BUILD_DIR}"
    shasum -a 256 FakeGPS.dylib FakeGPS.zip > SHA256SUMS.txt
)

printf '\nBuild completed:\n%s\n%s\n%s\n' "${DYLIB_PATH}" "${ZIP_PATH}" "${CHECKSUM_PATH}"
