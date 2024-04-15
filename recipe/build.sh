#!/bin/bash

set -exuo pipefail

export PYPI_RELEASE=1
export CMAKE_GENERATOR=Ninja
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CMAKE_BUILD_PARALLEL_LEVEL=""
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
export CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_PREFIX_PATH=${PREFIX};${SP_DIR} -DPython_EXECUTABLE=$PYTHON"

$PYTHON -m pip install git+https://github.com/wjakob/nanobind.git
$PYTHON -m pip install . -vv
