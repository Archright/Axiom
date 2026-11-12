import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
# axiomIoBoundary

## VerifiedSet Hydration — build a bitset of already-verified nodes from the
## proof vault, with a v1→v2 migration bridge for legacy certificates that
## lack a per-function sourceHash.

import std/json
import std/os
import std/options
import std/sets
import std/tables
import core/json/json_utils
import core/proof/source_fingerprint
import core/sorter/sorter_core
import core/topology/symbol_interning
import core/topology/topology_engine
import core/topology/verified_set
import core/results
import core/utils/io_utils
import core/axiom_pragmas
import core/types/certificate_types
import core/types/verification_tier
import core/proof/proof_integrity   # KernelScopeInfo, symbolInKernelScope
import core/trusted/authoritative_hydration

func isVerifiedCertificateStatus(status: string): bool {.inline.} =
  status == "certGreen" or status == "certVerifiedAxiom" or
  status == "certLeanVerified" or status == "certDualVerified"

proc moduleContentForHydration(
  modulePath: string;
  contentResolver: ModuleContentResolver
): string {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  let cached = contentResolver(modulePath)
  if cached.isSome:
    return cached.get()
  let diskOpt = readFileOpt(modulePath)
  if diskOpt.isOk:
    return diskOpt.get()
  ""

proc currentSourceFingerprintForNode(
  analysis: TopologyAnalysis;
  modulePath: string;
  functionName: string;
  contentResolver: ModuleContentResolver
): string {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  ## Certificates store the source hash of the whole module (the ``sourceCode``
  ## passed to the verifier), so hydration must compare against the same scope.
  let content = moduleContentForHydration(modulePath, contentResolver)
  if content.len == 0:
    return ""
  computeStableSourceFingerprint(content)

proc certSourceMatchesCurrent(
  node: JsonNode;
  analysis: TopologyAnalysis;
  contentResolver: ModuleContentResolver
): bool {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  ## I-D: a certificate is a valid candidate reuse only when its recorded
  ## sourceHash matches the CURRENT source fingerprint. Missing sourceHash or
  ## mismatched/missing current fingerprint → false (cache miss, fail-closed).
  let sourceHash = node.getOrDefault("sourceHash").getStr("")
  if sourceHash.len == 0:
    return false
  if analysis.state.nodes.len == 0:
    return true  # empty analysis: caller has no current-source basis — skip validation
  let modulePath = node.getOrDefault("modulePath").getStr("")
  let functionName = node.getOrDefault("functionName").getStr("")
  let currentHash = currentSourceFingerprintForNode(
    analysis, modulePath, functionName, contentResolver)
  currentHash.len > 0 and currentHash == sourceHash


proc certPassesStrictnessMode(
  node: JsonNode;
  config: HydrationConfig
): bool {.raises: [].} =
  ## Strictness-mode soundness checks (uf-abstract TCB, k-induction base case).
  case config.soundnessMode
  of smLax:
    true
  of smSoundnessGuard:
    let tier = node.getOrDefault("verificationTier").getStr("")
    if tier == "uf-abstract":
      let tcb = node.getOrDefault("tcb")
      let hasPost = not tcb.isNil and tcb.kind == JObject and tcb.hasKey("uninterpretedFns")
      hasPost
    else:
      true
  of smFullStrict:
    let tier = node.getOrDefault("verificationTier").getStr("")
    if tier == "uf-abstract":
      let tcb = node.getOrDefault("tcb")
      let hasPost = not tcb.isNil and tcb.kind == JObject and tcb.hasKey("uninterpretedFns")
      if not hasPost:
        return false
    if tier == "k-induction":
      let baseUnsat = node.getOrDefault("solverMeta").getOrDefault("baseCaseUnsat").getBool(true)
      if not baseUnsat:
        return false
    true

proc certificateAccepted(
  node: JsonNode;
  analysis: TopologyAnalysis;
  contentResolver: ModuleContentResolver;
  config: HydrationConfig = defaultHydrationConfig
): bool {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  let modulePath = node.getOrDefault("modulePath").getStr("")
  let functionName = node.getOrDefault("functionName").getStr("")
  if modulePath.len == 0 or functionName.len == 0:
    return false

  let status = node.getOrDefault("status").getStr("")
  if not isVerifiedCertificateStatus(status):
    return false

  let solverMeta = node.getOrDefault("solverMeta")
  let leanVerified = (
    not solverMeta.isNil and
    solverMeta.kind == JObject and
    solverMeta.getOrDefault("leanCompilerVerified").getBool(false)
  )
  # P0 invariant: certGreen without dual Z3∧Lean evidence must be rejected.
  if not statusConsistentWithEvidence(node):
    return false

  # Soundness Gatekeeper: Lean-only verification without vacuityProven is NOT sufficient.
  # leanCompilerVerified only means compilation success, not proof correctness.
  # Exception: certificates with verificationTier were verified by IR pipeline
  # which has built-in soundness checks (tautology filter, mutation test).
  let vacuityProven = (
    not solverMeta.isNil and
    solverMeta.kind == JObject and
    solverMeta.getOrDefault("vacuityProven").getBool(false)
  )
  let verificationTier = node.getOrDefault("verificationTier").getStr("")
  let z3outPath = node.getOrDefault("z3outPath").getStr("")
  let smtlib2 = node.getOrDefault("smtlib2").getStr("")
  let z3Unsat = smtlib2.len > 0 and z3outPath.len > 0
  # Accept if: Z3 UNSAT OR (Lean verified AND non-vacuous) OR (Lean verified AND IR pipeline)
  if leanVerified and not vacuityProven and not z3Unsat and verificationTier.len == 0:
    return false

  # Strictness-mode checks
  if not certPassesStrictnessMode(node, config):
    return false

  # Phase 2: VC Hash comparison (preferred — source-invariant)
  # vcHash is computed from Z3-canonicalized VC expressions, not source text.
  # This is stable across formatting changes, variable renaming, etc.
  let vcHash = node.getOrDefault("vcHash").getStr("")
  if vcHash.len > 0:
    # v2+ certificate. I-D: CacheHit = ValidCertificate(CurrentExecutionIdentity).
    # Validate against the CURRENT source fingerprint before accepting — a stale
    # cert whose source no longer matches must be a cache MISS, not a verified hit.
    # (vcHash Z3 validation stays deferred to verification time.)
    return certSourceMatchesCurrent(node, analysis, contentResolver)

  # Legacy: sourceHash comparison (v1 certificates)
  # Skip for IR pipeline verified certificates — they have their own soundness checks.
  let sourceHash = node.getOrDefault("sourceHash").getStr("")
  if sourceHash.len > 0 and verificationTier.len == 0:
    return certSourceMatchesCurrent(node, analysis, contentResolver)

  let schemaVersion = node.getOrDefault("schemaVersion").getStr("")
  # P0-a: migration bridge removed — legacy v1 certificates without a
  # per-function sourceHash are NO LONGER force-included into the verified set.
  # They remain readable evidence, but are excluded from the trust input.
  return false

proc hydrateVerifiedSetFromProofVault*(
  vaultDir: string;
  internPool: InternPoolSnapshot;
  analysis: TopologyAnalysis;
  contentResolver: ModuleContentResolver;
  scope: KernelScopeInfo;              # NEW: SSOT kernel scope for VKD numerator alignment
  claimsDir: string = ""               # Phase-5b: claim-authoritative source. When non-empty
                                        # and claims exist, this path wins over the legacy
                                        # certificate scan. Claim→ClaimStore→VerifiedSet is
                                        # authoritative; Certificate→VerifiedSet is the
                                        # deprecated fallback being phased out.
): VerifiedSet {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  ## Scan ``vaultDir/*.json`` and populate a VerifiedSet of nodes whose
  ## certificates are valid. Legacy v1 certificates without sourceHash are
  ## accepted through a migration bridge.
  ##
  ## When ``claimsDir`` is non-empty, the claim-authoritative path is tried
  ## first: if any PROVED claims are found, the certificate scan is skipped
  ## entirely and the claim-derived VerifiedSet is returned immediately.
  ## This makes the Claim the authoritative source of "verified" status.
  ## The certificate-based path remains as the fallback when no claims exist
  ## (backward-compatible default).
  ##
  ## Certificates for node IDs not present in the current source tree are
  ## silently ignored (stale historical artifacts).
  result = initVerifiedSet(analysis.verificationQueue.len)

  # Claim-authoritative branch (Phase-5b): if claims exist, they win.
  if claimsDir.len > 0:
    let (claimStore, claimVerified) = hydrateVerifiedSetFromClaims(claimsDir)
    if claimVerified.len > 0:
      for subjectId in claimVerified:
        let nodeIdOpt = nodeIdForSorter(internPool, sorterNodeId(subjectId))
        if nodeIdOpt.isSome:
          result.incl(nodeIdOpt.get())
      return result

  if vaultDir.len == 0:
    return result

  let pattern = joinPath(vaultDir, "*.json")
  var paths: seq[string] = @[]
  try:
    for path in walkPattern(pattern):
      paths.add(path)
  except CatchableError:
    return result

  for path in paths:
    let nodeOpt = readJsonFile(path)
    if nodeOpt.isNone:
      continue
    let node = nodeOpt.get()
    if node.kind != JObject:
      continue
    if not certificateAccepted(node, analysis, contentResolver):
      continue

    # SSOT kernel filter: only include certificates whose symbol is in the
    # authoritative kernel scope (verification_scope.lock). This ensures the
    # VKD numerator (verifiedSet.popcount()) is a subset of the kernel
    # denominator (|Kernel|=44), preventing inflation from non-kernel certs.
    # Uses Set-Membership against the SSOT, NOT the unreliable `kernel`
    # JSON field (which is absent on legitimate kernel certs like normalizeMaxWorkers).
    if scope.kernelSymbols.len > 0 and not symbolInKernelScope(node, scope):
      continue

    let modulePath = node.getOrDefault("modulePath").getStr("")
    let functionName = node.getOrDefault("functionName").getStr("")
    let nodeIdOpt = nodeIdForSorter(internPool, sorterNodeId(modulePath & "::" & functionName))
    if nodeIdOpt.isNone:
      continue
    result.incl(nodeIdOpt.get())

proc vaultCertAxiom(
  node: JsonNode;
  analysis: TopologyAnalysis;
  contentResolver: ModuleContentResolver
): Option[tuple[key: string, smtlib2: string]] {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  ## Validate a single vault certificate as a reusable axiom: it must be a
  ## verified status, evidence-consistent, source-matched (I-D), lean-verified,
  ## and carry an smtlib2 formula. Returns none on any failure (skip, fail-closed).
  if node.kind != JObject:
    return none(tuple[key: string, smtlib2: string])
  let modulePath = node.getOrDefault("modulePath").getStr("")
  let functionName = node.getOrDefault("functionName").getStr("")
  if modulePath.len == 0 or functionName.len == 0:
    return none(tuple[key: string, smtlib2: string])
  let status = node.getOrDefault("status").getStr("")
  if not isVerifiedCertificateStatus(status):
    return none(tuple[key: string, smtlib2: string])
  if not statusConsistentWithEvidence(node):
    return none(tuple[key: string, smtlib2: string])
  # I-D: cache miss unless the cert's sourceHash matches the current source.
  if not certSourceMatchesCurrent(node, analysis, contentResolver):
    return none(tuple[key: string, smtlib2: string])
  let solverMeta = node.getOrDefault("solverMeta")
  let leanVerified = (
    not solverMeta.isNil and
    solverMeta.kind == JObject and
    solverMeta.getOrDefault("leanCompilerVerified").getBool(false)
  )
  if not leanVerified:
    return none(tuple[key: string, smtlib2: string])
  let smtlib2 = node.getOrDefault("smtlib2").getStr("")
  if smtlib2.len == 0:
    return none(tuple[key: string, smtlib2: string])
  some((key: modulePath & "::" & functionName, smtlib2: smtlib2))

proc loadVerifiedAxiomsFromProofVault*(
  vaultDir: string;
  contentResolver: ModuleContentResolver;
  analysis: TopologyAnalysis = TopologyAnalysis()
): Table[string, AxiomFormula] {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  ## Scan ``vaultDir/*.json`` and build a node-id → axiom table for verified
  ## certificates that contain an ``smtlib2`` field. This lets the engine
  ## pre-promote verified dependencies into the SorterState vault.
  ##
  ## I-D / I-3: entries are validated against the CURRENT source fingerprint
  ## before promotion — a stale certificate whose sourceHash does not match the
  ## present source is a cache MISS (skipped), never a verified hit.
  result = initTable[string, AxiomFormula]()
  if vaultDir.len == 0:
    return result

  let pattern = joinPath(vaultDir, "*.json")
  var paths: seq[string] = @[]
  try:
    for path in walkPattern(pattern):
      paths.add(path)
  except CatchableError:
    return result

  for path in paths:
    let nodeOpt = readJsonFile(path)
    if nodeOpt.isNone:
      continue
    let axiomOpt = vaultCertAxiom(nodeOpt.get(), analysis, contentResolver)
    if axiomOpt.isSome:
      result[axiomOpt.get().key] = axiomFormula(axiomOpt.get().smtlib2)

{.pop.}

