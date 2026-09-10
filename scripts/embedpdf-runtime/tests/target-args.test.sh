#!/usr/bin/env bash
# Copyright 2026 CloudPDF LTD
# SPDX-License-Identifier: Apache-2.0

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../target-args.sh"
GOLDEN="${ARGS_GOLDEN_DIR:-/tmp/args-golden}"
FAILURES=0

fail() { echo "FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "ok: $*"; }

# Every pre-existing target must produce byte-identical args to what
# build-target.sh produced before target-args.sh existed.
for t in wasm32 darwin-arm64 darwin-x64 linux-x64 linux-arm64 \
         linuxmusl-x64 linuxmusl-arm64 win32-x64 win32-arm64; do
  if [[ ! -f "$GOLDEN/$t.gn" ]]; then
    fail "$t: no golden file at $GOLDEN/$t.gn; re-run Task 2 Step 1"
    continue
  fi
  if diff -u "$GOLDEN/$t.gn" <(bash "$SCRIPT" "$t") >/dev/null; then
    pass "$t matches golden"
  else
    fail "$t differs from golden"
    diff -u "$GOLDEN/$t.gn" <(bash "$SCRIPT" "$t") >&2
  fi
done

# An unknown target must be rejected, not silently defaulted.
if bash "$SCRIPT" no-such-target >/dev/null 2>&1; then
  fail "unknown target exited 0"
else
  pass "unknown target rejected"
fi

# Thread-local globals: off for every wasm target, on for everything else.
# wasm32-eh is added in Task 4 and is skipped until it exists.
for t in wasm32 wasm32-eh; do
  out="$(bash "$SCRIPT" "$t" 2>/dev/null)" || continue
  if grep -qx 'embedpdf_thread_local_globals=false' <<<"$out"; then
    pass "$t has thread-local globals off"
  else
    fail "$t must set embedpdf_thread_local_globals=false"
  fi
done
for t in darwin-arm64 linux-x64 win32-x64; do
  if bash "$SCRIPT" "$t" | grep -qx 'embedpdf_thread_local_globals=true'; then
    pass "$t has thread-local globals on"
  else
    fail "$t must set embedpdf_thread_local_globals=true"
  fi
done

# build-target.sh no longer computes GN_TARGET_* itself, it derives each one
# from target-args.sh output. Any GN_TARGET_* it USES must therefore also be
# DERIVED, or the script dies under `set -u` for exactly the targets that
# reach that line, which may be targets this machine cannot build.
BUILD_TARGET_SH="$HERE/../build-target.sh"
for v in $(grep -oE 'GN_TARGET_[A-Z]+' "$BUILD_TARGET_SH" | sort -u); do
  if grep -qE "^${v}=" "$BUILD_TARGET_SH"; then
    pass "build-target.sh derives $v"
  else
    fail "build-target.sh uses \$$v but never assigns it"
  fi
done

# wasm32-eh is wasm32 plus nothing in gn: the exception flags live in the
# emscripten toolchain config, not in args.gn. The two targets must therefore
# produce identical arguments, which also proves wasm32 was not disturbed.
if diff -u <(bash "$SCRIPT" wasm32) <(bash "$SCRIPT" wasm32-eh) >/dev/null; then
  pass "wasm32-eh args match wasm32"
else
  fail "wasm32-eh args differ from wasm32"
  diff -u <(bash "$SCRIPT" wasm32) <(bash "$SCRIPT" wasm32-eh) >&2
fi

# Android is static, like iOS, wasm and linuxmusl, so pdf_is_complete_lib must
# be true. Chromium's Android config exports nothing from a shared library, so
# a shared build's --gc-sections strips all of PDFium as unreferenced and the
# .so links empty.
for t in android-arm64 android-x64; do
  out="$(bash "$SCRIPT" "$t" 2>/dev/null)" || { fail "$t: target-args rejected it"; continue; }
  grep -qx 'target_os="android"' <<<"$out" \
    && pass "$t targets android" || fail "$t must set target_os=\"android\""
  grep -qx 'pdf_is_complete_lib=true' <<<"$out" \
    && pass "$t is a static library" || fail "$t must set pdf_is_complete_lib=true"
  grep -qx 'embedpdf_thread_local_globals=true' <<<"$out" \
    && pass "$t has thread-local globals on" || fail "$t must set embedpdf_thread_local_globals=true"
  # Static, and it inherits Chromium's bundled libc++ under the std::__Cr
  # namespace, which complete_static_lib does not fully absorb into the
  # archive. Without this, anything linking the archive gets undefined
  # std::__Cr symbols; on Android that's deferred all the way to a device
  # trying to load the library. The NDK supplies libc++ instead.
  grep -qx 'use_custom_libcxx=false' <<<"$out" \
    && pass "$t disables the bundled libc++" || fail "$t must set use_custom_libcxx=false"
done
bash "$SCRIPT" android-arm64 | grep -qx 'target_cpu="arm64"' \
  && pass "android-arm64 is arm64" || fail "android-arm64 must set target_cpu=\"arm64\""
bash "$SCRIPT" android-x64 | grep -qx 'target_cpu="x64"' \
  && pass "android-x64 is x64" || fail "android-x64 must set target_cpu=\"x64\""

# iOS is static, unlike darwin. The device and simulator slices share a cpu and
# are told apart only by target_environment, so asserting that pair matters more
# than it looks: swapping them produces two artifacts that link nowhere useful.
for t in ios-arm64 ios-sim-arm64; do
  out="$(bash "$SCRIPT" "$t" 2>/dev/null)" || { fail "$t: target-args rejected it"; continue; }
  grep -qx 'target_os="ios"' <<<"$out" \
    && pass "$t targets ios" || fail "$t must set target_os=\"ios\""
  grep -qx 'target_cpu="arm64"' <<<"$out" \
    && pass "$t is arm64" || fail "$t must set target_cpu=\"arm64\""
  grep -qx 'pdf_is_complete_lib=true' <<<"$out" \
    && pass "$t is a static library" || fail "$t must set pdf_is_complete_lib=true"
  grep -qx 'embedpdf_thread_local_globals=true' <<<"$out" \
    && pass "$t has thread-local globals on" || fail "$t must set embedpdf_thread_local_globals=true"
  # third_party/BUILD.gn depends on libjpeg_turbo unconditionally, and that
  # target asserts use_blink, which defaults to false only for iOS. Without
  # this, a later edit that doesn't know why it's there is likely to delete it
  # as unused, and gn gen breaks again.
  grep -qx 'use_blink=true' <<<"$out" \
    && pass "$t forces use_blink on for libjpeg_turbo" || fail "$t must set use_blink=true"
  # Without this it inherits Chromium's default, which tracks Apple's newest
  # release, producing an archive that refuses to load below that iOS
  # version. 17.0 is the floor EpdfOps/Package.swift declares.
  grep -qx 'ios_deployment_target="17.0"' <<<"$out" \
    && pass "$t sets ios_deployment_target=17.0" || fail "$t must set ios_deployment_target=\"17.0\""
  # Static, and it inherits Chromium's bundled libc++ under the std::__Cr
  # namespace, which complete_static_lib does not fully absorb into the
  # archive. Without this, a Rust build linking the archive gets undefined
  # std::__Cr symbols. The iOS SDK supplies libc++ instead.
  grep -qx 'use_custom_libcxx=false' <<<"$out" \
    && pass "$t disables the bundled libc++" || fail "$t must set use_custom_libcxx=false"
  # use_custom_libcxx=false alone does not build: Chromium's explicit libc++
  # header modules (std_core et al.) are always built from its own vendored
  # libc++, and once the SDK's libc++ is what's actually linked, the two
  # copies disagree on macros (_LIBCPP_ALIGNOF) and redeclare types
  # (integral_constant), failing module compilation outright. Confirmed by
  # building obj/buildtools/third_party/libc++/std_core/module.pcm with and
  # without this flag.
  grep -qx 'use_clang_modules=false' <<<"$out" \
    && pass "$t disables clang header modules" || fail "$t must set use_clang_modules=false"
done
bash "$SCRIPT" ios-arm64 | grep -qx 'target_environment="device"' \
  && pass "ios-arm64 is a device slice" || fail "ios-arm64 must set target_environment=\"device\""
bash "$SCRIPT" ios-sim-arm64 | grep -qx 'target_environment="simulator"' \
  && pass "ios-sim-arm64 is a simulator slice" || fail "ios-sim-arm64 must set target_environment=\"simulator\""

# darwin-arm64 is shared (pdf_is_complete_lib=false), so it resolves libc++
# into itself at link time and never references std::__Cr. It must NOT set
# use_custom_libcxx=false, or a later "make it consistent" edit would change
# the shared build's own libc++ instead of just the static targets that need
# the flag.
if bash "$SCRIPT" darwin-arm64 | grep -qx 'use_custom_libcxx=false'; then
  fail "darwin-arm64 must not set use_custom_libcxx=false (it's shared, not static)"
else
  pass "darwin-arm64 leaves use_custom_libcxx untouched"
fi

# Chromium builds explicit libc++ header modules from its own vendored copy
# regardless of use_custom_libcxx, so every target that switches to the
# platform libc++ must also turn those modules off or the std_core module
# fails to build. Verified on both iOS and Android.
for t in android-arm64 android-x64; do
  if bash "$SCRIPT" "$t" | grep -qx 'use_clang_modules=false'; then
    pass "$t disables clang modules"
  else
    fail "$t must set use_clang_modules=false"
  fi
done

if (( FAILURES > 0 )); then
  echo "$FAILURES failure(s)" >&2
  exit 1
fi
echo "all target-args assertions passed"
