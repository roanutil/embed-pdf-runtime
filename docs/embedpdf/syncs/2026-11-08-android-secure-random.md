# 2026-11-08: secure randomness on Android

Fork-only change on top of `786765b80` (upstream runtime `4346c5131`).

`core/fxcrt/epdf_secure_random.cpp` (upstream `547ea3376`, "Use secure randomness for encrypted
saves") chooses a random source for Windows, Apple, asm.js and Linux and stops the build with
`#error` on every other platform. Chromium's `build_config.h` sets `IS_ANDROID`, not `IS_LINUX`,
for Android, so `android-arm64` and `android-x64` no longer compile:

```
core/fxcrt/epdf_secure_random.cpp:24:2: error: "EPDF_FillSecureRandom has no secure random source for this platform."
```

Android now takes the Apple branch, `arc4random_buf`. Bionic declares it at every API level and
backs it with the kernel's random source. The Linux branch's `getrandom()` is not an option: bionic
has it only from API 28, and the Android AAR declares `minSdk 24`.

Upstream has the same gap. This note goes when upstream gives Android a source of its own; on that
sync, take upstream's branch.
