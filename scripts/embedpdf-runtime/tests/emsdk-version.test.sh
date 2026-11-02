#!/usr/bin/env bash
# Copyright 2026 CloudPDF LTD
# SPDX-License-Identifier: Apache-2.0

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../emsdk-version.sh"
FAILURES=0

fail() { echo "FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "ok: $*"; }

FAKE="$(mktemp -d)"
trap 'rm -rf "$FAKE"' EXIT
VERSION_DIR="$FAKE/third_party/emsdk/upstream/emscripten"

# Writes the version file the way emscripten does, quoted.
activate() { mkdir -p "$VERSION_DIR"; printf '"%s"\n' "$1" > "$VERSION_DIR/emscripten-version.txt"; }
check() { PDF_RUNTIME_SOURCE_DIR="$FAKE" bash "$SCRIPT" --check "$1" 2>"$FAKE/stderr"; }

# Every wasm target maps to one version. The two differ on purpose: wasm32
# stays on the release workflow's 3.1.72, and wasm32-eh's exception flags were
# measured on 4.0.0.
for pair in wasm32=3.1.72 wasm32-eh=4.0.0; do
  t="${pair%%=*}" want="${pair#*=}"
  got="$(bash "$SCRIPT" "$t" 2>/dev/null)"
  [[ "$got" == "$want" ]] && pass "$t is pinned to $want" || fail "$t must pin $want, got '$got'"
done

# Every wasm target target-args.sh knows has a pin, so a new one can't build
# on whatever emsdk happens to be active.
wasm_targets="$(grep -E '^  [a-z0-9][a-z0-9 |-]*\)$' "$HERE/../target-args.sh" \
  | tr -d ' )' | tr '|' '\n' | grep '^wasm')"
[[ -n "$wasm_targets" ]] || fail "found no wasm targets in target-args.sh"
for t in $wasm_targets; do
  bash "$SCRIPT" "$t" 2>/dev/null | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
    && pass "target-args.sh's $t has an emsdk pin" || fail "target-args.sh's $t has no emsdk pin"
done
if bash "$SCRIPT" wasm32-new >/dev/null 2>&1; then
  fail "a wasm target without a pin exited 0"
else
  pass "a wasm target without a pin is rejected"
fi

# Non-wasm targets have no pin and pass the check even with no emsdk at all.
for t in darwin-arm64 linux-x64 ios-arm64; do
  [[ -z "$(bash "$SCRIPT" "$t")" ]] && pass "$t has no emsdk pin" || fail "$t must have no emsdk pin"
  check "$t" && pass "$t passes the check without an emsdk" || fail "$t must pass the check"
done

# The matching version passes; the other target's version refuses, and the
# message says how to activate the right one.
activate 3.1.72
check wasm32 && pass "wasm32 passes on 3.1.72" || fail "wasm32 must pass on 3.1.72"
if check wasm32-eh; then
  fail "wasm32-eh must refuse on 3.1.72"
else
  pass "wasm32-eh refuses on 3.1.72"
  grep -q 'emsdk activate 4.0.0' "$FAKE/stderr" \
    && pass "the refusal names the version to activate" || fail "the refusal must say 'emsdk activate 4.0.0'"
fi
activate 4.0.0
check wasm32-eh && pass "wasm32-eh passes on 4.0.0" || fail "wasm32-eh must pass on 4.0.0"
check wasm32 && fail "wasm32 must refuse on 4.0.0" || pass "wasm32 refuses on 4.0.0"

# No emsdk installed refuses a wasm target too.
rm -rf "$FAKE/third_party"
check wasm32 && fail "wasm32 must refuse with no emsdk" || pass "wasm32 refuses with no emsdk"

# build-target.sh must run the check before it syncs, patches or runs gn, or a
# wrong emsdk is found only when the compiler fails (or doesn't).
BUILD_TARGET_SH="$HERE/../build-target.sh"
check_line="$(grep -n 'emsdk-version.sh' "$BUILD_TARGET_SH" | head -1 | cut -d: -f1)"
for step in ensure-deps.sh apply-patches.sh 'gn gen'; do
  step_line="$(grep -n "$step" "$BUILD_TARGET_SH" | head -1 | cut -d: -f1)"
  if [[ -n "$check_line" && -n "$step_line" ]] && (( check_line < step_line )); then
    pass "build-target.sh checks emsdk before $step"
  else
    fail "build-target.sh must check emsdk before $step"
  fi
done

if (( FAILURES > 0 )); then
  echo "$FAILURES failure(s)" >&2
  exit 1
fi
echo "all emsdk-version assertions passed"
