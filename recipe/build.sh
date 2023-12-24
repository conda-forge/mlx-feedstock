#!/bin/bash

set -exuo pipefail

export PYPI_RELEASE=1
export CMAKE_GENERATOR=Ninja
export DEVELOPER_DIR=/Applications/Xcode_15.1.app/Contents/Developer
export CMAKE_BUILD_PARALLEL_LEVEL=""
export ARCHFLAGS="-arch x86_64 -arch arm64"
if [[ "${target_platform}" != "osx-arm64" ]]; then
  export BLAS_HOME=$PREFIX
  export CMAKE_ARGS="${CMAKE_ARGS} -DMLX_BUILD_METAL=OFF"
fi
$PYTHON -m pip install . -vv
