#!/bin/bash

set -exuo pipefail

export PYPI_RELEASE=1
export CMAKE_GENERATOR=Ninja
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CMAKE_BUILD_PARALLEL_LEVEL=""

# MLX compiles its Metal shaders by shelling out to `xcrun -sdk macosx metal`
# and decides which kernels to build from `xcrun -sdk macosx --show-sdk-version`
# -- both of which come from Xcode, not from the conda-provided sysroot in
# CONDA_BUILD_SYSROOT.  Each SDK tier is pinned to a runner whose default Xcode
# is already new enough (see github_actions_labels in
# recipe/conda_build_config.yaml), so this normally keeps the default; it is a
# guard against a runner image whose default Xcode drifts behind the tier, which
# would otherwise silently build the macOS 26 tier with the same kernels as the
# 14.5 one instead of failing.
if [[ "${target_platform}" == "osx-arm64" ]]; then
  # CONDA_BUILD_SYSROOT is exported by conda-forge-ci-setup and looks like
  # /opt/conda-sdks/MacOSX26.1.sdk; fall back to the deployment target, which is
  # what conda-forge-ci-setup itself defaults the SDK version to.
  wanted_sdk="${CONDA_BUILD_SYSROOT:-}"
  wanted_sdk="${wanted_sdk##*/MacOSX}"
  wanted_sdk="${wanted_sdk%.sdk}"
  if [[ ! "${wanted_sdk}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    wanted_sdk="${MACOSX_DEPLOYMENT_TARGET:-14.5}"
  fi

  # sort -V puts the greater version last, so "$a is at least $b" is
  # "sorting the pair leaves $a on the bottom".
  version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -1)" == "$1" ]]; }

  sdk_of() { DEVELOPER_DIR="$1" xcrun -sdk macosx --show-sdk-version 2>/dev/null; }

  default_sdk="$(sdk_of "${DEVELOPER_DIR}" || true)"
  echo "Default Xcode at ${DEVELOPER_DIR} provides the macOS ${default_sdk:-?} SDK"

  if [[ -z "${default_sdk}" ]] || ! version_ge "${default_sdk}" "${wanted_sdk}"; then
    best_dir=""
    best_sdk=""
    for candidate in /Applications/Xcode*.app/Contents/Developer; do
      [[ -d "${candidate}" ]] || continue
      candidate_sdk="$(sdk_of "${candidate}" || true)"
      [[ -n "${candidate_sdk}" ]] || continue
      version_ge "${candidate_sdk}" "${wanted_sdk}" || continue
      if [[ -z "${best_sdk}" ]] || version_ge "${candidate_sdk}" "${best_sdk}"; then
        best_sdk="${candidate_sdk}"
        best_dir="${candidate}"
      fi
    done
    if [[ -z "${best_dir}" ]]; then
      echo "ERROR: no installed Xcode provides a macOS ${wanted_sdk} SDK or newer." >&2
      ls -d /Applications/Xcode*.app >&2 || true
      exit 1
    fi
    export DEVELOPER_DIR="${best_dir}"
    echo "Selected Xcode at ${DEVELOPER_DIR} (macOS ${best_sdk} SDK) for the macOS ${wanted_sdk} tier"
  fi

  # The M-series NAX (MetalPerformancePrimitives / Metal 4) kernels are built
  # when the Metal toolchain's SDK is >= 26.2 and the deployment target is
  # >= 26.0 -- the same gate recipe/0002-*.patch leaves in CMake.  The 26.2 SDK
  # floor is a hard requirement: the 26.1 SDK has MetalPerformancePrimitives but
  # not the cooperative-tensor accessors the kernels call.  Note this is Xcode's
  # SDK, not CONDA_BUILD_SYSROOT: `xcrun metal` resolves framework headers from
  # the former, and conda-forge ships no Metal toolchain of its own.
  expect_nax=0
  toolchain_sdk="$(sdk_of "${DEVELOPER_DIR}" || true)"
  if version_ge "${toolchain_sdk:-0}" "26.2" && version_ge "${MACOSX_DEPLOYMENT_TARGET:-0}" "26.0"; then
    expect_nax=1
  fi
  echo "NAX kernels expected in mlx.metallib: ${expect_nax}"

  # Shipping the macOS 26 tier at all is only worth the extra build because of
  # these kernels, so refuse to publish one silently missing them -- otherwise a
  # runner image whose default Xcode slipped below 26.2 would quietly produce a
  # higher-build-number package no better than the 14.5 one.
  if version_ge "${MACOSX_DEPLOYMENT_TARGET:-0}" "26.0" && [[ "${expect_nax}" != "1" ]]; then
    echo "ERROR: the macOS ${MACOSX_DEPLOYMENT_TARGET} tier exists to ship the NAX kernels," >&2
    echo "       but the Metal toolchain SDK is ${toolchain_sdk:-unknown} (< 26.2)." >&2
    ls -d /Applications/Xcode*.app >&2 || true
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

if [[ "${target_platform}" == "osx-arm64" ]]; then
  # air-lld drops functions from a metallib when they were compiled for a newer
  # deployment target than the metallib is linked for, and it only warns.  Check
  # the shipped library directly rather than trusting the configure-time gate.
  "${PYTHON}" - "${PREFIX}/lib/mlx.metallib" "${expect_nax}" <<'EOF'
import sys

metallib, expect_nax = sys.argv[1], sys.argv[2] == "1"
# A NAX kernel's mangled entry point, which can only be present if
# steel_gemm_fused_nax.metal was actually compiled in and survived linking.
with open(metallib, "rb") as f:
    found = b"steel_gemm_fused_nax" in f.read()

if expect_nax and not found:
    sys.exit(f"ERROR: no NAX kernels in {metallib}; this tier is supposed to ship them")
if found and not expect_nax:
    sys.exit(f"ERROR: NAX kernels in {metallib}; this tier is not supposed to ship them")
print(f"OK: NAX kernels {'present in' if found else 'absent from'} {metallib}, as expected")
EOF
fi
