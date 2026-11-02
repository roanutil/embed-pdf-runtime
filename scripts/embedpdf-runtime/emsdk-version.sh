#!/usr/bin/env bash
# Copyright 2026 CloudPDF LTD
# SPDX-License-Identifier: Apache-2.0
#
# The emsdk version each wasm target is built with, and the check that the
# active emsdk matches it. The pin lives here and nowhere else in the fork's
# scripts; build/toolchain/wasm/BUILD.gn only points at
# third_party/emsdk/upstream/emscripten/, whatever version is active there.
#
#   emsdk-version.sh <target>          print the target's pin (nothing for a
#                                      non-wasm target)
#   emsdk-version.sh --check <target>  exit 0 if the active emsdk matches the
#                                      pin, or the target isn't wasm; refuse
#                                      otherwise
#
# The check refuses instead of installing: an install downloads from the
# network, which a build script shouldn't do behind the caller's back.

set -euo pipefail

SOURCE_DIR="${PDF_RUNTIME_SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# wasm32: 3.1.72, the version the release workflow installs. Its clang crashes
# on libyuv's WASM SIMD rows, so target-args.sh turns libyuv off.
# wasm32-eh: 4.0.0, which config-eh.gn's exception flags were measured on
# (-sWASM_LEGACY_EXCEPTIONS=0, native setjmp/longjmp).
emsdk_pin() {
  case "$1" in
    wasm32) echo "3.1.72" ;;
    wasm32-eh) echo "4.0.0" ;;
    wasm32*)
      echo "no emsdk version pinned for $1; add it to $0" >&2
      return 1
      ;;
    *) ;;
  esac
}

# Prints the active emsdk's version without the quotes emscripten writes
# around it, or nothing when no emsdk is installed.
emsdk_active() {
  local file="$SOURCE_DIR/third_party/emsdk/upstream/emscripten/emscripten-version.txt"
  if [[ -f "$file" ]]; then
    tr -d '"[:space:]' < "$file"
  fi
}

usage() {
  echo "usage: $0 [--check] <target>" >&2
  exit 1
}

CHECK=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK=true
  shift
fi
TARGET="${1:-}"
[[ -n "$TARGET" ]] || usage

PIN="$(emsdk_pin "$TARGET")"

if [[ "$CHECK" == false ]]; then
  [[ -z "$PIN" ]] || echo "$PIN"
  exit 0
fi

[[ -n "$PIN" ]] || exit 0

ACTIVE="$(emsdk_active)"
if [[ "$ACTIVE" != "$PIN" ]]; then
  {
    echo "$TARGET is built with emsdk $PIN, but the active emsdk is ${ACTIVE:-not installed}"
    echo "(third_party/emsdk/upstream/emscripten/emscripten-version.txt). Activate $PIN:"
    echo "  $SOURCE_DIR/third_party/emsdk/emsdk install $PIN"
    echo "  $SOURCE_DIR/third_party/emsdk/emsdk activate $PIN"
    if [[ -z "$ACTIVE" ]]; then
      echo "If third_party/emsdk is missing, clone https://github.com/emscripten-core/emsdk.git there first."
    fi
  } >&2
  exit 1
fi
