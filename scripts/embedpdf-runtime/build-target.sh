#!/usr/bin/env bash
# Copyright 2026 CloudPDF LTD
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SOURCE_DIR="${PDF_RUNTIME_SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  echo "usage: $0 <target>" >&2
  exit 1
fi

if ! GN_ARGS="$("$SOURCE_DIR/scripts/embedpdf-runtime/target-args.sh" "$TARGET")"; then
  exit 1
fi

GN_TARGET_OS="$(sed -n 's/^target_os="\(.*\)"$/\1/p' <<<"$GN_ARGS")"
GN_TARGET_CPU="$(sed -n 's/^target_cpu="\(.*\)"$/\1/p' <<<"$GN_ARGS")"

PDF_RUNTIME_TARGET_OS_LIST="${PDF_RUNTIME_TARGET_OS_LIST:-$GN_TARGET_OS}" \
  "$SOURCE_DIR/scripts/embedpdf-runtime/ensure-deps.sh"

"$SOURCE_DIR/scripts/embedpdf-runtime/apply-patches.sh" "$TARGET"

if [[ "$TARGET" == linux-* ]]; then
  (
    cd "$SOURCE_DIR"
    build/install-build-deps.sh --no-prompt
    build/linux/sysroot_scripts/install-sysroot.py "--arch=$GN_TARGET_CPU"
  )
fi

OUT="$SOURCE_DIR/out/embedpdf-runtime/$TARGET"
mkdir -p "$OUT"

printf '%s\n' "$GN_ARGS" > "$OUT/args.gn"

(
  cd "$SOURCE_DIR"
  gn gen "$OUT"
  ninja -C "$OUT" pdfium
)

echo "$OUT"
