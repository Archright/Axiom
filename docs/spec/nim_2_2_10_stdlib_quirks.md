# Nim 2.2.10 Stdlib Quirk Registry

**Discovered**: 2026-06-02 (BATCH 4 + BATCH 5 verification)
**Source**: https://nim-lang.org/install.html (latest stable 2.2.10, 2026-04-24)
**Verified by**: BATCH 4 nim check re-run with `nim 2.2.10` after DEBT#130 closure

This document is the SSOT for Nim 2.2.10-specific behavioral differences that affect AXIOM. It MUST be consulted before any proc→func conversion, stdlib import, or test code touching the affected APIs.

## Quirk Catalog

### Q-001: `checksums/md5`, `checksums/sha2` removed from stdlib (DEBT#135)

**Symptom**:
```
src/core/file_utils.nim(3, 17) Error: cannot open file: checksums/md5
src/core/verified_axioms_core.nim(20, 17) Error: cannot open file: checksums/sha2
```

**Root cause**: Nim 2.2.10 stdlib no longer ships the `checksums/` subdirectory. The `md5` and `sha2` modules were extracted to a standalone Nimble package `nimlang/checksums`.

**Resolution options** (priority order):
1. **Install Nimble package**: `nimble install checksums` — adds to `~/.nimble/pkgs/checksums/`
2. **Use new stdlib path**: `import std/checksums/md5` (preferred over `checksums/md5`)
3. **Inline replacement**: implement getMD5 with `std/sha1` + custom encoding (not recommended for security)

**Affected files**:
- `src/core/io/file_utils.nim:3` (was `src/core/file_utils.nim`) — `import checksums/md5`
- `src/core/verified_axioms/verified_axioms_core.nim:20` (was `src/core/verified_axioms_core.nim`) — `import checksums/sha2`

**Workaround in effect**: DEBT#135 Closed (resolved 2026-06-02). `nimble install checksums` completed; `nim check` passes.

---

### Q-002: `times.getTime` reclassified as `.sideEffect` (DEBT#136)

**Symptom**:
```
src/core/scheduler.nim(30, 6) Error: 'recordDuration' can have side effects
>> Hint: 'recordDuration' calls `.sideEffect` 'getTime' (times.nim:982)
```

**Root cause**: Nim 2.2.10 effect system strictness — `getTime` (wall-clock system call) is now explicitly tagged `.sideEffect`, propagating to all callers. Previously tolerated in `func` context; now rejected.

**Resolution**: convert `func` → `proc` for any function that calls `getTime`, `getMonoTime`, `getLocalTime`, `getGMTime`, or any `std/times` API reading system state.

**Justification per AGENTS.md §0.6 + GUARDIAN §17**:
- `func` is permitted ONLY for provably side-effect-free functions
- Time measurement is a side effect on the real-world clock
- `proc` is the correct choice; `{.raises: [].}` pragma must be retained

**Affected files** (resolved):
- `src/core/gate/scheduler.nim:30` (was `src/core/scheduler.nim`) — `func recordDuration` → `proc recordDuration` ✅ DEBT#136 Closed

---

### Q-003: `TableRef.isInitialized` field removed (DEBT#138, closed)

**Symptom**:
```
lib/pure/unittest.nim(759, 14) Error: undeclared field: 'isInitialized' for type tables.TableRef
  [type declared in lib/pure/collections/tables.nim(215, 3)]
```

**Root cause**: Nim 2.2.10 `std/tables` redesigned `TableRef` internal fields; `isInitialized` is no longer publicly accessible (moved to private state).

**Downstream impact**: Any code that compiles `unittest` (i.e., every `tests/**/*_test.nim`) cascades this error. This is an **internal stdlib bug** — `unittest.nim(759)` itself depends on the removed field.

**Workarounds** (any one is acceptable):
1. Patch `unittest.nim(759)` to use `s.durations.len > 0` instead of `s.durations.isInitialized`
2. Replace `TableRef` with explicit `seq` to avoid stdlib bug
3. Apply a local Nim stdlib override via `nim.cfg` + `--lib:path/to/patched`

**Affected files** (resolved):
- `tests/gateway/scheduler_priority_test.nim:10` — patched ✅ DEBT#138 Closed (resolved 2026-06-02)
- `lib/pure/unittest.nim:759` — internal stdlib (downstream cascade, mitigated via workaround 3)

---

### Q-004: `Table[].[]` requires `std/tables` import (DEBT#132, closed)

**Symptom**:
```
Error: type mismatch Expression: moduleAliasTable["cli_utils.nim"]
Expected: proc `[]`(s: string; i: BackwardsIndex): char
```

**Root cause**: `Table[T, U]` indexing is a free proc in `std/tables`. Without `import std/tables` (or `import tables`), Nim falls back to `string[]` overload and fails.

**Resolution**: add `tables` to the import list.

**Affected files** (resolved):
- `tests/gateway/axir_constraint_test.nim:2` — added `tables` to `import std/[unittest, options, strutils, tables]` ✅ DEBT#132 Closed

---

### Q-005: `JsonNode`/`JObject` require `std/json` import (DEBT#131, closed)

**Symptom**:
```
Error: undeclared identifier: 'JsonNode'
```

**Root cause**: `JsonNode`, `JObject`, `hasKey` are exported from `std/json`. Auto-split modules may inherit parent imports but lose direct `import` statements.

**Resolution**: add `import std/json` at the top of the file.

**Affected files** (resolved):
- `src/verification/lean_lsp_protocol.nim:3` — added `import std/json` ✅ DEBT#131 Closed

---

### Q-006: `LeanLspClient` requires `import ./lean_lsp` (DEBT#137, closed)

**Symptom**:
```
Error: undeclared identifier: 'LeanLspClient'
```

**Root cause**: `lean_lsp_protocol.nim` is auto-split from `lean_lsp.nim`. The split module loses the parent's `type LeanLspClient*` declaration context.

**Resolution**: add `import ./lean_lsp` to the auto-split module.

**Affected files** (resolved):
- `src/verification/lean_lsp_protocol.nim:4` — added `import ./lean_lsp` ✅ DEBT#137 Closed

---

### Q-007: Closure Capture gcsafe Enforcement (DEBT#139)

**Symptom**:
```
Error: 'makeMockOracle' is not GC-safe as it accesses 'reply' which is a global using GC'ed memory
```

**Root cause**: `gcsafe` proc type fundamentally rejects closure capture of any GC-managed value (Nim 2.2.10 strict effect system). Test mocks like `makeMockOracle` that capture function parameters (`reply: string`) or outer-scope locals (`var captured: string`) cannot satisfy `proc(...): Result[...] {.gcsafe, raises: [].}`.

**Resolution**: keep `{.raises: [].}` (the essential no-throw contract for the consumer), remove `{.gcsafe.}` from both the type and the closure literals. Trade-off: caller cannot use the oracle from a gcsafe context — but in this codebase, the consumer `isTrivialViaZ3` is itself not gcsafe, so the capability loss is theoretical, not practical.

---

### Q-008: Const-Context `currentSourcePath()` / `LogicalPath` Wrapping Deferral (DEBT#453)

**Registered claim** (`src/core/trusted/layer_enforcement.nim:28-32` marker, `:39` site; `docs/DEBT_REGISTRY.md` DEBT#453, Low/Open): const-context `currentSourcePath()` returns `string`; wrapping it in `LogicalPath` is recorded as breaking const evaluation / macro expansion, with cascade into widely-imported public APIs (`enforceLayerImports`, `enforceLayer`).

**Measured evidence** (2026-10-07, Nim 2.2.10 pinned `[Linux: amd64]`, compiled 2026-04-24; minimal repros `nim c -p:src` in worktree `tmp/quirk453/` — not committed):

| Case | Shape | Result |
|---|---|---|
| t1 | `const src = currentSourcePath()` | compiles (SuccessX) |
| t2 | `const lp = LogicalPath(currentSourcePath())` — direct distinct wrap in const | compiles |
| t3 | `const lp = toLogical(PhysicalPath(src), root)` — real conversion boundary (plain runtime `func`) in const | compiles |
| t4 | `toLogical(PhysicalPath(instantiationInfo(-1, true).filename), root)` inside a macro body | compiles |
| t5 | exact `resolveProjectRoot` shape: `{.compileTime.}` proc + `const srcLogical: LogicalPath = toLogical(PhysicalPath(currentSourcePath()), root)` | compiles |
| t6 | `staticRead(LogicalPath(currentSourcePath()))` | **Error: type mismatch** — got `LogicalPath`, expected `proc staticRead(filename: string)` |
| t7 | macro emits `const emitted*: LogicalPath = …`; consumer module does not import `path_identity`, reads `emitted` | compiles |
| t7b | same consumer adds `var x: LogicalPath = emitted` | **Error: undeclared identifier: 'LogicalPath'** |

**Root cause / verdict on the registered claim**: the strict form — "wrapping breaks const evaluation / macro expansion" — does **not** reproduce on Nim 2.2.10: the compiler VM evaluates distinct-wrapped const bindings fine (t2/t3/t5). In the 2.2.10 toolchain, `currentSourcePath` is a template expanding to `instantiationInfo(-1, true).filename` (`lib/system/compilation.nim:143`) and yields a plain `string`; wrapping that value in a distinct type is a legal compile-time conversion. What actually rejects a wrapped value are two documented semantics, not a VM limitation:

1. **Distinct types have no implicit conversion to their base type.** Compile-time stdlib APIs typed `string` (e.g. `staticRead`, and likewise `os.parentDir` applied to a `LogicalPath` value) reject the distinct argument unless it is explicitly unwrapped: `staticRead(string(lp))` (t6).
2. **Type-symbol leakage into instantiation sites.** Code emitted by a macro that references `LogicalPath` resolves the symbol at the consumer scope when the consumer writes its own type annotations — modules that use the macro API but never import `core/utils/path_identity` fail with `undeclared identifier` (t7b). This is the concrete mechanism of `docs/spec/artifact_determinism.md` §2.4's "cascading into widely-imported public APIs" clause.

**Official documentation basis** (Context7 → `nim-lang.github.io/Nim`, official docs mirror):

- `system.html`: "Returns the full file-system path of the current source at compile time. `template currentSourcePath(): string`" — documents the `string` return and compile-time availability; no prohibition on distinct wrapping.
- `manual.html` (Distinct type): "A distinct type is a new type derived from a base type that is **incompatible** with its base type… Explicit type conversions between a distinct type and its base type are permitted"; the "Convertible relation" section lists implicit conversions — distinct is **not** among them.
- `manual.html` (SQL example): the rejection of a plain `string` where a distinct is expected is presented as intended behavior ("Static error: `query` expects an SQL string!").
- `system.html`: `proc staticRead(filename: string): string {.magic: "Slurp".}` — parameter is typed `string`.
- `manual.html`/`tut1.html` (Constants): "The compiler must be able to evaluate the expression in a constant declaration at compile time" — no distinct-type restriction stated.

Net: official docs neither mandate nor prohibit the wrap; the observed rejections (t6/t7b) are documented, intended distinct-type semantics, and the strict "const evaluation breaks" phrasing is unsupported by both the official docs and measurement. No observation contradicts official documentation.

**Resolution**: the deferral stands (docs-only entry; the QUIRK marker and `data/debt_registry.json` are untouched per AGENTS.md §0.5c). Const-context sites remain `string`-typed (PhysicalPath-leak per `docs/spec/artifact_determinism.md` §2.4-2.5) until a runtime refactor converts them. When a wrapped value must feed a compile-time `string` API, unwrap explicitly at the call site (`staticRead(string(lp))`) or keep the wrap internal to the module so the `LogicalPath` symbol never reaches consumer scopes.

**Upstream issue status**: none warranted — the behavior follows documented distinct-type conversion rules and the `staticRead` string contract, so it is not a compiler defect; no upstream Nim issue was filed or located for const-context distinct wrapping of `currentSourcePath`.

**Affected files** (registered sites): `src/core/trusted/layer_enforcement.nim:28-32` (marker), `:39` (`const srcPath = currentSourcePath()`); registry row `docs/DEBT_REGISTRY.md` DEBT#453 (Open); deferral ledger `docs/spec/artifact_determinism.md` §2.4-2.5.

---

### Q-009: `staticRead`/`slurp` Two-Stage Path Resolution — Module-Dir-Relative First, Import-Path Search Second, CWD Never Consulted (no DEBT row; **RESOLVED 2026-10-08, PR #590** — see "Resolution applied"; quirk record below kept as history)

**Registered claim**: `nim c --skipParentCfg --skipProjCfg` builds (checker.mk `NIM_TOOL_FLAGS` — `ci/checker.mk:21`; hermetic gate/tool self-builds) fail at `src/core/contracts/spec_binding_macro.nim:36` (`staticRead("../../docs/spec/three_tier_contract_architecture.md")`) while the same source builds succeed on machines carrying a local, git-ignored `src/docs → ../docs` symlink. First recorded 2026-10-07 in `docs/evidence/ratchet_authority_closure_2026-10-07.md` §"Build-environment observation" (root cause probe-verified there as module-relative resolution); the earlier session-level suspicion that the config flags themselves cause the failure is disproven below.

**Measured evidence** (2026-10-08, Nim 2.2.10 pinned `[Linux: amd64]`, worktree `quirk-docs-2`; fixtures under git-ignored `tmp/` — not committed):

| Probe | Shape | Result |
|---|---|---|
| real-gate A | `nim c --skipParentCfg --skipProjCfg --path:. --path:src --path:tools --path:<checksums> --path:<fusion> src/gate/runners/nim_check_gate.nim`, no `src/docs` symlink | **`src/core/contracts/spec_binding_macro.nim(36, 30) Error: cannot open file: ../../docs/spec/three_tier_contract_architecture.md`** (exit 1) |
| real-gate B | same + `ln -s ../docs src/docs` | compiles, exit 0 (symlink removed afterwards; tree left clean) |
| flag matrix | repo-shape fixture × {`--skipParentCfg --skipProjCfg` on/off} × {parent `config.nims` loaded/not} × {symlink present/absent} | outcome tracks **only the symlink**; flags and config loading are **not causal** (4/4 cells agree) |
| C1 | module `a/b/srmod.nim`: `staticRead` of a fixture doc via `../../docs/spec/…` (fixture file exists only in the fixture tree), CWD=`/` | compiles — hit resolved under the module's directory; `/docs/…` (CWD-relative) does not exist |
| C2 | `staticRead("data/registry.json")` with CWD = the directory that HAS `data/registry.json` | **fails** — CWD is never consulted by `staticRead` |
| C3 | same miss + `--path:<dir holding the file>` | compiles — on total stage-1 miss the import/search paths are searched |
| R2 | project file 2 levels under repo root; a marker file exists only at the repo-root escape target | hit — a search-path (project dir) join with a `../..`-bearing relative **escapes the search path upward** |
| R3 | nothing reachable anywhere | non-fatal `Error: cannot open file: …`; `staticRead` yields `""` and compilation continues (a downstream `static:` assert then failed on the empty string) |

**Root cause** (compiler source, Nim 2.2.10 `compiler/vmdeps.nim:18-23`): `opSlurp` — the magic behind `staticRead`/`slurp` — resolves in two stages: (1) `parentDir(toFullPath(conf, info)) / file`, i.e. relative to the directory of the file CONTAINING the call; (2) if absent, `findFile(conf, file)` — the module/search-path machinery (`compiler/options.nim:872-890`), whose raw path joins do not normalize `..`, so a `../`-bearing relative can escape the search path entirely (for gate/tool builds the project file lives in `src/gate/runners/`, so the project-dir join lands on `src/docs/…` — the same target as stage 1; `--path:.`/`--path:src` joins land above the repo root). A total miss is NON-FATAL: `localError("cannot open file: …")` + empty-string result. For `spec_binding_macro.nim` specifically: the `static:` guard at `:22-24` uses VM `fileExists(RegistryPath)` (CWD-relative — passes when CWD = repo root) while `staticRead` at `:36` is module-dir-relative-first — the guard and the reader resolve on different bases; and `SpecDocContent` is forced by every `{.spec("…")}` expansion (`src/core/types/vkd_types.nim`, `src/core/types/certificate_types.nim`, `src/core/types/asi_types.nim`), which is why real gate builds — whose import graphs pull those modules — evaluate the read, while a bare `import core/contracts/spec_binding_macro` with no `{.spec}` use may not.

**Verdict on the registered claim**: the observed flag correlation ("skip flags → fail / default config.nims → succeed") is **not causal** — the measured matrix flips only on the `src/docs` symlink. The causal variable is the machine-local symlink (present on some machines, never in CI runners — 2026-10-07 evidence doc). The evidence document's root-cause claim (module-dir-relative resolution; CWD and project-path have no effect) is **confirmed and extended**: stage 2 exists (import-path fallback, with `../` escape), and CWD is consulted never (C2).

**Official documentation basis** (Context7 → `nim-lang.github.io/Nim`, official docs mirror):

- `system.html`: `proc staticRead(filename: string): string {.magic: "Slurp".}` — "Reads a file at compile-time for resource embedding" / "Compile-time readFile proc for easy resource embedding"; `slurp` = alias. **No path-resolution base is documented at all** — neither CWD nor source-file-relative is stated. The observed two-stage semantics are therefore UNdocumented behavior, not a contradiction of documented behavior; nothing in the reference would let a reader predict them or avoid the trap. Documentation gap, recorded as-is.
- `nimc.html` (Configuration files): `--skipCfg` / `--skipUserCfg` / `--skipParentCfg` / `--skipProjCfg` are documented exclusively as config-file-selection switches ("Users can selectively skip these configuration files using specific command-line options") — no documented effect on CWD or compile-time file-path resolution. Consistent with the measurement: the flags are not causal.
- `nimc.html` (Search path handling): a global search path locates imported modules and include files — the machinery `staticRead`'s stage 2 reuses.
- `system.html` / `macros.html`: `currentSourcePath()` returns "the path of the specific source file containing the … call"; `macros.getProjectPath()` returns the project path — the documented anchoring primitives for compile-time reads.

**Resolution applied (2026-10-08, PR #590 — code change, the fix this entry registered the need for)**: `src/core/contracts/spec_binding_macro.nim` anchors BOTH compile-time reads on a module-private `RepoRootAnchor = currentSourcePath().parentDir().parentDir().parentDir().parentDir()` (4×parentDir = repo root): `RegistryPath` (the `static:` guard's VM `fileExists` and the registry `staticRead` now resolve on the same absolute base — the CWD-relative-guard vs module-relative-reader split registered above is closed) and `SpecDocPath` (renamed from `SpecDocRelPath`; the `../../docs/spec/three_tier_contract_architecture.md` literal — whose wrong depth was the entire symlink dependency — is gone). The inverted inline comment at `src/core/context/run_context.nim:105-109` (registered above) is corrected to the measured semantics. Measured evidence (Nim 2.2.10 pinned `[Linux: amd64]`, worktree `staticread-anchor`):

| Probe | Shape | Result |
|---|---|---|
| real-gate A, pre-fix | hermetic-flag `nim_check_gate` rebuild (`--skipParentCfg --skipProjCfg --path:.` `--path:src --path:tools` + nimble dep paths per `config/paths.nims` `injectAxiomDependencies`), no `src/docs` symlink | exit 1 — `spec_binding_macro.nim(36, 30) Error: cannot open file: ../../docs/spec/three_tier_contract_architecture.md` (Q-009 reproduced; registration probe had stopped at this line and never reached the `malebolgia` import further down the graph) |
| real-gate A, post-fix | same, no symlink | **exit 0**, binary produced |
| real-gate B, post-fix | same + `ln -s ../docs src/docs` | exit 0; symlink removed afterwards, tree clean — the outcome no longer tracks the symlink |
| CWD independence | post-fix compile from CWD=`/tmp` with absolute source path | exit 0 — the CWD-relative registry-guard dependence is closed |

The absolute anchor is sound by compiler source, not only by measurement: on total stage-1 miss (stage 1 joins the containing module's dir with the literal — normalizing join, so an absolute argument forms a non-existent `…/contracts/<abs>/…` path), `findFile` (`compiler/options.nim:928-932`, pinned toolchain) has an absolute fast path — `if f.isAbsolute: result = if f.fileExists: AbsoluteFile(f) else: AbsoluteFile""` — so an existing absolute path is returned as-is and read. Official documentation basis (Context7 → `nim-lang.github.io/Nim`): `system.currentSourcePath()` "Returns the full file-system path of the current source at compile time" (measured absolute in this build shape); `macros.getProjectPath()` "Returns the path of the project being compiled" — deliberately NOT used as the anchor: the project file for gate/tool self-builds lives in `src/gate/runners/`, so a project-path anchor would re-introduce a layout dependence. `staticRead`/`slurp` still document no resolution base (the documentation gap above stands, recorded as-is).

**Resolution (2026-10-08, docs-only registration slice — historical, superseded by "Resolution applied")** (docs-only slice — no code, marker, or registry change per that task's scope and AGENTS.md §0.5c): builds that must not depend on machine state anchor compile-time reads with `currentSourcePath()` — the pattern already used by `src/core/context/run_context.nim:105-109` (whose inline comment inverts the actual semantics — it claims "staticRead is CWD-relative otherwise"; measured: CWD is never consulted. Inverted-comment observation recorded here; correcting it is a code change, out of scope). Until `spec_binding_macro.nim:35-36` is so anchored, every clean worktree (no `src/docs` symlink) fails to build gate binaries whose graph reaches a `{.spec}` expansion; the interim workaround remains the machine-local symlink. **No "fix" is applied** — this entry records observed behavior and the documentation gap as-is.

**Upstream issue status**: none warranted — the behavior follows from the compiler source and violates no documented contract; the gap is documentation-side (no stated resolution base for `staticRead`/`slurp` in `system.html`).

**Affected files** (registered sites): `src/core/contracts/spec_binding_macro.nim:21-26` (CWD-relative guard vs module-relative reader), `:35-36` (the failing read); `{.spec}` consumers forcing evaluation: `src/core/types/vkd_types.nim`, `src/core/types/certificate_types.nim`, `src/core/types/asi_types.nim`; build recipes exposing it: `ci/checker.mk:21` (`NIM_TOOL_FLAGS`), hermetic gate/tool self-builds (`tools/axiom_cli.nim:40` isolation flags); anchoring precedent: `src/core/context/run_context.nim:105-109`; observation ledger: `docs/evidence/ratchet_authority_closure_2026-10-07.md` §"Build-environment observation".

---

### Q-010: `cast[int](someFloat)` reinterprets the IEEE-754 bit pattern — not a numeric conversion (docs-only entry; fix applied in the same slice, no DEBT row)

**Symptom** (2026-10-08, DEBT#471 closure follow-up): the ghost epoch directory
`epoch_4745300579805605544` appeared under `.axiom/cache/gate_memo/` — numeric,
but ~4.7e18, i.e. far above any legitimate monotonic epoch counter (observed
max ≈ 30). Not corruption: a valid CAS memo entry written by a unit test
(`gateId: "unit-test-depsdirs-…"`) at that garbage epoch.

**Root cause**: `tests/unit/gate_memo_depsdirs_test.nim` used
`let epoch = cast[int](epochTime()).int`. `cast` between float and int does NOT
convert the numeric value — it reinterprets the 64-bit IEEE-754 representation.
For `epochTime() ≈ 1.7914e9` the bit pattern is `0x41DB_…`, and read as an
int64 that is ≈ 4.745e18 — exactly the observed ghost directory name. The
test also targeted the cwd-relative real cache (`GateMemoBaseDir`), and its
cleanup removed a legacy flat path that `saveGateMemo` (CAS layout) never
writes, so the pollution survived every run.

**Resolution**: the test now runs sandboxed (temp cwd, matching the
`makeMemoTmpDir` convention of `gate_memo_test.nim`) at contract-valid epoch 0
with real cleanup; `garbageCollectOldEpochs` gained the foreign-directory guard
([cache_policy.md "Foreign directory guard"](cache_policy.md)) so the class is
reclaimed/detected going forward. Both landed in the same change that
documents this quirk — no separate DEBT row.

**Rule**: `cast` between float and int types is a bit-pattern
reinterpretation, not a conversion; in AXIOM sources it must not be used where
a numeric conversion is meant (use `.int64` / `int()` conversion syntax).

---

### Q-011: `for k, v in jsonNode` on a `JArray` binds `pairs()` and asserts `JObject` (DEBT#497 follow-up, 2026-10-08)

- **Symptom**: a two-variable `for i, item in node` loop over a `JsonNode` compiles clean but raises
  `json.nim(847, 3) pairs() can not iterate a JsonNode of kind JArray [AssertionDefect]` at runtime
  whenever the node is an array — the two-variable destructure selects json.nim's `pairs` iterator
  (object-only, `assert node.kind == JObject`) instead of an index/yield iterator.
- **Root cause**: iterator resolution by tuple arity; json.nim 2.2.10 `pairs` is object-only.
  Single-variable `for item in node` (items) is safe for arrays.
- **Resolution**: iterate arrays by index (`for i in 0 ..< node.len: node[i]`).
- **Affected files**: `src/gate/runners/architecture_config_gate.nim` (`scanJsonForTimestamps`
  JArray branch — latent since the gate could only run via the DEBT#497 hollow-CAS shell; surfaced
  by the real-main wiring of the DEBT#497 follow-up).

### Q-012: `execCmdEx` is line-oriented — `readLine` + unconditional `"\n"` re-append mangles binary (`-z`) output (2026-10-10, VS-2 judgment-key v3 slice; no DEBT row — fix applied in the same slice)

- **Symptom**: `execCmdEx("git ls-tree -r -z <oid>")` returns the NUL-record stream with one
  extra trailing `0x0A` byte (`…\t<last-path>\0\n`). A fail-closed parser of the `-z` stream
  (`semantic_set_derivation.parseLsTreeZ`) then rejects the final empty/newline-only record
  (`ls-tree record has no meta/path tab: '\n'`).
- **Root cause** (stdlib, `lib/pure/osproc.nim` `execCmdEx`): output is captured through
  `outp.readLine(line)` and the captured line is followed by `result[0].add("\n")` on every
  read. The `-z` stream contains no `\n` at all, so the entire output is "one line" and the
  re-append fabricates a trailing newline that git never emitted. Measured (2026-10-10,
  git 2.43.0, file-vs-pipe both 428732 bytes ending `\0`; Nim capture 428733 bytes ending
  `00 0A`; `execCmdEx("printf 'abc'")` → `abc\n` — 4 bytes for a 3-byte output; `true` →
  empty, so the append happens only when output is non-empty).
- **Resolution**: any subprocess whose stdout is BINARY (git `-z`, `--porcelain=v2` NUL
  mode, tar, etc.) must be captured raw — `startProcess(prog, args = […], options =
  {poUsePath, poStdErrToStdOut})` + `outputStream.readAll()` + `waitForExit()` — never
  `execCmdEx`/`execCmd` line semantics. Text commands (`rev-parse`, `add`, `commit -q`)
  are unaffected (output ends with `\n` or is empty; the re-append is a no-op), but the
  raw-capture boundary is the rule for any future binary consumer.
- **Affected files**: `src/verification/semantic_set_derivation.nim` (`runGitOrErr` —
  rewritten to the raw `startProcess` capture, the single derivation authority for the
  judgment key component ⑤); tests seed/commit paths (`tests/unit/
  test_judgment_set_derivation.nim`) adjusted to argv-style tokens (no `quoteShell`, no
  spaces in commit messages) because the raw boundary spawns argv directly, not a shell.

---

### Q-013: `os.parentDir("/")` returns `""` — `findRepoRoot`'s filesystem-root guard never fires and the anchor walk escapes to a CWD-relative `""` root (2026-10-24, VS-2 lane-precondition slice; docs-only entry, no DEBT row)

- **Symptom**: a binary compiled OUTSIDE the repo tree (e.g. `nim c -o:/tmp/...`) returns
  `findRepoRoot() == ""` when run with CWD inside the repo. Downstream marker-anchored joins
  then become CWD-anchored relative paths — most notably the attest-chain ircheck lookup
  (`resolveRepoRoot() / "proofs" / ".lake" / "build" / "bin" / "ircheck"`:
  `src/verification/extraction_agreement.nim:165-173`,
  `src/verification/obligation/canonical_verification.nim:1043-1049`,
  `src/verification/kernel_reexecution.nim:521-522`), which silently resolves against the
  CWD instead of the repo. With CWD OUTSIDE the repo, the walk instead lands on the legacy
  fallback `parentDir(startDir)` — one level above the binary, also not the repo.
- **Root cause** (Nim 2.2.10 `[Linux: amd64]`, measured + stdlib source): `parentDir("/")`
  returns `""` (not `"/"`), and `parentDir("")` returns `""`. Stdlib mechanism
  (pinned toolchain `lib/std/private/ospaths2.nim`): `parentDirPos` (`:401-408`) adjusts
  for a trailing separator with `q = 2`, so for `"/"` the scan starts at `len-q == -1` and
  finds no separator → `-1`; `parentDir` (`:421-432`) then hits the
  `result[^1] in {DirSep, AltSep}` branch which returns `""` — the in-source comment
  concedes "`/` => `/` (as done with splitFile) would be a sensible alternative". AXIOM-side
  consequence: the walk-up loop in `findRepoRoot`
  (`src/core/utils/repo_root.nim:25-51`) detects the filesystem root with
  `let parent = parentDir(result); if parent == result: break` (`:46-48`) — at
  `result == "/"` the guard compares `"" == "/"` and does NOT break, so `result` drops to
  `""`; the next iteration's marker probe `fileExists(result / axiomRoot)` (`:40`) evaluates
  `fileExists("" / ".axiom_root")` == `fileExists(".axiom_root")` — a CWD-relative check
  (stdlib `/` keeps an empty head relative: `"" / ".axiom_root" == ".axiom_root"`).
  In-repo binaries never reach this state (the `.axiom_root` anchor is found first).
- **Measured evidence** (2026-10-24; probe compiled against the real module —
  `nim c --skipParentCfg --skipProjCfg --path:<repo>/src`, source and binary under
  `/tmp/laneprep_probe/`, so `getAppDir()` is outside the repo):

  | CWD | `parentDir("/")` | `findRepoRoot(getAppDir())` | mechanism |
  |---|---|---|---|
  | repo root | `""` | `""` | walk passes `/` (guard `"" == "/"` false), then the `"" / ".axiom_root"` probe hits the CWD-relative marker → returns `""` |
  | `/tmp` | `""` | `/tmp` | same escape; CWD-relative probe misses; `parentDir("") == "" == result` breaks the loop; legacy fallback `parentDir(startDir)` = `/tmp` |

- **Resolution**: binaries whose on-disk location is not repo-anchored must not rely on the
  marker walk: run them with the binary inside the repo tree (`nim r tests/unit/<suite>.nim`
  places the binary next to the source), set `AXIOM_ROOT` (honored first,
  `repo_root.nim:30-36`), or use the per-consumer override (e.g. `AXIOM_IRCHECK_CMD` for the
  attest chain — `docs/agents/operations.md` Trap 4). No code change in this slice; the
  `/` edge is stdlib-following, not a stdlib defect.
- **Official documentation basis** (Context7 → `nim-lang.github.io/Nim`, `ospaths2.html` /
  `paths.html`): `parentDir` "Returns the parent directory of the given path... handles
  edge cases like empty paths and trailing separators, preserving absolute/relative
  status"; the documented `runnableExamples` cover `parentDir("") == ""` and
  `parentDir("/./foo//./") == "/"` but no `parentDir("/")` case. The measured `""` for the
  absolute `"/"` sits in that documentation gap (and is at odds with the
  "preserving absolute/relative status" prose); the loop consequence above is
  undocumented-behavior interaction, not a documented-contract violation.
- **Affected files**: `src/core/utils/repo_root.nim:25-51` (walk-up + root guard + legacy
  fallback); attest-chain consumers of `resolveRepoRoot()`:
  `src/verification/extraction_agreement.nim:165-173`,
  `src/verification/obligation/canonical_verification.nim:1043-1049`,
  `src/verification/kernel_reexecution.nim:521-522`; precondition documentation:
  `docs/agents/operations.md` Trap 4.

## Cross-Reference to AGENTS.md

- §0.5b: Quirk Documentation Mandate — this file is the SSOT
- §0.5c: Tracked QUIRK markers — see Q-008 (DEBT#453); markers must stay in sync with `data/debt_registry.json`
- §0.6: Static First — see Q-002 (func→proc justification)
- §0.6a: Concurrent Code — `times.getMonoTime` is preferred over `getTime` for benchmarking
- §2.6: Incremental Principle — quirk discovered → register in DEBT_REGISTRY → document here

## Update Procedure

1. **Discovery**: nim check / compile produces unexpected error
2. **Quirk ID**: assign next available `Q-NNN` (see top of this file)
3. **Document**: add new section with Symptom / Root cause / Resolution / Affected files
4. **Register DEBT**: add row to `docs/DEBT_REGISTRY.md` (closed iff fix applied)
5. **Reference**: add entry to `AGENTS.md` §0.5b pointer (if SSOT-level)

## Verification Command

```bash
export 
export PATH="$HOME/.choosenim/toolchains/nim-2.2.10/bin:$HOME/.nimble/bin:$PATH"
nim --version | head -2  # Must report 2.2.10
```
