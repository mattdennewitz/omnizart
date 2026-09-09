#!/bin/bash

set -e

# Rebuilds the bundled NNLS Chroma Vamp plugin from source.
#
# Omnizart ships prebuilt NNLS Chroma binaries under omnizart/resource/vamp/, and
# omnizart/__init__.py points VAMP_PATH at that directory. The chord application loads
# the plugin from there through vampyhost. A binary that does not match the host
# architecture makes `omnizart chord transcribe` fail with a bare
# "TypeError: Failed to load plugin: nnls-chroma:nnls-chroma".
#
# On macOS the script builds the requested architecture and merges it into the existing
# universal binary with lipo, so slices that are already shipped are preserved untouched.
#
# Usage:
#     ./scripts/build_vamp_plugin.sh            # build for the current architecture
#     ./scripts/build_vamp_plugin.sh arm64      # build a specific macOS architecture
#     ./scripts/build_vamp_plugin.sh --installed  # patch the installed omnizart
#
# By default the rebuilt plugin is written into this checkout. Pass --installed
# to write it into the omnizart package of the active environment instead, which
# is what you want after `pip install omnizart`, since the plugin is loaded from
# wherever the package lives rather than from a source tree.
#
# Requirements:
#     macOS  brew install vamp-plugin-sdk boost
#     Linux  apt-get install libvamp-sdk2v5 vamp-plugin-sdk libboost-dev

# Upstream source of the plugin: GPL-2.0, https://github.com/c4dm/nnls-chroma
NNLS_REPO="https://github.com/c4dm/nnls-chroma.git"
NNLS_COMMIT="4c5f214a75cb354f8d8c933e161377c5b4d83713"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ARCH=""
TARGET_INSTALLED=false
for arg in "$@"; do
    case "$arg" in
        --installed) TARGET_INSTALLED=true ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *) ARCH="$arg" ;;
    esac
done
ARCH="${ARCH:-$(uname -m)}"

if [ "$TARGET_INSTALLED" = true ]; then
    # Resolve the plugin directory of the omnizart on the current PYTHONPATH.
    VAMP_DIR="$(python -c 'import os, omnizart; print(os.path.join(os.path.dirname(omnizart.__file__), "resource", "vamp"))' 2>/dev/null)"
    if [ -z "$VAMP_DIR" ] || [ ! -d "$VAMP_DIR" ]; then
        echo "Could not locate an installed omnizart. Activate the environment first." >&2
        exit 1
    fi
else
    VAMP_DIR="$REPO_ROOT/omnizart/resource/vamp"
fi
echo "Target: $VAMP_DIR"


fetch_source() {
    echo "Fetching nnls-chroma at $NNLS_COMMIT"
    git clone --quiet "$NNLS_REPO" "$WORK_DIR/nnls-chroma"
    git -C "$WORK_DIR/nnls-chroma" checkout --quiet "$NNLS_COMMIT"
}


build_macos() {
    local prefix
    prefix="$(brew --prefix)"

    if [ ! -f "$prefix/lib/libvamp-sdk.a" ]; then
        echo "Missing Vamp SDK. Run: brew install vamp-plugin-sdk boost" >&2
        exit 1
    fi

    echo "Building nnls-chroma for $ARCH"
    make -C "$WORK_DIR/nnls-chroma" -f Makefile.osx \
        VAMP_SDK_DIR="$prefix/include" \
        BOOST_ROOT="$prefix/include" \
        ARCHFLAGS="-arch $ARCH -mmacosx-version-min=11.0" \
        LDFLAGS="-arch $ARCH -mmacosx-version-min=11.0 -dynamiclib \
                 -install_name nnls-chroma.dylib $prefix/lib/libvamp-sdk.a \
                 -exported_symbols_list vamp-plugin.list -framework Accelerate" \
        >/dev/null

    # Merging rather than overwriting keeps every architecture already shipped intact.
    # The freshly built slice carries the ad-hoc signature that arm64 requires, and lipo
    # copies slices verbatim, so the result must not be re-signed afterwards: signing the
    # universal binary would rewrite the Intel slices as well.
    local built="$WORK_DIR/nnls-chroma/nnls-chroma.dylib"
    local target="$VAMP_DIR/nnls-chroma.dylib"
    local keep=""

    if [ -f "$target" ]; then
        keep="$(lipo -archs "$target" | tr ' ' '\n' | grep -vx "$ARCH" | tr '\n' ' ')"
    fi

    if [ -z "$(echo "$keep" | xargs)" ]; then
        cp "$built" "$target"
    else
        local extract_args=()
        for slice in $keep; do
            extract_args+=(-extract "$slice")
        done
        lipo "$target" "${extract_args[@]}" -output "$WORK_DIR/existing.dylib"
        lipo -create "$WORK_DIR/existing.dylib" "$built" -output "$target"
    fi

    echo "Updated $target"
    lipo -info "$target"
}


build_linux() {
    echo "Building nnls-chroma for $ARCH"
    make -C "$WORK_DIR/nnls-chroma" -f Makefile.linux >/dev/null
    cp "$WORK_DIR/nnls-chroma/nnls-chroma.so" "$VAMP_DIR/nnls-chroma.so"
    echo "Updated $VAMP_DIR/nnls-chroma.so"
}


verify() {
    echo
    echo "Verifying the plugin loads on this machine"
    python -c "
import omnizart  # sets VAMP_PATH
import vampyhost
vampyhost.load_plugin('nnls-chroma:nnls-chroma', 44100, 0).unload()
print('nnls-chroma loaded successfully')
"
}


fetch_source
case "$(uname -s)" in
    Darwin) build_macos ;;
    Linux)  build_linux ;;
    *)      echo "Unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac
verify
