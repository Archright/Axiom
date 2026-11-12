## tests/unit/test_hollow_cas_closure.nim
##
## DEBT#497 follow-up — hollow-CAS closure regression harness.
##
## Freezes the invariant that a hollow AOT binary (an empty, exit-0 shell
## produced by linking a runner module with no standalone main) can never
## produce a PASS verdict on any execution path:
##
##   I1 (manifest coverage)   — every manifest.d gate whose entry module has
##                              no standalone-main marker must be admitted to
##                              the in-process enforcement path
##                              (LightGateAllowlist). Measured 2026-10-08:
##                              registerGate-only runners AOT-link to hollow
##                              31,872–32,192-byte binaries that exit 0 —
##                              unconditional-PASS theater on the subprocess
##                              CAS path (runSingleGateImpl).
##   I2 (no stale allowlist)  — every LightGateAllowlist name must have a real
##                              runGateInProcess dispatch case; the "Gate not
##                              registered for in-process dispatch" sentinel
##                              verdict must be unreachable (the stale
##                              "debt-scan-gate" entry removed by this slice
##                              was exactly this shape).
##   I3 (module-level closure)— every registerGate-calling runner module under
##                              src/gate/runners must either carry a standalone
##                              main or be in-process enforceable. Wired gates
##                              close via the #587 pattern (allowlist + case +
##                              adapter); unwired orphans close via a real
##                              main (DEBT#270 manifest↔runner 1:1 makes
##                              in-process registration impossible for them).

import std/[unittest, os, strutils, json]
import gate/utils/gate_safety_macro
import gate/utils/inprocess_dispatch

proc manifestGates(): seq[tuple[id, entry: string]] =
  ## (gateId, entry) for every manifest.d gate — runtime read, tests run with
  ## CWD = repository root (make test contract).
  for kind, path in walkDir("src/gate/manifest.d"):
    if kind != pcFile or not path.endsWith(".json"):
      continue
    if path.endsWith("_index.json"):
      continue
    let j = parseJson(readFile(path))
    result.add((j["id"].getStr(), j["entry"].getStr()))

proc resolveEntrySrc(entry: string): string =
  ## Mirror runSingleGateImpl source resolution: entry (optionally .nim) under
  ## src/gate/runners, else the src/cli fallback (config.nims buildGates).
  let withExt = if entry.endsWith(".nim"): entry else: entry & ".nim"
  if fileExists(withExt):
    return withExt
  let cli = entry.replace("src/gate/runners/", "src/cli/") & ".nim"
  if fileExists(cli):
    return cli
  ""

func hasStandaloneMain(content: string): bool =
  hasStandaloneMainMarker(content)

func registeredGateId(content: string): string =
  ## Extract the literal id from a non-comment `registerGate("id", ...)` call.
  ## Comment/doc lines (`##`, `#`) are ignored — gate_concept.nim documents the
  ## call shape inside a doc comment and defines no runner.
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith("#"):
      continue
    let i = trimmed.find("registerGate(\"")
    if i >= 0:
      let rest = trimmed[i + "registerGate(\"".len .. ^1]
      let endQ = rest.find('"')
      if endQ > 0:
        return rest[0 ..< endQ]
  ""

# ═══════════════════════════════════════════════════════════════════════
# Test Suite
# ═══════════════════════════════════════════════════════════════════════

suite "DEBT#497 hollow-CAS closure":

  test "I1: every main-less manifest runner is in-process enforceable":
    var mainLess = 0
    for (id, entry) in manifestGates():
      # Prebuilt binary entries are executed directly (hasPrebuiltEntry) — no
      # CAS compilation, so no hollow-link exposure. A missing prebuilt fails
      # the gate (fail-closed), never hollow-PASSes it.
      if entry.startsWith("bin/"):
        continue
      let src = resolveEntrySrc(entry)
      check src.len > 0
      if src.len == 0:
        continue
      if not hasStandaloneMain(readFile(src)):
        inc mainLess
        check isLightGateAllowed(id)
    # Sanity: the sweep actually exercised the manifest (and still contains
    # the known main-less, in-process-enforced gate from the #587 closure).
    check mainLess >= 1
    check isLightGateAllowed("trust-commit-scope")

  test "I2: every allowlist name has a real runGateInProcess dispatch case":
    for allowed in LightGateAllowlist:
      let ctx = InProcessGateContext(
        repoRoot: getCurrentDir(),
        stagedFiles: @[],
        gateId: $allowed,
        epoch: 0,
        subtreeRoot: "",
        stage: 0,
        maxJobs: 1,
        passFilenames: false,
        effectiveTimeoutMs: 0)
      let res = runGateInProcess(ctx)
      # The sentinel is the "no case" fallback verdict — an allowlist name
      # that reaches it would FAIL every real run (stale-name shape).
      check "Gate not registered for in-process dispatch" notin res.stdout

  test "I2b: stale retired gate name is not in the allowlist":
    # debt-scan-gate was merged into debt-integrity-gate; its allowlist entry
    # was stale residue (no manifest gate, no dispatch case).
    check not isLightGateAllowed("debt-scan-gate")

  test "I3: every registerGate-only runner module is closed (main or allowlist)":
    for kind, path in walkDir("src/gate/runners"):
      if kind != pcFile or not path.endsWith(".nim"):
        continue
      let content = readFile(path)
      let id = registeredGateId(content)
      if id.len == 0:
        continue
      if hasStandaloneMain(content):
        continue
      check isLightGateAllowed(id)

  test "I4: closed wired gates produce real in-process verdicts":
    # decision-binding-gate and delegation-enforcer — measured hollow before
    # this slice; after closure the in-process path executes the real
    # judgment (never the sentinel). repoRoot = current repo, so the
    # judgments run for real; only dispatchability is asserted, not verdict.
    for gateId in ["decision-binding-gate", "delegation-enforcer"]:
      let ctx = InProcessGateContext(
        repoRoot: getCurrentDir(),
        stagedFiles: @[],
        gateId: gateId,
        epoch: 0,
        subtreeRoot: "",
        stage: 0,
        maxJobs: 1,
        passFilenames: false,
        effectiveTimeoutMs: 0)
      let res = runGateInProcess(ctx)
      check res.name == gateId
      check "Gate not registered for in-process dispatch" notin res.stdout
