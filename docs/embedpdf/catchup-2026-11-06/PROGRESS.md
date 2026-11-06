# Runtime catch-up progress — 2026-11-06

Target: canonical runtime4346c5131cd009c4086fdce13bde7fd43fbd4ce0, fixed by viewer8297bad8d388eb9c70324c22cb001c59248f95f4.

1. Created owned runtime worktree from82f2dfabe2542208c783d49e210ed87f214ac0c3. Preserved the earlier3c55 layer fork and8b1e targetargs/emsdk history; original host checkout untouched.
2. Existing targetargs and emsdk-version regression scripts passed on baseline and merged source, including canonical macOS static/archive routing. Source mergea799941c245f44f524413165624e6a845749334d contains the exact upstream target and fork histories without conflicts.
3. Public C declarations1066→1068, exactly EPDFAnnot_SetNoColor and EPDFAnnot_SetSubtype; zero removed/changed signatures. C API listing checker passes590 EPDF functions in24 headers. This is source/header proof, not built-library symbol acceptance.
4. Build tools: newly provisioned depot_tools9fc44de94012dc6598ed1e84a9251759ed5ea7f8; fresh image has emsdk3.1.72 but no preexisting gclient/gn/native deps. Dependency sync and matching LinuxARM64/WASM/native embedder acceptance remain pending. Max2compiler jobs and one heavy build initially.
5. Resume: read source-verification.json; use this worktree and dedicated catchup/2026-11-06-runtime branch. Preserve released bytes, avoid all canonical upstream pushes, record subsequent build provenance in the viewer implementation ledger. Do not call Job1 complete before native tests/library and WASM identity are proved.

Ruling: use upstream's included semantic regression cases as inherited target tests and preserve fork targetargs regressions; add a new failure-first regression if integration exposes a missing fork case. No new semantic code has been invented in the clean merge.

Next action: sync DEPS at the committed source, then build and run relevant native embedder cases with matching libraries.
