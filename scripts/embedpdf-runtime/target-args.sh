#!/usr/bin/env bash
# Copyright 2026 CloudPDF LTD
# SPDX-License-Identifier: Apache-2.0
#
# Prints the args.gn body for one target and exits. No side effects: this is
# the pure part of build-target.sh, split out so a target's gn arguments can
# be asserted without running gn or ninja.

set -euo pipefail

TARGET="${1:-}"
PDF_IS_COMPLETE_LIB=true
# EmbedPDF: thread-confined runtime. Off by default; enabled below for every
# non-wasm target. wasm isolates globals per-instance, so it stays off there.
EMBEDPDF_TLS_GLOBALS=false

if [[ -z "$TARGET" ]]; then
  echo "usage: $0 <target>" >&2
  exit 1
fi

case "$TARGET" in
  wasm32 | wasm32-eh)
    GN_TARGET_OS="emscripten"
    GN_TARGET_CPU="wasm"
    EXTRA_ARGS=$'\nis_clang=false\nuse_custom_libcxx=false'
    ;;
  darwin-arm64)
    GN_TARGET_OS="mac"
    GN_TARGET_CPU="arm64"
    PDF_IS_COMPLETE_LIB=false
    ;;
  darwin-x64)
    GN_TARGET_OS="mac"
    GN_TARGET_CPU="x64"
    PDF_IS_COMPLETE_LIB=false
    ;;
  linux-x64)
    GN_TARGET_OS="linux"
    GN_TARGET_CPU="x64"
    PDF_IS_COMPLETE_LIB=false
    ;;
  linux-arm64)
    GN_TARGET_OS="linux"
    GN_TARGET_CPU="arm64"
    PDF_IS_COMPLETE_LIB=false
    EXTRA_ARGS=$'\narm_control_flow_integrity="none"'
    ;;
  linuxmusl-x64)
    GN_TARGET_OS="linux"
    GN_TARGET_CPU="x64"
    EXTRA_ARGS=$'\nis_musl=true\nis_clang=false\nuse_sysroot=false\nuse_custom_libcxx=false\nuse_custom_libcxx_for_host=false\nuse_glib=false'
    ;;
  linuxmusl-arm64)
    GN_TARGET_OS="linux"
    GN_TARGET_CPU="arm64"
    EXTRA_ARGS=$'\nis_musl=true\nis_clang=false\nuse_sysroot=false\nuse_custom_libcxx=false\nuse_custom_libcxx_for_host=false\nuse_glib=false'
    ;;
  win32-x64)
    GN_TARGET_OS="win"
    GN_TARGET_CPU="x64"
    PDF_IS_COMPLETE_LIB=false
    ;;
  win32-arm64)
    GN_TARGET_OS="win"
    GN_TARGET_CPU="arm64"
    PDF_IS_COMPLETE_LIB=false
    ;;
  android-arm64)
    GN_TARGET_OS="android"
    GN_TARGET_CPU="arm64"
    # Static, unlike the other shared platforms: Chromium's Android config
    # exports nothing from a shared library, so --gc-sections strips all of
    # PDFium as unreferenced and the .so links empty. Falls back to the
    # PDF_IS_COMPLETE_LIB=true default set above.
    # use_custom_libcxx=false: a static target that pulls in Chromium's
    # bundled libc++ ships an archive nobody can link, because that libc++ is
    # a separate target under the std::__Cr namespace that complete_static_lib
    # does not fully absorb. wasm32 and linuxmusl-x64 already set this for the
    # same reason; darwin doesn't need it only because it's a shared library
    # that resolves libc++ into itself at link time. The NDK supplies libc++
    # here instead.
    # use_clang_modules=false: needed here for the same reason as on iOS, and
    # CONFIRMED on Linux rather than assumed. Chromium builds explicit libc++
    # header modules from its own vendored copy regardless of
    # use_custom_libcxx, and with that copy no longer staged the generated
    # module map points at headers that are not there:
    #   FAILED: obj/build/modules/android-arm64/std_core/module.pcm
    #   While building module 'std_core':
    #   __cstddef/byte.h:13:10: fatal error: '__fwd/byte.h' file not found
    # The NDK's libc++ turned out to hit this too, so being closer to upstream
    # LLVM than Apple's fork does not help.
    EXTRA_ARGS=$'\nuse_custom_libcxx=false\nuse_clang_modules=false'
    ;;
  android-x64)
    GN_TARGET_OS="android"
    GN_TARGET_CPU="x64"
    # Static, unlike the other shared platforms: Chromium's Android config
    # exports nothing from a shared library, so --gc-sections strips all of
    # PDFium as unreferenced and the .so links empty. Falls back to the
    # PDF_IS_COMPLETE_LIB=true default set above.
    # use_custom_libcxx=false: a static target that pulls in Chromium's
    # bundled libc++ ships an archive nobody can link, because that libc++ is
    # a separate target under the std::__Cr namespace that complete_static_lib
    # does not fully absorb. wasm32 and linuxmusl-x64 already set this for the
    # same reason; darwin doesn't need it only because it's a shared library
    # that resolves libc++ into itself at link time. The NDK supplies libc++
    # here instead.
    # use_clang_modules=false: see the matching note on android-arm64 above.
    # Confirmed on Linux, not assumed: without it the std_core libc++ header
    # module fails to build with "'__fwd/byte.h' file not found".
    EXTRA_ARGS=$'\nuse_custom_libcxx=false\nuse_clang_modules=false'
    ;;
  ios-arm64)
    GN_TARGET_OS="ios"
    GN_TARGET_CPU="arm64"
    # third_party/BUILD.gn depends on libjpeg_turbo unconditionally, and that
    # target asserts use_blink, which build/config/features.gni:41 defaults to
    # false only for iOS.
    # ios_deployment_target: without this it inherits Chromium's default,
    # which tracks Apple's newest release. Pinned to 17.0 because that's the
    # floor rust-core-scaffold/packages/swift/EpdfOps/Package.swift declares
    # for its own iOS platform requirement.
    # use_custom_libcxx=false: a static target that pulls in Chromium's
    # bundled libc++ ships an archive nobody can link, because that libc++ is
    # a separate target under the std::__Cr namespace that complete_static_lib
    # does not fully absorb. wasm32 and linuxmusl-x64 already set this for the
    # same reason; darwin doesn't need it only because it's a shared library
    # that resolves libc++ into itself at link time. The iOS SDK supplies
    # libc++ here instead.
    # use_clang_modules=false: Chromium's explicit libc++ header modules
    # (std_core et al., build/config/c++/modules.gni) are always built from
    # Chromium's vendored libc++ headers regardless of use_custom_libcxx. With
    # the system libc++ selected above, that vendored copy and Apple's SDK
    # copy disagree on macro definitions (_LIBCPP_ALIGNOF) and redeclare the
    # same types (integral_constant), and module compilation fails outright.
    # Confirmed by building obj/buildtools/third_party/libc++/std_core/module.pcm
    # with and without this flag on 2026-09-04.
    EXTRA_ARGS=$'\ntarget_environment="device"\nios_enable_code_signing=false\nuse_blink=true\nios_deployment_target="17.0"\nuse_custom_libcxx=false\nuse_clang_modules=false'
    ;;
  ios-sim-arm64)
    GN_TARGET_OS="ios"
    GN_TARGET_CPU="arm64"
    # third_party/BUILD.gn depends on libjpeg_turbo unconditionally, and that
    # target asserts use_blink, which build/config/features.gni:41 defaults to
    # false only for iOS.
    # ios_deployment_target: without this it inherits Chromium's default,
    # which tracks Apple's newest release. Pinned to 17.0 because that's the
    # floor rust-core-scaffold/packages/swift/EpdfOps/Package.swift declares
    # for its own iOS platform requirement.
    # use_custom_libcxx=false: a static target that pulls in Chromium's
    # bundled libc++ ships an archive nobody can link, because that libc++ is
    # a separate target under the std::__Cr namespace that complete_static_lib
    # does not fully absorb. wasm32 and linuxmusl-x64 already set this for the
    # same reason; darwin doesn't need it only because it's a shared library
    # that resolves libc++ into itself at link time. The iOS SDK supplies
    # libc++ here instead.
    # use_clang_modules=false: Chromium's explicit libc++ header modules
    # (std_core et al., build/config/c++/modules.gni) are always built from
    # Chromium's vendored libc++ headers regardless of use_custom_libcxx. With
    # the system libc++ selected above, that vendored copy and Apple's SDK
    # copy disagree on macro definitions (_LIBCPP_ALIGNOF) and redeclare the
    # same types (integral_constant), and module compilation fails outright.
    # Confirmed by building obj/buildtools/third_party/libc++/std_core/module.pcm
    # with and without this flag on 2026-09-04.
    EXTRA_ARGS=$'\ntarget_environment="simulator"\nios_enable_code_signing=false\nuse_blink=true\nios_deployment_target="17.0"\nuse_custom_libcxx=false\nuse_clang_modules=false'
    ;;
  *)
    echo "unknown target: $TARGET" >&2
    exit 1
    ;;
esac

# EmbedPDF: enable per-thread PDFium globals everywhere except wasm, where each
# instance already isolates globals via its own linear memory. This is a prefix
# match, not an equality test, so that every wasm variant is covered.
if [[ "$TARGET" != wasm32* ]]; then
  EMBEDPDF_TLS_GLOBALS=true
fi

cat <<EOF
is_debug=false
treat_warnings_as_errors=false
pdf_use_skia=false
pdf_enable_xfa=false
pdf_enable_v8=false
is_component_build=false
clang_use_chrome_plugins=false
pdf_is_standalone=true
use_debug_fission=false
pdf_is_complete_lib=$PDF_IS_COMPLETE_LIB
pdf_use_partition_alloc=false
embedpdf_thread_local_globals=$EMBEDPDF_TLS_GLOBALS
symbol_level=0
target_os="$GN_TARGET_OS"
target_cpu="$GN_TARGET_CPU"${EXTRA_ARGS:-}
EOF
