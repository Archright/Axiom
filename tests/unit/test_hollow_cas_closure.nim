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

import std/[unittest, os, strutils, json, osproc]
import core/gate/gate_cas
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


# ---------------------------------------------------------------------------
# DEBT#524 — CAS reuse verdict integrity (digest sidecar)
# ---------------------------------------------------------------------------
# A cached gate binary is a REUSE HIT only when
#   <casDir>/binary.sha256 exists, is exactly 64 lowercase hex chars, and
#   equals the SHA-256 of <casDir>/binary.
# Existence alone is not a verdict: a post-store tamper, a crash between the
# binary and sidecar renames, or a malformed sidecar must all resolve as a
# MISS (recompile), never as a silent reuse.
#
# Expected digests come from external `sha256sum`, not from the production
# hash path, so a shared bug in hash_kernel cannot make these tests pass
# vacuously.

proc independentSha256(path: string): string =
  let (output, rc) = execCmdEx("sha256sum " & quoteShell(path))
  doAssert rc == 0, "sha256sum failed for " & path
  output.split(' ')[0].strip()

proc freshCasDir(): string =
  result = getTempDir() / "axiom_cas524_test"
  if dirExists(result):
    removeDir(result)
  createDir(result)

suite "DEBT#524 CAS digest sidecar (fail-closed reuse)":
  test "I5a: sidecar stores the binary's actual lowercase-hex SHA-256":
    let dir = freshCasDir()
    defer: removeDir(dir)
    let casBinary = dir / "binary"
    writeFile(casBinary, "gate binary v1")
    let digest = writeCasBinarySidecar(casBinary)
    check digest.len == 64
    check isLowercaseHex64(digest)
    check digest == independentSha256(casBinary)
    check readFile(casBinary & CasSidecarSuffix).strip() == digest

  test "I5b: a matching sidecar is a HIT":
    let dir = freshCasDir()
    defer: removeDir(dir)
    let casBinary = dir / "binary"
    writeFile(casBinary, "gate binary v1")
    check writeCasBinarySidecar(casBinary).len == 64
    check casBinarySidecarIntact(casBinary, "tamper-gate")

  test "I5c: post-store tamper is a MISS":
    let dir = freshCasDir()
    defer: removeDir(dir)
    let casBinary = dir / "binary"
    writeFile(casBinary, "gate binary v1")
    check writeCasBinarySidecar(casBinary).len == 64
    writeFile(casBinary, "gate binary v2 - tampered after store")
    check not casBinarySidecarIntact(casBinary, "tamper-gate")

  test "I5d: sidecar-less entry is a MISS":
    let dir = freshCasDir()
    defer: removeDir(dir)
    let casBinary = dir / "binary"
    writeFile(casBinary, "gate binary v1")
    check not casBinarySidecarIntact(casBinary, "tamper-gate")

  test "I5e: malformed sidecars are MISSes":
    let dir = freshCasDir()
    defer: removeDir(dir)
    let casBinary = dir / "binary"
    writeFile(casBinary, "gate binary v1")
    let sidecar = casBinary & CasSidecarSuffix
    let good = independentSha256(casBinary)
    writeFile(sidecar, good[0 ..< 63] & "\n")
    check not casBinarySidecarIntact(casBinary, "tamper-gate")
    writeFile(sidecar, good.toUpperAscii() & "\n")
    check not casBinarySidecarIntact(casBinary, "tamper-gate")
    writeFile(sidecar, 'z'.repeat(64) & "\n")
    check not casBinarySidecarIntact(casBinary, "tamper-gate")
    writeFile(sidecar, "")
    check not casBinarySidecarIntact(casBinary, "tamper-gate")

  test "I5f: an incomplete CAS entry is never resolved as a hit":
    let root = freshCasDir()
    defer: removeDir(root)
    let gateId = "tamper-gate"
    let sourceHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    let casKey = computeCasKey(gateId, sourceHash, root)
    check casKey.len > 0
    let casDir = root / ".axiom" / "cache" / CasDirName / casKey
    createDir(casDir)
    let casBinary = casDir / "binary"
    writeFile(casBinary, "cached gate binary")
    # sidecar-less: never a hit
    check resolveCasBinaryPathWithHash(gateId, "unused", root, sourceHash) == ""
    # stored + intact: a hit
    discard writeCasBinarySidecar(casBinary)
    check resolveCasBinaryPathWithHash(gateId, "unused", root, sourceHash) == casBinary
    # tampered afterwards: back to a MISS
    writeFile(casBinary, "cached gate binary - tampered")
    check resolveCasBinaryPathWithHash(gateId, "unused", root, sourceHash) == ""
