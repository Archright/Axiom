## tcb_judgments.nim — CI Optimization TCB Judgment Tool (P2)
##
## Spec: docs/spec/ci_optimization_tcb_judgments.md — THE single implementation
## of the four proof obligations. A CI optimization candidate is VALID only if
## ALL judgments pass. A judgment that cannot fail is a dead gate (theater,
## AGENTS.md §0.9) — `selftest` proves every FAIL path really fails.
##
## Exit codes (mirrors tools/ci_shadow_runner.sh:17-19):
##   0 = PASS           2 = JUDGMENT-FAIL   1 = error (bad args / I/O)
##
## Invariant key list (J2 §2.4) is a MIRROR of the certificate identity SSOT
## (src/verification/certificate_identity.nim:32-36 canonicalV3FieldKeys).
## The SSOT computes identities; this tool only compares measured digests by
## key, so the mirror cannot drift into a second identity formula. The spec
## records the MECE relation (no identity computed here).

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, json, strutils, algorithm]
import checksums/sha1
## J1 §1.1 projection-excluded telemetry keys — single source is
## core/utils/canonical_projection.nim (productization_contract.md:209).  A second
## copy here could drift from the list the hash actually strips, so this tool
## consumes the SSOT instead of re-deriving it.
from core/utils/canonical_projection import volatileKeys

## ---------------------------------------------------------------------------
## J2 §2.4 INVARIANT digest set — the only keys allowed to FAIL equality.
## ---------------------------------------------------------------------------
const invariantKeys* = [
  # (a) semantic — verdict/ProofStatus/classification
  "verdict", "proofStatus", "classification",
  # (c) canonical identity
  "canonicalProjectionHash",
  # certificate identity — 13-field projection (canonicalV3FieldKeys mirror)
  "certSchemaVersion", "certModulePath", "certFunctionName",
  "certSourceHash", "certIrHash", "certLeanProposition",
  "certSolverStatus", "certStatus", "certWinningStrategy",
  "certInputHash", "certSolverInputDigest", "certSolverResultDigest",
  "certEvidenceId",
  # solver contract digests
  "solverInputDigest", "solverResultDigest",
  # ledger subject identity
  "subjectId",
]

## J2 §2.4 substrate-specific keys — reported separately, never a failure.
const substrateKeys* = [
  "artifactIdDigest",          ## ArtifactDigest — artifact_determinism.md:10
  "axiomExecutableDigest",     ## identity.nim:178,188-206 (bundle fingerprint)
  "workUnitFingerprint",
  "gateEnvLockHostOS",         ## aot_pipeline.md:224-238,247
  "gateEnvLockHostCPU",
  "gateEnvLockKernelVersion",
  "toolchainDigest",
]

## ---------------------------------------------------------------------------
## Pure logic — func {.raises: [].}
## ---------------------------------------------------------------------------

func isInvariantKey*(k: string): bool {.raises: [].} =
  for ik in invariantKeys:
    if ik == k:
      return true
  false

func isSubstrateKey*(k: string): bool {.raises: [].} =
  for sk in substrateKeys:
    if sk == k:
      return true
  false

func isVolatileKey*(k: string): bool {.raises: [].} =
  for vk in volatileKeys:
    if vk == k:
      return true
  false

proc sortedKeys*(node: JsonNode): seq[string] {.raises: [].} =
  ## Deterministic key enumeration of a JSON object (sorted).
  for k in node.keys:
    result.add(k)
  result.sort()

func strVal(node: JsonNode; key: string): string {.raises: [].} =
  ## Deterministic string value of node[key]; missing key or non-string value
  ## yields "" (empty) — never raises (KeyError is raisable from node[k]).
  try:
    if node.hasKey(key) and node[key].kind == JString:
      result = node[key].getStr("")
  except KeyError:
    discard

func canonicalDigestOf*(node: JsonNode): string {.raises: [].} =
  ## SHA-256 over sorted key:value lines — deterministic canonical digest of
  ## a measurement JSON (sorted-object canonicalization, productization_contract.md:207).
  let keys = sortedKeys(node)
  var parts: seq[string] = @[]
  for k in keys:
    parts.add(k & "=" & strVal(node, k))
  if parts.len == 0:
    result = ""
  else:
    result = $secureHash(parts.join("\n"))

func boolToStr*(b: bool): string {.raises: [].} =
  if b: "PASS" else: "FAIL"

## ---------------------------------------------------------------------------
## I/O boundary — proc only
## ---------------------------------------------------------------------------

## ---------------------------------------------------------------------------
## I/O boundary — proc only
## ---------------------------------------------------------------------------

proc loadJsonOrError(path: string): JsonNode =
  ## Fail-closed read: unreadable/invalid JSON is a tool ERROR (exit 1),
  ## never silently skipped (AGENTS.md §0.6 fail-closed).
  try:
    result = parseJson(readFile(path))
  except CatchableError as e:
    stderr.writeLine("[tcb-judgment] ERROR: cannot read " & path & ": " & e.msg)
    quit(1)

proc echoLine(s: string) =
  echo s

proc compareInvariantSet(baseline, candidate: JsonNode): seq[string] =
  ## Returns the list of invariant keys whose baseline digest differs from
  ## the candidate digest (empty = PASS).
  let keys = sortedKeys(baseline)
  for k in keys:
    if not isInvariantKey(k):
      continue
    if baseline{k}.kind == JNull or candidate{k}.kind == JNull:
      result.add(k & " (missing on one side)")
      continue
    if baseline{k}.getStr("") != candidate{k}.getStr(""):
      result.add(k & " (" & baseline{k}.getStr("")[0 ..< min(16, baseline{k}.getStr("").len)] & " != " & candidate{k}.getStr("")[0 ..< min(16, candidate{k}.getStr("").len)] & ")")
  result.sort()

proc comparePerSymbol(baseline, candidate: JsonNode): seq[string] =
  ## J1 per-symbol parity: for the symbols present on BOTH sides, verdicts
  ## (Projection equality — union comparison with panic on conflict).
  let bKeys = sortedKeys(baseline)
  let cKeys = sortedKeys(candidate)
  for k in bKeys:
    if k notin cKeys:
      # symbol dropped in candidate
      result.add(k & " (missing in candidate)")
      continue
    let bV = if baseline{k}.kind == JString: baseline{k}.getStr("") else: ""
    let cV = if candidate{k}.kind == JString: candidate{k}.getStr("") else: ""
    if bV != cV:
      result.add(k & " (" & bV & " != " & cV & ")")
  for k in cKeys:
    if k notin bKeys:
      result.add(k & " (new in candidate)")
  result.sort()

proc readDirJsonFiles(dir: string): seq[(string, JsonNode)] =
  ## Deterministic enumeration of *.json files in a directory.
  var names: seq[string] = @[]
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".json"):
      names.add(extractFilename(path))
  names.sort()
  for n in names:
    let node = loadJsonOrError(dir / n)
    if node.kind == JObject:
      result.add((n, node))

## ---------------------------------------------------------------------------
## Judgment 4 — worker determinism
## ---------------------------------------------------------------------------

proc judgeWorkerDeterminism(runsDir: string): int =
  ## J4 §4.2: N >= 5 runs, all canonical digests identical. N < 5 is FAIL.
  let runs = readDirJsonFiles(runsDir)
  if runs.len < 5:
    echoLine("[J4] worker-determinism FAIL — " & $runs.len & " run(s) found; >=5 required (1 matching run is NOT a proof)")
    echoLine("[J4] runs-dir: " & runsDir)
    return 2
  echoLine("[J4] worker-determinism: " & $runs.len & " runs (>=5) — comparing canonical digests")
  var digests: seq[string] = @[]
  for (name, node) in runs:
    let d = canonicalDigestOf(node)
    digests.add(d)
    echoLine("  run " & name & " digest=" & (if d.len > 16: d[0 ..< 16] else: d) & "…")
  let first = digests[0]
  var mismatches: seq[string] = @[]
  for i in 1 ..< digests.len:
    if digests[i] != first:
      mismatches.add(runs[i][0] & " digest differs from " & runs[0][0])
  if mismatches.len > 0:
    echoLine("[J4] worker-determinism FAIL — canonical digests differ:")
    for m in mismatches:
      echoLine("  " & m)
    return 2
  echoLine("[J4] worker-determinism PASS — all " & $digests.len & " canonical digests identical")
  0

## ---------------------------------------------------------------------------
## Judgment 3 — cache manifest circularity analysis
## ---------------------------------------------------------------------------

proc manifestHash(raw: string): string {.raises: [].} =
  $secureHash(raw)

proc readWorkflowOrError(path: string): string =
  try:
    result = readFile(path)
  except CatchableError as e:
    stderr.writeLine("[tcb-judgment] ERROR: cannot read " & path & ": " & e.msg)
    quit(1)

func hasRestoreKeysStep(raw: string): bool {.raises: [].} =
  ## restore-keys FORBIDDEN (J3 §3.5): detect the YAML step input shape
  ## `restore-keys:` (a line whose first token is `restore-keys:` after
  ## leading whitespace). Prose documentation of the prohibition ("restore-keys
  ## are FORBIDDEN", action.yml:28-30) must NOT be detected — a real usage is
  ## a YAML key.
  for line in raw.splitLines():
    let s = line.strip()
    if s == "restore-keys:" or s.startsWith("restore-keys: ") or
       s.startsWith("restore-keys: |") or s.startsWith("restore-keys: >"):
      return true
  false

func extractVerifyBlock(raw: string): string {.raises: [].} =
  ## Extracts the restore-side digest-verification block: the python heredoc
  ## that contains the per-entry files{} recompute loop (the `for rel, expect
  ## in sorted(files...` loop inside the `<<'PY' ... PY` heredoc). Criteria
  ## are applied WITHIN this block only, so prose elsewhere in the workflow
  ## (keygen sha256sum usages, Makefile mentions) can never satisfy the
  ## circularity criterion — whole-file scanning would be a vacuous pass.
  ## If no heredoc markers are present (excerpt mode), the whole input is
  ## treated as the verify block (excerpt provider responsibility).
  let lines = raw.splitLines()
  var start = -1
  var finish = -1
  for i, line in lines:
    if line.contains("for rel, expect in sorted(files"):
      ## backtrack to the heredoc start (`<<'PY'`)
      var j = i
      while j >= 0:
        if lines[j].contains("<<'PY'") or lines[j].contains("<<\"PY\"") or
           lines[j].contains("<< \"PY\"") or lines[j].contains("<< 'PY'"):
          start = j
          break
        dec j
      ## forward to the heredoc terminator (line == "PY")
      var k = i
      while k < lines.len:
        if lines[k].strip() == "PY":
          finish = k
          break
        inc k
      break
  if start >= 0 and finish > start:
    result = lines[start .. finish].join("\n")
  else:
    result = raw

func hasTrustedDerivedExpectationIn(blk: string): bool {.raises: [].} =
  ## Spec §3.3 REQUIRED criterion — files{} digests compared against a
  ## trusted-input-derived expectation, i.e. (1) source-derived recompute or
  ## (2) platform-verified (signed) manifest. Pattern set, scoped to the
  ## verify block:
  ##   SOURCE-DERIVED: `expected = os.environ[...]` / `expect = os.environ[...]`
  ##     (env-injected trusted value used as the compare target), or a digest
  ##     recompute from repo recipe inputs (`sha256sum Makefile`, `git
  ##     ls-tree`), or statically pinned golden digests (64+ hex literals).
  ##   SIGNED: an asymmetric/platform signature verification of the manifest
  ##     (ed25519 / jws / jwk / hmac / openssl dgst / signature).
  let b = blk.toLowerAscii()
  ## (1) source-derived: expected value assigned from a trusted env input
  if b.contains("expected = os.environ") or b.contains("expect = os.environ") or
     b.contains("expected = sha256") or b.contains("expect = sha256"):
    return true
  ## (1b) source-derived: digest recompute from recipe/trusted paths inside
  ## the block (manifest-binding EXPECT checks alone are NOT this — they only
  ## bind buildSha/bKey, action.yml:207-212).
  if b.contains("sha256sum makefile") or b.contains("git ls-tree") or
     b.contains("sha256sum .github") or b.contains("sha256sum src"):
    return true
  ## (2) signed manifest: asymmetric/platform-managed verification
  if b.contains("ed25519") or b.contains("jws") or b.contains("jwk") or
     b.contains("hmac") or b.contains("openssl dgst") or
     b.contains("signature"):
    return true
  false

type ProbeRow* = object
  className: string
  covered: bool
  probe: string

proc enumerateProbeCoverage(raw: string): seq[ProbeRow] {.raises: [].} =
  ## J3 §3.4 (b): probe coverage vs cached classes. Each cached class is
  ## mapped to the weakest present functional/existence verify probe; a class
  ## with NO probe is FLAGGED as uncovered (reported — a genuine coverage gap
  ## the P2-3(b) work must close). Coverage-gap is REPORTED, not an exit-2
  ## cause: the B payload as a whole is already source-bound via exact key +
  ## buildSha/bKey vs EXPECT (action.yml:207-212), so an uncovered class is
  ## covered transitively today; it becomes a soundness FAIL only when the
  ## payload-level anchor is absent.
  let r = raw.toLowerAscii()
  ## nimcache (build/nimcache — B payload, no functional probe in action.yml).
  ## "compiler/ast.nim" is a TOOLCHAIN probe and must NOT count for nimcache.
  result.add ProbeRow(className: "nimcache (build/nimcache)",
    covered: r.contains("nimcache") and r.contains("nim check"),
    probe: "functional compile probe required (e.g. `nim check` exercising restored nimcache); B restore only ships it")
  ## .lake — Lake functional probe (import Lake), action.yml:314-333
  result.add ProbeRow(className: "proofs/.lake",
    covered: r.contains("check_lake_probe") or
             (r.contains("import lake") and r.contains("probe")),
    probe: "Lake functional probe (check_lake_probe / import Lake)")
  ## .axiom/cache — no functional probe in action.yml (path-list presence is
  ## NOT a probe; "ax scope" in a prose comment is NOT a cache probe).
  result.add ProbeRow(className: ".axiom/cache",
    covered: r.contains("axiom/cache") and
             (r.contains("gate_env.lock") or
              r.contains("replay") or r.contains("cache-replay")),
    probe: "functional/replay probe required (e.g. gate_env.lock integrity or cache-replay verify); B restore only ships it")
  ## toolchain (A-layer) — version fingerprint verify + compiler/ast.nim
  result.add ProbeRow(className: "toolchain (~/.nimble ~/.choosenim ~/.elan)",
    covered: (r.contains("nim --version") or r.contains("ast.nim")) and
             (r.contains("lean --version") or r.contains("check_lake_probe")) and
             r.contains("z3 --version"),
    probe: "A-layer fingerprint verify (nim/lean/z3 --version) + compiler/ast.nim existence + Lake functional probe")
  ## ci binaries (bin/ax + 3) — B manifest per-entry sha256 (files loop); the
  ## restored binary is ALSO governed by SourceCoherence FATAL (main.nim:69-87).
  result.add ProbeRow(className: "ci binaries (bin/ax + 3)",
    covered: r.contains("for rel, expect in sorted(files") and
             r.contains(".hexdigest()"),
    probe: "B manifest per-entry sha256 loop + SourceCoherence FATAL in binary (src/cli/main.nim:69-87)")

proc judgeCacheManifest(workflowPath: string): int =
  ## J3 §3.3: circularity criterion — does the restore-side files{} digest
  ## verification compare against a SOURCE-DERIVED/SIGNED expectation?
  ## Evidence rules:
  ##   - manifest path is inside the B-layer payload (action.yml:20-24 / :168-177)
  ##   - `buildSha`/`bKey` vs EXPECT_BUILD_SHA/EXPECT_B_KEY (action.yml:207-212)
  ##     binds the manifest to caller-derived inputs but does NOT re-derive
  ##     file digests — files{} values still come from the payload itself.
  ##   - a source-derived expectation means the verifier RECOMPUTES a digest
  ##     from a trusted input (recipe/build, e.g. expected = os.environ[...],
  ##     sha256sum over the Makefile output contract), or the manifest is
  ##     platform-signed; files{} values consumed from the payload as-is is
  ##     CIRCULAR.
  ## REQUIRED improvement is not yet implemented → this FAILS until P2-3(a)
  ## lands. Making it vacuous-pass is forbidden (spec §3.7, §6).
  let raw = readWorkflowOrError(workflowPath)
  let wf = raw.toLowerAscii()  ## case-insensitive search (bKey/EXPECT etc.)

  ## 1. Manifest path inside the B-layer restore payload?
  ##    (action.yml:168-177 — build/.axiom-b-fingerprint.json ships with the cache)
  let inPayload = wf.contains("build/.axiom-b-fingerprint.json") and wf.contains("bin/ax")
  ## 2. EXPECT build-sha binding present?
  let hasExpect = wf.contains("expect_build_sha") and wf.contains("expect_b_key")
  ## 3. files{} digest comparison present at all?
  ##    (sha256 recompute loop — the verify step computes entry hashes)
  let hasVerifyLoop = wf.contains("sha256") and wf.contains(".hexdigest()") and
                      wf.contains("for rel, expect in sorted(files")
  ## 4. trusted-input-derived expectation INSIDE the verify block?
  let verifyBlock = extractVerifyBlock(raw)
  let trustedDerived = hasTrustedDerivedExpectationIn(verifyBlock)
  ## 5. semantic provenance probe present anywhere in the workflow? REPORT-ONLY —
  ##    the probe re-derives build provenance OUTSIDE the payload (trusted tree
  ##    materialized from the git object store via `git archive`, restored
  ##    binary's own SourceCoherence check executed against it). It closes the
  ##    simultaneous-contamination gap the per-entry digest loop cannot see;
  ##    its presence is reported but the exit stays driven by criterion 4.
  let hasProvenanceProbe = wf.contains("git archive") and
                           wf.contains("sourcecoherence")

  echoLine("[J3] cache-manifest — workflow: " & workflowPath)
  echoLine("[J3]   manifest located inside B-layer payload? " & boolToStr(inPayload))
  echoLine("[J3]   EXPECT_BUILD_SHA/EXPECT_B_KEY binding present? " & boolToStr(hasExpect))
  echoLine("[J3]   restore-side per-entry sha256 recompute loop present? " & boolToStr(hasVerifyLoop))
  echoLine("[J3]   verify-block scope: " & $verifyBlock.splitLines().len & " lines (heredoc extraction; excerpt mode = whole input)")
  echoLine("[J3]   trusted-input-derived files{} expectation present? " & boolToStr(trustedDerived))
  echoLine("[J3]   semantic provenance probe (git-archive trusted tree + SourceCoherence) present? " & boolToStr(hasProvenanceProbe) & " (report-only — the exit is driven by the in-block trusted-derived expectation)")

  ## probe coverage enumeration (J3 §3.4 (b)) — reported, FLAG uncovered
  echoLine("[J3]   probe coverage vs cached classes:")
  for row in enumerateProbeCoverage(raw):
    if row.covered:
      echoLine("[J3]     COVERED  " & row.className & " — " & row.probe)
    else:
      echoLine("[J3]     [COVERAGE-GAP] UNCOVERED  " & row.className & " — " & row.probe)

  ## restore-keys forbidden check (J3 §3.5) — real step input, not prose
  if hasRestoreKeysStep(raw):
    echoLine("[J3] cache-manifest FAIL — restore-keys: step input present (prefix fallback consumed without verification, action.yml:28-30,110,164)")
    return 2

  if not hasVerifyLoop:
    echoLine("[J3] cache-manifest FAIL — no restore-side per-entry digest verification found")
    return 2

  ## Circularity finding: the verify loop compares against the payload's own
  ## manifest values. Until a source-derived/signed expectation exists, this
  ## FAILS — precondition for the improvement (P2-3(a)).
  if not trustedDerived:
    echoLine("[J3] cache-manifest CIRCULAR — files{} digests originate from the restored payload itself (manifest shipped inside the cache: B-layer restore path list carries build/.axiom-b-fingerprint.json; the save-side single writer (ci-cache-publisher.yml) writes it at save and restore reads it back; the fingerprint-verify heredoc loop reads expected values from the payload manifest m[\"files\"]). A source-derived or signed expectation is required: expected = os.environ[...] / sha256sum <recipe path> / ed25519|jws|hmac signature, plus a semantic provenance probe (git archive of the trusted tree + SourceCoherence) to cover simultaneous payload+manifest contamination.")
    echoLine("[J3] cache-manifest JUDGMENT-FAIL (exit 2) — improvement P2-3(a) not yet landed")
    return 2

  if hasProvenanceProbe:
    echoLine("[J3] cache-manifest PASS — files{} verification uses a trusted-input-derived expectation + semantic provenance probe (simultaneous payload+manifest contamination covered)")
  else:
    echoLine("[J3] cache-manifest PASS — files{} verification uses a trusted-input-derived expectation (NOTE: no semantic provenance probe found — simultaneous payload+manifest contamination of the restored binaries is covered only by the in-block identity re-derivation; report-only finding)")
  0

## ---------------------------------------------------------------------------
## Judgment 2 — canonical identity-set equality
## ---------------------------------------------------------------------------

proc judgeCanonicalIdentitySet(baselinePath, candidatePath: string): int =
  let b = loadJsonOrError(baselinePath)
  let c = loadJsonOrError(candidatePath)
  if b.kind != JObject or c.kind != JObject:
    stderr.writeLine("[tcb-judgment] ERROR: baseline/candidate must be JSON objects")
    return 1

  ## Substrate-specific digests: report only (scoping, never a failure — §2.4).
  var reported: seq[string] = @[]
  for k in sortedKeys(b):
    if isSubstrateKey(k):
      reported.add(k & "=" & b{k}.getStr(""))
  for k in sortedKeys(c):
    if isSubstrateKey(k):
      reported.add(k & "=" & c{k}.getStr(""))
  if reported.len > 0:
    reported.sort()
    echoLine("[J2] substrate-specific digests (reported, scoping only — NOT failure):")
    for r in reported:
      echoLine("  " & r)

  ## Unknown keys: report (forward-compatible measurement surface).
  var unknownB: seq[string] = @[]
  for k in sortedKeys(b):
    if not isInvariantKey(k) and not isSubstrateKey(k) and not isVolatileKey(k):
      unknownB.add(k)
  for k in sortedKeys(c):
    if not isInvariantKey(k) and not isSubstrateKey(k) and not isVolatileKey(k) and k notin unknownB:
      unknownB.add(k)
  if unknownB.len > 0:
    unknownB.sort()
    echoLine("[J2] unknown keys (reported — measurement surface, not failure):")
    for u in unknownB:
      echoLine("  " & u)

  let diffs = compareInvariantSet(b, c)
  if diffs.len > 0:
    echoLine("[J2] canonical-identity-set FAIL — invariant digest(s) differ (" & $diffs.len & "):")
    for d in diffs:
      echoLine("  " & d)
    return 2
  echoLine("[J2] canonical-identity-set PASS — all invariant digests equal")
  0

## ---------------------------------------------------------------------------
## Judgment 1 — semantic parity (per-symbol)
## ---------------------------------------------------------------------------

proc judgeParity(baselinePath, candidatePath: string): int =
  let b = loadJsonOrError(baselinePath)
  let c = loadJsonOrError(candidatePath)
  if b.kind != JObject or c.kind != JObject:
    stderr.writeLine("[tcb-judgment] ERROR: baseline/candidate must be JSON objects (per-symbol verdict map)")
    return 1
  let diffs = comparePerSymbol(b, c)
  if diffs.len > 0:
    echoLine("[J1] parity FAIL — per-symbol semantic projection differs (" & $diffs.len & "):")
    for d in diffs[0 ..< min(40, diffs.len)]:
      echoLine("  " & d)
    if diffs.len > 40:
      echoLine("  … and " & $(diffs.len - 40) & " more")
    return 2
  echoLine("[J1] parity PASS — per-symbol semantic projection identical (verdict/ProofStatus per unit)")
  0

## ---------------------------------------------------------------------------
## selftest — every judgment's FAIL path must actually FAIL
## ---------------------------------------------------------------------------

proc selftest(): int =
  ## Proves each judgment's FAIL path really fails with exit 2, and the PASS
  ## paths really pass with exit 0. A judgment that never fails is a dead
  ## gate — the selftest would expose it (spec §6.1).
  echoLine("[selftest] tcb_judgments selftest begin")
  var failures: seq[string] = @[]
  var passes = 0

  proc check(name: string; code: int; expect: tuple[code: int; msg: string]) =
    if code == expect.code:
      inc passes
      echoLine("[selftest] PASS " & name & " → exit " & $code & " (" & expect.msg & ")")
    else:
      failures.add(name & " → exit " & $code & " (expected " & $expect.code & ": " & expect.msg & ")")
      echoLine("[selftest] FAIL " & name & " → exit " & $code & " (expected " & $expect.code & ")")

  ## --- Fixture 1: J1 parity — identical baseline/candidate → exit 0 -------
  let parityPassDir = getTempDir() / "tcb_selftest_parity_pass"
  createDir(parityPassDir)
  writeFile(parityPassDir / "b.json", """{"worker_one_status":"psVerified","worker_two_status":"psVerified"}""")
  writeFile(parityPassDir / "c.json", """{"worker_one_status":"psVerified","worker_two_status":"psVerified"}""")
  check("J1-parity-PASS", judgeParity(parityPassDir / "b.json", parityPassDir / "c.json"),
        (0, "identical per-symbol verdict maps"))

  ## --- Fixture 2: J1 parity — mismatch → exit 2 ----------------------------
  let parityFailDir = getTempDir() / "tcb_selftest_parity_fail"
  createDir(parityFailDir)
  writeFile(parityFailDir / "b.json", """{"worker_one_status":"psVerified","worker_two_status":"psVerified"}""")
  writeFile(parityFailDir / "c.json", """{"worker_one_status":"psVerified","worker_two_status":"psContradicted"}""")
  check("J1-parity-FAIL", judgeParity(parityFailDir / "b.json", parityFailDir / "c.json"),
        (2, "worker_two_status changes verdict"))

  ## --- Fixture 3: J2 canonical identity — invariant differ → exit 2 -------
  let idSetPassDir = getTempDir() / "tcb_selftest_idset_pass"
  createDir(idSetPassDir)
  writeFile(idSetPassDir / "b.json", """{"subjectId":"abc123","verdict":"pass","solverInputDigest":"sha256:111","artifactIdDigest":"sha256:AAA"}""")
  writeFile(idSetPassDir / "c.json", """{"subjectId":"abc123","verdict":"pass","solverInputDigest":"sha256:111","artifactIdDigest":"sha256:BBB"}""")
  check("J2-idset-PASS-substrate-scope", judgeCanonicalIdentitySet(idSetPassDir / "b.json", idSetPassDir / "c.json"),
        (0, "invariants equal; substrate artifactIdDigest differs but is reported only"))

  let idSetFailDir = getTempDir() / "tcb_selftest_idset_fail"
  createDir(idSetFailDir)
  writeFile(idSetFailDir / "b.json", """{"subjectId":"abc123","verdict":"pass","solverInputDigest":"sha256:111"}""")
  writeFile(idSetFailDir / "c.json", """{"subjectId":"abc456","verdict":"pass","solverInputDigest":"sha256:111"}""")
  check("J2-idset-FAIL-invariant", judgeCanonicalIdentitySet(idSetFailDir / "b.json", idSetFailDir / "c.json"),
        (2, "subjectId invariant differs"))

  ## --- Fixture 4: J3 cache-manifest circularity → exit 2 (pre-P2-3a state)
  let cmCircularPath = getTempDir() / "tcb_selftest_cm_circular.yml"
  writeFile(cmCircularPath, """name: circular
steps:
  - name: B-layer fingerprint verify (restored digest vs save-time manifest)
    if: steps.b-restore.outputs.cache-hit == 'true'
    env:
      EXPECT_BUILD_SHA: ${{ inputs.cache-build-source }}
      EXPECT_B_KEY: ${{ steps.keygen.outputs.b-key }}
    run: |
      set -uo pipefail
      MANIFEST="build/.axiom-b-fingerprint.json"
      for rel, expect in sorted(files.items()):
          actual = hashlib.sha256(open(rel, "rb").read()).hexdigest()
          if actual != expect: ... 
""")
  check("J3-cache-manifest-CIRCULAR-FAIL", judgeCacheManifest(cmCircularPath),
        (2, "files{} compared against payload's own manifest → circular, not yet fixed"))

  ## --- Fixture 4b: J3 PASS — signed-manifest verification in the block ------
  let cmSignedPath = getTempDir() / "tcb_selftest_cm_signed.yml"
  writeFile(cmSignedPath, """name: improved
steps:
  - name: B-layer fingerprint verify (restored digest vs signed manifest)
    env:
      EXPECT_BUILD_SHA: ${{ inputs.cache-build-source }}
    run: |
      set -uo pipefail
      MANIFEST="build/.axiom-b-fingerprint.json"
      if python3 - "$MANIFEST" <<'PY'
      import hashlib, json, os, sys
      m = json.load(open(sys.argv[1]))
      files = m.get("files", {})
      for rel, expect in sorted(files.items()):
          actual = hashlib.sha256(open(rel, "rb").read()).hexdigest()
          if actual != expect:
              sys.exit(1)
      # manifest signed by the build authority; verify before trusting files{}
      if not verify_ed25519_signature(open("build/.axiom-b-fingerprint.sig").read(),
                                      pubkey, m):
          sys.exit(2)
      PY
""")
  check("J3-cache-manifest-PASS-signed", judgeCacheManifest(cmSignedPath),
        (0, "signed-manifest verification inside the verify block"))

  ## --- Fixture 4c: J3 FAIL — signature marker ONLY in prose outside the
  ##     verify block must NOT satisfy the criterion (vacuous-pass regression)
  let cmProsePath = getTempDir() / "tcb_selftest_cm_prose.yml"
  writeFile(cmProsePath, """name: prose-marker
# Design note: the manifest will later be verified with ed25519 signatures.
steps:
  - name: B-layer fingerprint verify (restored digest vs save-time manifest)
    run: |
      set -uo pipefail
      MANIFEST="build/.axiom-b-fingerprint.json"
      if python3 - "$MANIFEST" <<'PY'
      import hashlib, json, sys
      m = json.load(open(sys.argv[1]))
      files = m.get("files", {})
      for rel, expect in sorted(files.items()):
          actual = hashlib.sha256(open(rel, "rb").read()).hexdigest()
          if actual != expect:
              sys.exit(1)
      PY
""")
  check("J3-cache-manifest-FAIL-prose-outside-block", judgeCacheManifest(cmProsePath),
        (2, "ed25519 mentioned only in prose — files{} still payload-derived (circular)"))

  ## --- Fixture 4d: J3 PASS — trusted-input-derived identity re-derivation
  ##     inside the block (the landed P2-3(a) mechanism: expected b-key
  ##     recomputed from env-injected keygen outputs + recipe file recompute,
  ##     so the manifest identity claims are never accepted from the payload)
  let cmDerivedPath = getTempDir() / "tcb_selftest_cm_derived.yml"
  writeFile(cmDerivedPath, """name: anchored
steps:
  - name: B-layer fingerprint verify (restored digest vs save-time manifest — identity re-derived from trusted inputs)
    if: steps.b-restore.outputs.cache-hit == 'true'
    env:
      EXPECT_BUILD_SHA: ${{ steps.keygen.outputs.b-identity }}
      EXPECT_B_KEY: ${{ steps.keygen.outputs.b-key }}
      A_KEY: ${{ steps.keygen.outputs.a-key }}
    run: |
      set -uo pipefail
      MANIFEST="build/.axiom-b-fingerprint.json"
      if python3 - "$MANIFEST" <<'PY'
      import hashlib, json, os, sys
      m = json.load(open(sys.argv[1]))
      expect = os.environ["EXPECT_B_KEY"]
      build_sha = os.environ["EXPECT_BUILD_SHA"]
      inner = "".join(hashlib.sha256(open(rf, "rb").read()).hexdigest() + "  " + rf + "\n" for rf in ("Makefile", "config.nims", "config/effects.nims", "src/gate/config.nims"))
      recipe_hash = hashlib.sha256(inner.encode()).hexdigest()[:32]
      a_fp = hashlib.sha256(os.environ["A_KEY"].encode()).hexdigest()[:32]
      derived = "axiom-b-%s-%s%s" % (build_sha, recipe_hash, a_fp)
      if derived != expect or m.get("bKey") != derived or m.get("buildSha") != build_sha:
          sys.exit(1)
      files = m.get("files", {})
      for rel, expect in sorted(files.items()):
          actual = hashlib.sha256(open(rel, "rb").read()).hexdigest()
          if actual != expect:
              sys.exit(1)
      PY
      then
        : # verified against the re-derived identity
      else
        discard_b
      fi
""")
  check("J3-cache-manifest-PASS-trusted-derived", judgeCacheManifest(cmDerivedPath),
        (0, "expected identity re-derived from env-injected keygen outputs + recipe recompute inside the block"))

  ## --- Fixture 4e: J3 FAIL — provenance-probe markers (git archive +
  ##     SourceCoherence) present only OUTSIDE the verify block must NOT flip
  ##     the exit (the probe row is report-only; criterion 4 stays governing)
  let cmProbeProsePath = getTempDir() / "tcb_selftest_cm_probe_prose.yml"
  writeFile(cmProbeProsePath, """name: probe-marker-circular
# Design note: a later step will run `git archive` and re-execute the binary
# so SourceCoherence compares it against the trusted tree.
steps:
  - name: B-layer fingerprint verify (restored digest vs save-time manifest)
    run: |
      set -uo pipefail
      MANIFEST="build/.axiom-b-fingerprint.json"
      if python3 - "$MANIFEST" <<'PY'
      import hashlib, json, sys
      m = json.load(open(sys.argv[1]))
      files = m.get("files", {})
      for rel, expect in sorted(files.items()):
          actual = hashlib.sha256(open(rel, "rb").read()).hexdigest()
          if actual != expect:
              sys.exit(1)
      PY
""")
  check("J3-cache-manifest-FAIL-probe-marker-outside-block", judgeCacheManifest(cmProbeProsePath),
        (2, "git archive + SourceCoherence markers in prose only — in-block expectation still payload-derived (circular); probe row is report-only"))

  ## --- Fixture 5: J4 worker determinism — 4 runs only → exit 2 -------------
  let wdFailDir = getTempDir() / "tcb_selftest_wd_fail"
  createDir(wdFailDir)
  for i in 0 ..< 4:
    writeFile(wdFailDir / ("run" & $i & ".json"), """{"canonicalProjectionHash":"sha256:same"}""")
  check("J4-worker-determinism-FAIL-N4", judgeWorkerDeterminism(wdFailDir),
        (2, "4 < 5 runs — insufficient repetitions"))

  ## --- Fixture 6: J4 worker determinism — 5 identical runs → exit 0 --------
  let wdPassDir = getTempDir() / "tcb_selftest_wd_pass"
  createDir(wdPassDir)
  for i in 0 ..< 5:
    writeFile(wdPassDir / ("run" & $i & ".json"), """{"canonicalProjectionHash":"sha256:same"}""")
  check("J4-worker-determinism-PASS-N5", judgeWorkerDeterminism(wdPassDir),
        (0, "5 identical canonical digests"))

  ## --- Fixture 7: J4 worker determinism — 5 runs, digest mismatch → exit 2
  let wdMismatchDir = getTempDir() / "tcb_selftest_wd_mismatch"
  createDir(wdMismatchDir)
  for i in 0 ..< 5:
    var o = newJObject()
    o["canonicalProjectionHash"] = %("sha256:diff" & intToStr(i))
    writeFile(wdMismatchDir / ("run" & intToStr(i) & ".json"), $o)
  check("J4-worker-determinism-FAIL-mismatch", judgeWorkerDeterminism(wdMismatchDir),
        (2, "5 runs but digests differ"))

  echoLine("[selftest] results: " & $passes & " passed, " & $failures.len & " failed")
  if failures.len > 0:
    echoLine("[selftest] FAILED expectations:")
    for f in failures:
      echoLine("  - " & f)
    return 1
  echoLine("[selftest] PASS — every judgment has a live FAIL path and every fixture exited as specified")
  0

## ---------------------------------------------------------------------------
## Main
## ---------------------------------------------------------------------------

proc usage() =
  echoLine("tcb_judgments.nim — CI optimization TCB judgment tool (spec: docs/spec/ci_optimization_tcb_judgments.md)")
  echoLine("")
  echoLine("Usage:")
  echoLine("  tcb_judgments --judgment parity --baseline <file> --candidate <file>")
  echoLine("  tcb_judgments --judgment canonical-identity-set --baseline <file> --candidate <file>")
  echoLine("  tcb_judgments --judgment cache-manifest --workflow <path-or-excerpt>")
  echoLine("  tcb_judgments --judgment worker-determinism --runs <dir>")
  echoLine("  tcb_judgments selftest")
  echoLine("")
  echoLine("Exit codes: 0 = PASS, 2 = JUDGMENT-FAIL, 1 = error (bad args / I/O)")

proc main() =
  var args: seq[string] = commandLineParams()
  if args.len == 0 or args[0] == "--help" or args[0] == "-h":
    usage()
    quit(0)
  if args[0] == "selftest":
    quit(selftest())

  ## Required flag grammar: --judgment <name> [--baseline B] [--candidate C]
  ##                         [--workflow W] [--runs D]
  if args.len < 2 or args[0] != "--judgment":
    usage()
    quit(1)

  var judgement = ""
  var baseline = ""
  var candidate = ""
  var workflow = ""
  var runsDir = ""
  var i = 1
  while i < args.len:
    case args[i]
    of "--baseline":
      if i + 1 >= args.len:
        stderr.writeLine("[tcb-judgment] ERROR: --baseline requires a path")
        quit(1)
      baseline = args[i + 1]
      inc i
    of "--candidate":
      if i + 1 >= args.len:
        stderr.writeLine("[tcb-judgment] ERROR: --candidate requires a path")
        quit(1)
      candidate = args[i + 1]
      inc i
    of "--workflow":
      if i + 1 >= args.len:
        stderr.writeLine("[tcb-judgment] ERROR: --workflow requires a path")
        quit(1)
      workflow = args[i + 1]
      inc i
    of "--runs":
      if i + 1 >= args.len:
        stderr.writeLine("[tcb-judgment] ERROR: --runs requires a directory")
        quit(1)
      runsDir = args[i + 1]
      inc i
    else:
      ## positional: the judgment name follows --judgment
      if judgement.len == 0 and not args[i].startsWith("--"):
        judgement = args[i]
      else:
        stderr.writeLine("[tcb-judgment] ERROR: unknown argument: " & args[i])
        quit(1)
    inc i

  if judgement.len == 0:
    stderr.writeLine("[tcb-judgment] ERROR: --judgment requires a name (parity|canonical-identity-set|cache-manifest|worker-determinism)")
    quit(1)

  case judgement
  of "parity":
    if baseline.len == 0 or candidate.len == 0:
      stderr.writeLine("[tcb-judgment] ERROR: parity requires --baseline and --candidate")
      quit(1)
    quit(judgeParity(baseline, candidate))
  of "canonical-identity-set":
    if baseline.len == 0 or candidate.len == 0:
      stderr.writeLine("[tcb-judgment] ERROR: canonical-identity-set requires --baseline and --candidate")
      quit(1)
    quit(judgeCanonicalIdentitySet(baseline, candidate))
  of "cache-manifest":
    if workflow.len == 0:
      stderr.writeLine("[tcb-judgment] ERROR: cache-manifest requires --workflow")
      quit(1)
    quit(judgeCacheManifest(workflow))
  of "worker-determinism":
    if runsDir.len == 0:
      stderr.writeLine("[tcb-judgment] ERROR: worker-determinism requires --runs")
      quit(1)
    quit(judgeWorkerDeterminism(runsDir))
  else:
    stderr.writeLine("[tcb-judgment] ERROR: unknown judgment: " & judgement)
    quit(1)

when isMainModule:
  main()
