# config/effects.nims — Compilation Flags, Warnings, Effects
# Extracted from config.nims lines 125-177
# Provides: SSL, threads, outdir, warnings, effects, strictEffects

# SSL support for HTTPS API calls (Mistral Leanstral)
switch("define", "ssl")

# AGENTS.md §0.6a: malebolgia threadpool requires threads
switch("threads")

# AGENTS.md §0.2: All compiled binaries go to bin/ (already in .gitignore)
# Prevents ELF artifacts from polluting src/ tree
switch("outdir", "bin")

# Phase 16: ARC memory model — safe after acyclic verification (acyclicViolations: 0)
switch("mm", "arc")

# AGENTS.md §0.6: Bare except = theater signature #2 (swallowed failure)
# NOTE: Unconditional `switch("warningAsError", "BareExcept")` removed — Nim stdlib
#   unittest.nim uses `except Exception:` which triggers Nim 2.x strict exception
#   checking. Because `.circleci/config.yml` (primary CI, immutable per AGENTS.md)
#   cannot be modified to pass `-d:testing`, there is no way to conditionally
#   suppress this warning for test builds via NimScript `when` directives.
#   Enforcement shifts to code review / static analysis. See GUARDIAN §-1.

# AGENTS.md §0.6: Strict compilation enforcement (Ψ3)
# All warnings are errors globally — CI catches policy violations at compile time.
# Break-glass: ALLOW_WARNINGS=true nim c ... → warnings remain warnings (not errors).
# This is an intentional risk signal, not a permanent bypass. Logged in CI output.
if getEnv("ALLOW_WARNINGS") != "true":
  switch("warningAsError", "on")
  # AGENTS.md §4 GUARDIAN: styleCheck MUST be hint-level, NEVER error.
  # styleCheck:hint surfaces naming issues as suggestions, never as build failures.
  # The axiom_gateway_build block in strict.nims can override to error for CI.
  switch("styleCheck", "hint")
  switch("hint", "XDeclaredButNotUsed:on")
else:
  # ── Break-glass monitoring ────────────────────────────────────────────────
  # Every ALLOW_WARNINGS usage is flagged immediately at compile time.
  # This ensures no silent accumulation of tech debt.
  echo "🚨 [break-glass] ALLOW_WARNINGS=true — warnings are NOT errors."
  echo "   This is an EMERGENCY escape mechanism. Review required."
  if getEnv("AXIOM_BYPASS_REASON").len > 0:
    echo "   Reason: " & getEnv("AXIOM_BYPASS_REASON")
  else:
    echo "   ⚠  No AXIOM_BYPASS_REASON provided — document your reason!"
  if getEnv("CI") == "true":
    echo "   ❌ CI environment detected — break-glass in CI requires post-merge audit."

# ── Visibility Matrix (Hint/Warning Control) ─────────────────────────────────
# AGENTS.md §0.6: Static First Enforcement
# Suppress noisy compiler hints that do not indicate real issues
switch("hint", "XCannotRaiseY:off")

# Strict warnings-as-error for test and gate builds
# Ensures test/gate compilations treat all warnings as errors
when defined(testing) or defined(gate):
  switch("warningAsError", "on")

# Compile-time effect tracking
switch("experimental", "strictEffects")
switch("experimental", "caseStmtMacros")  # fusion/matching 패턴 매칭 필수

# ── Term-Rewriting: Immutable File AST Interception ────────────────────────
# Phase 3.5: Ensures rewriteGateSeverity template in axiom_pragmas.nim is
# always active globally, including §-1 immutable files.
# NOTE: termRewriting is a standard language feature in Nim 2.2.10 — NO
#   experimental flag is needed. The template{pattern} syntax works natively.
# NOTE: `switch("import", "core/trusted/env_types")` REMOVED — it injected
# env_types into every compilation unit, causing UnusedImport warnings in
# modules that don't use any env_types symbols. The only consumer that
# needs it without an explicit import is the rewriteGateSeverity template
# in axiom_pragmas.nim, which now imports env_types directly.
# === HARD GATE: Effect system compliance ===
# AGENTS.md §0.6: Effect violations are ALWAYS errors — no break-glass escape.
# This is unconditional: even ALLOW_WARNINGS=true cannot suppress Effect errors.
switch("warningAsError", "Effect")        # Effect 위반 → 항상 컴파일 에러
if getEnv("ALLOW_WARNINGS") != "true":
  switch("warningAsError", "Effect")      # Defense-in-depth (redundant but harmless)

# ── Build Speed: deterministic incremental + parallel C compilation ──
# --usenimcache REMOVED (DEBT#457): the content-hash output suffix it adds to
# compiled tool names was the ETXTBSY parallel-race cause in bin/; the actual
# safeguards are stable --out: names plus fail-closed fan-out
# (build once → freeze → fan-out, PR #39). The unchanged-module incremental
# skip is the nimcache C incremental mechanism (config.nims NOTE at the
# hermetic block — Nim 2.2.10 byte-compares the generated .nim.c) and is
# independent of usenimcache. parallelBuild is computed dynamically in
# config.nims (getDeterministicParallelJobs — memory-aware, VM-safe).

# ── Discard Result Linter — Global Activation (Warning Mode) ──
# Phase 2c/3a: Anti-Theater by Construction. Wire discard_result_linter globally
# so every compiled module gets the check. The macro uses warning() (not error())
# to avoid breaking the build — the 97 existing best-effort I/O sites documented
# in data/discarded_result_sites.txt carry `# axiom:best-effort(...)` comments.
# Hard-fail can be enabled by changing warning()->error() in
# src/core/lint/discard_result_linter.nim after remediation.
#
# Coverage model: switch("import", ...) injects the import into every compilation
# unit, making the checkDiscardResult macro available everywhere. Modules that need
# the check wrap their procs with `checkDiscardResult:` (see io_executor.nim:79).
switch("import", "core/lint/discard_result_linter")
# The injected import triggers UnusedImport noise in units that don't reference
# the macro; discard_result_linter.nim carries a module-level {.used.} for the
# non-cyclic case, and this global suppression absorbs the remaining cyclic-import
# cases. Import topology is still enforced by the check-imports AST scanner, so
# no real unused-import detection is lost.
switch("warning", "[UnusedImport]:off")
