#!/bin/bash

set -exuo pipefail

export PYPI_RELEASE=1
export CMAKE_GENERATOR=Ninja
export CMAKE_BUILD_PARALLEL_LEVEL=""

# MLX builds without its Metal kernels, with no error, if it cannot find the
# Metal compiler. That comes from the runner's Xcode, which may lack the
# optional Metal Toolchain component.
if [[ "${target_platform}" == "osx-arm64" ]]; then
  if ! xcrun -sdk macosx metal --version >/dev/null 2>&1 || ! xcrun -sdk macosx metallib --version >/dev/null 2>&1; then
    echo "xcrun cannot find metal or metallib. Install the Metal Toolchain with:"
    echo "    xcodebuild -downloadComponent MetalToolchain"
    exit 1
  fi
fi

if [[ "${target_platform}" != "osx-arm64" ]]; then
  export BLAS_HOME=$PREFIX
  export CMAKE_ARGS="${CMAKE_ARGS} -DMLX_BUILD_METAL=OFF"
elif [[ "$target_platform" == "osx-arm64" && "${CONDA_BUILD_CROSS_COMPILATION:-0}" == "1" ]]; then
  export CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_OSX_ARCHITECTURES=arm64"
fi
if [[ "${target_platform}" == linux-* ]]; then
  export LDFLAGS="-lblas ${LDFLAGS}"
elif [[ "${target_platform}" == "osx-64" ]]; then
  export LDFLAGS="$LDFLAGS -llapacke -llapack"
fi
export CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_PREFIX_PATH=${PREFIX};${SP_DIR} -DPython_EXECUTABLE=$PYTHON -DPython_INCLUDE_DIR=${PREFIX}/include/python${PY_VER}"

$PYTHON -m pip install . -vv

