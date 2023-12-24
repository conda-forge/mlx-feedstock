#!/bin/bash

set -exuo pipefail

export PYPI_RELEASE=1
export CMAKE_GENERATOR=Ninja
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CMAKE_BUILD_PARALLEL_LEVEL=""
if [[ "${target_platform}" != "osx-arm64" ]]; then
  export BLAS_HOME=$PREFIX
  export CMAKE_ARGS="${CMAKE_ARGS} -DMLX_BUILD_METAL=OFF"
else
  export CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_OSX_ARCHITECTURES=arm64;x86_64"
fi
$PYTHON -m pip install . -vv
