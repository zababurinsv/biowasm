#!/bin/bash

# This script compiles a tool to WebAssembly and is invoked by the Makefile.

usage="Usage: ./compile.sh toolName toolVersion toolBranch targetName"
TOOL=${1?$usage}
VERSION=${2?$usage}
BRANCH=${3?$usage}
TARGET=${4?$usage}
DIR_TOOLS=tools/

# ------------------------------------------------------------------------------
# Initialize
# ------------------------------------------------------------------------------

# Load target Emscripten flags
. ./config/shared.$TARGET.sh

# Prep build/ folder
cd "${DIR_TOOLS}/${TOOL}/"
mkdir -p build

# ------------------------------------------------------------------------------
# Setup codebase
# ------------------------------------------------------------------------------

echo "——————————————————————————————————————————————————"
echo "🧬 Processing $TOOL v$VERSION @ branch '$BRANCH'..."
echo "——————————————————————————————————————————————————"

# Base package isn't a repo
if [[ "$TOOL" != "base" ]]; then
    cd src/

    # Go to branch/tag of interest (clean up previous iterations)
    git reset --hard
    git clean -f -d
    git fetch --all
    git checkout "$BRANCH"

    # Apply patches, if any
    patch_file=../patches/${BRANCH}.patch
    if [[ -f "$patch_file" ]]; then
        echo "Applying patch file <$patch_file>"
        git apply -v $patch_file
    else
        echo "No patch file found at <$patch_file>"
    fi

    cd ../
fi

# ------------------------------------------------------------------------------
# Compile tool
# ------------------------------------------------------------------------------

echo "——————————————————————————————————————————————————"
echo "🧬 Compiling $TOOL v$VERSION to WebAssembly..."
echo "——————————————————————————————————————————————————"
./compile.sh

# ------------------------------------------------------------------------------
# Finalize
# ------------------------------------------------------------------------------

for glueCode in $(ls build/*.js);
do
    # TODO: Remove this once fixed in Emscripten
    # Patch Emscripten bug #12367 - see <https://github.com/emscripten-core/emscripten/issues/12367>
    sed -i 's/var stat=stream.node.mount.opts.fs.fstat(stream.nfd);/var stat=stream.node.node_ops.getattr(stream.node);/g' $glueCode
    # TODO: Remove this once fixed in Emscripten
    # Without this patch, invalid file paths throw instead of returning an error. This only seems to happen
    # when accessing an invalid file in a path that corresponds to a symlink within a PROXYFS file system ¯\_(ツ)_/¯
    # This isn't used that often but does otherwise break samtools commands that look for a .csi index before
    # looking for a .bai index.
    sed -i 's/return-54}throw e/return-54}return-54/g' $glueCode

    # Prepend info about biowasm
    echo '// Auto-generated by biowasm; see biowasm.com for details.' > "${glueCode}.tmp"
    cat "$glueCode" >> "${glueCode}.tmp"
    mv "${glueCode}.tmp" "$glueCode"
done

# Copy over (or create) config.json file
if [[ -f "configs/${BRANCH}.json" ]]; then
    cp "configs/${BRANCH}.json" "build/config.json"
else
    echo '{"wasm-features":[]}' > "build/config.json"
fi
