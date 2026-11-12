import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
## Shared Baseline Snapshot Core — SSOT for `tools/baseline_snapshot.nim`
## and the `ax baseline` CLI command (Phase 2 WS-4).
##
## Captures the stable certificate vault (`src/verification/certificates`)
## as a single audit baseline written to `data/baseline.json`.
##
## Both entry points share this logic so that `ax baseline check` compares
## against exactly what `ax baseline update` (and the standalone tool) writes.
##
## Determinism: the snapshot carries a content-derived `timestamp` (SHA-1 of the
## sorted vault content) rather than wall-clock time, so identical vault input
## always produces byte-identical `data/baseline.json` output (§0.2).

import std/[json, os, strutils, tables, math, algorithm]
import checksums/sha2
import core/types/vkd_types
import core/types/results
import core/types/certificate_types
import core/types/verification_tier
import core/utils/io_utils
import cli/shared/proof_hydration
import core/trusted/axiom_pragmas
import core/parsers/safe_parsers
import core/proof/proof_integrity
import verification/certificate_verifier
import verification/obligation/metrics_io  ## P6: canonical metrics file

const
  ProofVaultDir* = "src/verification/certificates"
  BaselineDataDir* = "data"
  BaselineFileName* = "baseline.json"
  ErrEmptyVaultExit* = 2     ## Zero-Theater Exit Contract (ADR-0010): empty vault
  ErrBaselineDegradedExit* = 1  ## VKD_current < VKD_baseline (or no baseline found)
  OkBaselineExit* = 0        ## VKD_current >= VKD_baseline

type
  TierKey* = enum
    tkNone = "none"
    tkZ3Verified = "z3-verified"
    tkLeanVerified = "lean-verified"
    tkDualVerified = "dual-verified"
    tkUnknown = "unknown"

  SoundnessKey* = enum
    skSafe = "safe"
    skDebt = "debt"
    skUnknown = "unknown"

  BaselineSnapshot* = object
    vkdFixed4*: string
    timestamp*: string
    totalFunctions*: int
    verifiedFunctions*: int
    vkdScore*: float
    coverageRatio*: float
    rigorScore*: float
    tierDistribution*: Table[string, int]
    certificatesByTier*: Table[string, seq[string]]
    soundnessMode*: string
    topSourceModules*: seq[tuple[name: string, count: int]]
    kernelTotal*: int            ## |Kernel| — full kernel scope count (verification_scope.lock)
    kernelExemptTotal*: int        ## |Kernel∖Exempt| = kernelTotal − exempt count
    vksTotal*: int  ## |VKS| — proof-bearing (non-exempt) kernel symbols
    ogr*: float  ## P6: Obligation Grounding Rate (runtime, 0.0 when unavailable)
    par*: float  ## P6: Proof Attempt Rate (runtime, 0.0 when unavailable)

proc collectTier*(tierStr: string): TierKey =
  case tierStr.toLowerAscii()
  of "none": tkNone
  of "z3-verified", "z3only", "certz3verified": tkZ3Verified
  of "lean-verified", "leanonyl", "certleanverified": tkLeanVerified
  of "dual-verified", "dual", "certdualverified": tkDualVerified
  else: tkUnknown

proc collectSoundness*(status: string): SoundnessKey =
  case status
  of "certSafetyVerified", "certZ3Candidate", "certLeanVerified",
     "certDualVerified", "certTypeLevelVerified", "certWellFormed",
     "certVerifiedAxiom", "certPseudoVerified": skSafe
  of "certSoundnessDebt": skDebt
  else: skUnknown

proc collectModuleFrequency*(certs: seq[JsonNode]): seq[tuple[name: string, count: int]] =
  var freq = initCountTable[string]()
  for cert in certs:
    let modPath = cert{"modulePath"}.getStr("unknown")
    freq.inc(modPath)
  for k, v in freq.pairs:
    result.add((k, v))
  result.sort(proc(a, b: tuple[name: string, count: int]): int =
    cmp(b.count, a.count)
  )

proc readStableVaultCerts*(dir: string): seq[JsonNode] =
  ## Reads all JSON certificates from the stable vault directory.
  if not dirExists(dir):
    return @[]
  for kind, path in walkDir(dir):
    if kind != pcFile or not path.endsWith(".json"): continue
    try:
      let content = readFile(path)
      let node = parseJson(content)
      if node.kind == JObject:
        result.add(node)
    except CatchableError:  # axiom:best-effort(unreadable or malformed cert skipped from informational snapshot)
      discard

proc deterministicSnapshotId*(certs: seq[JsonNode]): string =
  ## Deterministic snapshot identity — stable across runs on an unchanged vault.
  ## Derived from the sorted, canonical content of every certificate so that
  ## identical input (vault) always yields identical output (Determinism, §0.2).
  var parts: seq[string] = @[]
  for cert in certs:
    let idField = cert{"irHash"}.getStr(cert{"fingerprint"}.getStr(""))
    parts.add(idField)
    parts.add(cert{"functionName"}.getStr(""))
  parts.sort()
  var hasher = initSha_256()
  hasher.update(parts.join("\n"))
  result = $hasher.digest()

proc countKernelVerified*(certs: seq[JsonNode]; scope: KernelScopeInfo): int {.raises: [].} =
  ## CANONICAL VKD numerator predicate — the number of kernel symbols that are
  ## admitted via proof_integrity.isVkdAdmissible (certGreen-only gate).
  ##
  ## # CANONICAL DECLARATION: proof_integrity.isVkdAdmissible (composing
  ## isDeepVerified → certificate_verifier.isDeepVerified) is the SINGLE GENUINE
  ## QUALIFICATION PREDICATE. All callers (this function, countKernelSymbolsDeepVerified
  ## in proof_hydration.nim, and report_cli.nim) delegate to it — ensuring
  ## single-path VKD convergence. No alternative qualification logic must be
  ## introduced or this comment invalidated.
  ##
  ## For each symbol in scope.kernelSymbols (`modulePath::functionName`), +1 when a
  ## matching certificate passes the unified VKD admission predicate
  ## (proof_integrity.isVkdAdmissible).
  ##
  ## Set Membership is satisfied by construction: we only iterate over
  ## `scope.kernelSymbols` and a matching cert's `modulePath::functionName` equals
  ## the symbol being counted. Fail-closed: an empty/degraded scope yields 0.
  result = proof_hydration.countKernelSymbolsDeepVerified(scope,
    proc (modulePath: string; functionName: string): JsonNode {.raises: [].} =
      for cert in certs:
        if cert{"modulePath"}.getStr("") == modulePath and
           cert{"functionName"}.getStr("") == functionName:
          return cert
      nil
    , certificate_verifier.isDeepVerified)

proc computeBaselineSnapshot*(certDir: string; scope: KernelScopeInfo): BaselineSnapshot {.axiomDecision.} =
  ## Scans the stable vault and builds a BaselineSnapshot.
  ##
  ## VKD (vkdScore/coverageRatio/rigorScore/vkdFixed4) is now single-predicate —
  ## driven by `proof_integrity` (Phase 3 WS-B). Denominator = scope.kernelTotal
  ## (|Kernel| from verification_scope.lock), numerator = deep-verified kernel
  ## symbols. This replaces the former self-traversed vault count + weakened
  ## isDeepVerified (solverMeta.leanCompilerVerified only), which was theater (§0.9):
  ## it claimed 0.9955 while an honest VKD is |deep-verified kernel| / |Kernel|.
  ##
  ## NOTE (lock degradation): the tool itself never calls generateAxiomInit, so the
  ## lock is preserved here. But if a build macro overwrote the lock to a partial
  ## value (e.g. 19), loadKernelScope returns an empty scope -> verified=0 and
  ## total=0 -> fail-closed (vkdScore 0.0). Regenerate with `nim c
  ## src/cli/axiom_engine.nim` (kernel_total from verification_scope.lock, SSOT) before re-running.
  let certs = readStableVaultCerts(certDir)
  let kernelTotal = scope.kernelTotal
  let verifiedCount = countKernelVerified(certs, scope)
  let metrics = computeVkd(verifiedCount, kernelTotal)

  result = BaselineSnapshot(
    vkdFixed4: metrics.vkdFixed4,
    timestamp: deterministicSnapshotId(certs),
    totalFunctions: kernelTotal,        # |Kernel| — kernel symbols in verification_scope.lock
    verifiedFunctions: verifiedCount,
    vkdScore: metrics.coverageRatio,
    coverageRatio: metrics.coverageRatio,
    rigorScore: metrics.coverageRatio * 3.0,
    kernelTotal: kernelTotal,
    kernelExemptTotal: kernelTotal - scope.vksTotal,
    vksTotal: scope.vksTotal,
    tierDistribution: initTable[string, int](),
    soundnessMode: "none",
    certificatesByTier: initTable[string, seq[string]](),
    topSourceModules: collectModuleFrequency(certs)
  )

  if certs.len == 0:
    return

  var tierDist = initTable[string, int]()
  var tierCerts = initTable[string, seq[string]]()
  var soundnessCounts = initTable[SoundnessKey, int]()

  for cert in certs:
    let tierStr = cert{"verificationTier"}.getStr("none")
    let tierLabel = $collectTier(tierStr)
    tierDist[tierLabel] = tierDist.getOrDefault(tierLabel, 0) + 1

    let fnName = cert{"functionName"}.getStr("unknown")
    if not tierCerts.hasKey(tierLabel):
      tierCerts[tierLabel] = @[]
    tierCerts[tierLabel].add(fnName)

    let status = cert{"status"}.getStr("")
    let sk = collectSoundness(status)
    soundnessCounts[sk] = soundnessCounts.getOrDefault(sk, 0) + 1

  let safeCount = soundnessCounts.getOrDefault(skSafe, 0)
  let debtCount = soundnessCounts.getOrDefault(skDebt, 0)

  var soundnessStr = "none"
  if certs.len > 0 and debtCount == 0 and safeCount > 0:
    soundnessStr = "safe"
  elif debtCount > 0:
    soundnessStr = "debt"

  result.tierDistribution = tierDist
  result.soundnessMode = soundnessStr
  result.certificatesByTier = tierCerts
  result.topSourceModules = collectModuleFrequency(certs)

  # P6: Merge OGR/PAR from canonical metrics file if available.
  # Additive: only overwrite when the file contains non-zero values
  # (i.e., a prove run has completed and written real counters).
  let diskMetrics = readObligationMetrics()
  if diskMetrics.ogr > 0.0:
    result.ogr = diskMetrics.ogr
  if diskMetrics.par > 0.0:
    result.par = diskMetrics.par

proc snapshotToJson*(snap: BaselineSnapshot): JsonNode =
  result = newJObject()
  result["vkdFixed4"] = newJString(snap.vkdFixed4)
  result["timestamp"] = newJString(snap.timestamp)
  result["totalFunctions"] = newJInt(snap.totalFunctions)
  result["verifiedFunctions"] = newJInt(snap.verifiedFunctions)
  result["vkdScore"] = newJFloat(snap.vkdScore)
  result["coverageRatio"] = newJFloat(snap.coverageRatio)
  result["rigorScore"] = newJFloat(snap.rigorScore)
  result["soundnessMode"] = newJString(snap.soundnessMode)

  var tiers = newJObject()
  for k, v in snap.tierDistribution.pairs:
    tiers[k] = newJInt(v)
  result["tierDistribution"] = tiers

  var byTier = newJObject()
  for k, v in snap.certificatesByTier.pairs:
    var arr = newJArray()
    for fn in v:
      arr.add(newJString(fn))
    byTier[k] = arr
  result["certificatesByTier"] = byTier

  var modules = newJArray()
  for (name, count) in snap.topSourceModules:
    var entry = newJObject()
    entry["module"] = newJString(name)
    entry["count"] = newJInt(count)
    modules.add(entry)
  result["topSourceModules"] = modules

  # ── Canonical scope snapshot (schema additive; backward-compatible) ──
  result["kernelTotal"] = %snap.kernelTotal      # |K|
  result["kernelExemptTotal"] = %snap.kernelExemptTotal  # |E|
  result["vksTotal"] = %snap.vksTotal   # |VKS| = |K∖E|
  result["kernelVerified"] = %snap.verifiedFunctions  # |VKS ∩ verified|
  let vksRatio = if snap.vksTotal > 0:
      snap.verifiedFunctions.float / snap.vksTotal.float else: 0.0
  let rawRatio = if snap.kernelTotal > 0: snap.verifiedFunctions.float / snap.kernelTotal.float else: 0.0
  result["metrics"] = %*{
    # VKD — Verified Kernel Density = |VKS ∩ verified| / |VKS|
    "vkd": {
      "verified": snap.verifiedFunctions,
      "total": snap.vksTotal,
      "ratio": vksRatio
    },
    # rawKernelCoverage (legacy CI threshold) = |K ∩ verified| / |K|
    "rawKernelCoverage": {
      "verified": snap.verifiedFunctions,
      "total": snap.kernelTotal,
      "ratio": rawRatio
    }
  }
  # P6: OGR/PAR are additive fields — included only when non-zero
  # (runtime counters are available only after a prove run).
  if snap.ogr > 0.0:
    result["metrics"]["ogr"] = %snap.ogr
  if snap.par > 0.0:
    result["metrics"]["par"] = %snap.par
  # DEBT#409 — vkdFixed4 (top-level baseline field) is the LEGACY CI THRESHOLD
  # view: verifiedFunctions / kernel_total (denominator = |K| = 40, the FULL
  # kernel scope, NOT |VKS| = 23). It is NOT canonical VKD. It is the sole value
  # consumed by `ax baseline check` / cmdBaselineCheck for monotonic comparison
  # (see docs/spec/verification_density.md §Binary Contract). Canonical VKD
  # (|VKS ∩ certGreen| / |VKS|) lives in metrics.vkd above and is projected by
  # getCanonicalVkdMetrics in report_cli.nim. Field preserved verbatim.

proc writeBaseline*(path: string; snap: BaselineSnapshot): Result[void, string] {.axiomDecision.} =
  ## Writes snapshot JSON atomically (tmp + fsync + rename via writeFileAtomic).
  let dir = parentDir(path)
  if dir.len > 0 and not dirExists(dir):
    try:
      createDir(dir)
    except CatchableError as e:
      return err("createDir(" & dir & "): " & e.msg)
  let jsonOut = snapshotToJson(snap).pretty() & "\n"
  writeFileAtomic(path, jsonOut)

proc readBaselineVkdFixed4*(path: string): string {.axiomDecision.} =
  ## Reads the vkdFixed4 value from an existing baseline.json. Empty on error/missing.
  if not fileExists(path):
    return ""
  try:
    let node = parseJson(readFile(path))
    result = node{"vkdFixed4"}.getStr("")
  except CatchableError:
    result = ""

type
  BaselineCheckOutcome* = object
    ## Zero-Theater Exit Contract (ADR-0010) decision for `ax baseline check`.
    ## code: 2 = empty vault, 1 = VKD degraded (actual regression), 0 = OK
    ## (maintained, improved, or reclassification migration).
    code*: int
    currentVkd*: string
    storedVkd*: string
    changeKind*: string        ## "RECLASSIFICATION" | "ACTUAL_REGRESSION" | "IMPROVEMENT" | "MAINTAINED"
    dualVerifiedCount*: int    ## genuinely dual-verified (certGreen + evidence-consistent) count now
    storedDualVerifiedCount*: int ## same count from stored baseline (−1 when unavailable)

proc readStoredDualVerifiedCount*(baselinePath: string): int {.axiomDecision.} =
  ## Reads the dual-verified count from a stored baseline.json `certificatesByTier`.
  ## Returns −1 when the field is absent or unreadable (backward-compat fallback).
  if not fileExists(baselinePath):
    return -1
  try:
    let node = parseJson(readFile(baselinePath))
    let byTier = node{"certificatesByTier"}
    if byTier.isNil or byTier.kind != JObject:
      return -1
    let dualArr = byTier{"dual-verified"}
    if dualArr.isNil or dualArr.kind != JArray:
      return -1
    result = dualArr.len
  except CatchableError:
    result = -1

proc countGenuinelyDualVerified*(certs: seq[JsonNode]): int {.raises: [].} =
  ## Counts certificates whose declared status is certGreen AND whose stored
  ## evidence is consistent with that claim (Z3 unsat ∧ Lean verified).
  ## This is the genuine dual-verified count — excludes mislabeled Z3-only
  ## certs that were incorrectly tagged certGreen before P0 reclassification.
  for cert in certs:
    let status = cert{"status"}.getStr("")
    if status == "certGreen" and statusConsistentWithEvidence(cert):
      inc result

proc baselineCheckOutcome*(baselinePath: string; certDir: string; scope: KernelScopeInfo): BaselineCheckOutcome {.axiomDecision.} =
  ## Stable vault scan → Exit 2/1/0 per ADR-0010 with reclassification awareness:
  ##   totalCount == 0 (empty vault)      → 2 (ERR_EMPTY_VAULT)
  ##   VKD_current < VKD_baseline AND genuinely-dual count also decreased
  ##     → 1 (ERR_BASELINE_DEGRADED, ACTUAL_REGRESSION)
  ##   VKD_current < VKD_baseline but genuinely-dual count preserved
  ##     → 0 (RECLASSIFICATION; P0 migration of mislabeled certGreen → certZ3Candidate)
  ##   VKD_current >= VKD_baseline        → 0 (OK; IMPROVEMENT or MAINTAINED)
  ##
  ## Monotonic threshold comparison — never raw string equality. vkdFixed4 is
  ## float-parsed via safeParseFloat before the >= comparison. Empty kernel scope
  ## (degraded/missing verification_scope.lock) is fail-closed, never fail-open (§0.9).
  let current = computeBaselineSnapshot(certDir, scope)
  let currentCerts = readStableVaultCerts(certDir)
  result.currentVkd = current.vkdFixed4
  result.storedVkd = readBaselineVkdFixed4(baselinePath)
  result.dualVerifiedCount = countGenuinelyDualVerified(currentCerts)
  result.storedDualVerifiedCount = readStoredDualVerifiedCount(baselinePath)

  if current.totalFunctions == 0:
    result.code = ErrEmptyVaultExit
    result.changeKind = "MAINTAINED"
    return
  if result.storedVkd.len == 0:
    result.code = ErrBaselineDegradedExit
    result.changeKind = "IMPROVEMENT"
    return
  let storedF = safeParseFloat(result.storedVkd)
  let currentF = safeParseFloat(result.currentVkd)
  if storedF.isErr or currentF.isErr:
    result.code = ErrBaselineDegradedExit
    result.changeKind = "IMPROVEMENT"
    return

  let cur = currentF.get
  let sto = storedF.get

  if cur >= sto:
    result.code = OkBaselineExit
    result.changeKind = if cur > sto: "IMPROVEMENT" else: "MAINTAINED"
    return

  # cur < sto — VKD headline dropped; classify as reclassification or regression
  let storedDual = result.storedDualVerifiedCount
  let currentDual = result.dualVerifiedCount

  if storedDual >= 0 and currentDual >= storedDual:
    # Genuinely dual-verified count did not decrease → reclassification migration
    result.code = OkBaselineExit
    result.changeKind = "RECLASSIFICATION"
  elif storedDual < 0 and currentDual == 0:
    # Legacy baseline (no dual count) and current has 0 genuinely dual → migration
    result.code = OkBaselineExit
    result.changeKind = "RECLASSIFICATION"
  else:
    # Genuinely dual-verified count decreased → real regression
    result.code = ErrBaselineDegradedExit
    result.changeKind = "ACTUAL_REGRESSION"

proc baselineCheckExitCode*(baselinePath: string; certDir: string; scope: KernelScopeInfo): int {.axiomDecision.} =
  ## Convenience wrapper — Exit code only (2/1/0).
  result = baselineCheckOutcome(baselinePath, certDir, scope).code

proc checkBaselineIntegrity*(baselinePath: string; certDir: string; scope: KernelScopeInfo): bool {.axiomDecision.} =
  ## Backward-compatible wrapper. Integrity holds iff the exit contract is OK (0).
  ## Fail-closed: an empty vault now yields false, never true (§0.9).
  result = baselineCheckExitCode(baselinePath, certDir, scope) == OkBaselineExit

{.pop.}
