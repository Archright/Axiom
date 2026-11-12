-- GateData.lean — SSOT definitions for the Axiom gate topology.
-- Ported from src/generated/axiom_topology.nim and src/gate/gate_manifest.json.
-- Contains: GateId enum, string table, MPHF displacement table,
-- dependency edges, FNV-1a hash, and MPHF lookup.

set_option autoImplicit false

-- ============================================================================
-- §1  Gate Count
-- ============================================================================

def AxiomTotalGates : Nat := 55

-- ============================================================================
-- §2  Gate Identifier Enum (55 gates, alphabetical by manifest ID)
-- ============================================================================

inductive GateId where
  | architectureConfigGate
  | architectureGuard
  | assetHygieneGate
  | binaryArtifactGate
  | binaryFreshnessGate
  | castNosideeffectDocGate
  | cliBuild
  | contextSizeGuard
  | context7EvidenceGate
  | coreInvariantGate
  | dagEnforcementGate
  | debtBlocker
  | debtReductionGate
  | debtScanGate
  | delegationEnforcer
  | dependencyRulesGate
  | docCompletenessGate
  | documentationFirstGate
  | drnim
  | externalCliSmoke
  | externalCliSmokeHard
  | forwardingStubCycleGate
  | gateSelfCheck
  | gatewayTest
  | hermeticTestGate
  | hotspotEnforcement
  | hotspotGate
  | hotspotRatchetGate
  | importEncapsulationGate
  | integrityTest
  | integrityWorkflow
  | intentGate
  | languageBanGate
  | loggingPolicyGate
  | magicNumberSniffer
  | manifestConsistencyGate
  | memoryPolicyGate
  | monotonicWhitelistGate
  | nimCheck
  | nimtry
  | nimtryGate
  | policyValidator
  | procedureGate
  | proofUniverseLockGate
  | qualityAuditGate
  | qualityGateMarker
  | qualityGateRunner
  | sentinel
  | specBindingGate
  | specPresenceGate
  | testCoverageGate
  | topologyPolicyGate
  | unstagedGuard
  | validateArchitecture
  | verificationAuditor
  deriving DecidableEq, Repr, Inhabited

-- ============================================================================
-- §3  Gate String Table (index matches GateId ordinal)
-- ============================================================================

def gateIdStrings : Array String := #[
  "architecture-config-gate",
  "architecture-guard",
  "asset-hygiene-gate",
  "binary-artifact-gate",
  "binary-freshness-gate",
  "cast-nosideeffect-doc-gate",
  "cli-build",
  "context-size-guard",
  "context7-evidence-gate",
  "core-invariant-gate",
  "dag-enforcement-gate",
  "debt-blocker",
  "debt-reduction-gate",
  "debt-scan-gate",
  "delegation-enforcer",
  "dependency-rules-gate",
  "doc-completeness-gate",
  "documentation-first-gate",
  "drnim",
  "external-cli-smoke",
  "external-cli-smoke-hard",
  "forwarding-stub-cycle-gate",
  "gate-self-check",
  "gateway-test",
  "hermetic-test-gate",
  "hotspot-enforcement",
  "hotspot-gate",
  "hotspot-ratchet-gate",
  "import-encapsulation-gate",
  "integrity-test",
  "integrity-workflow",
  "intent-gate",
  "language-ban-gate",
  "logging-policy-gate",
  "magic-number-sniffer",
  "manifest-consistency-gate",
  "memory-policy-gate",
  "monotonic-whitelist-gate",
  "nim-check",
  "nimtry",
  "nimtry-gate",
  "policy-validator",
  "procedure-gate",
  "proof-universe-lock-gate",
  "quality-audit-gate",
  "quality-gate-marker",
  "quality-gate-runner",
  "sentinel",
  "spec-binding-gate",
  "spec-presence-gate",
  "test-coverage-gate",
  "topology-policy-gate",
  "unstaged-guard",
  "validate-architecture",
  "verification-auditor"
]

-- ============================================================================
-- §4  MPHF Displacement Table (FNV-1a + displacement, 55-entry permutation)
-- ============================================================================

def displacement : Array Nat := #[
  47, 48, 50, 25,  6, 42,  1,  2,  3, 22, 23,  8, 34, 18, 35, 51,
  52, 53,  4, 21, 28, 54,  7, 43, 49,  0, 11, 26,  9, 33, 38,
  45, 32, 14, 15, 12, 19, 20, 36, 16, 37, 30, 40, 27, 31, 41, 44,
  46,  5, 13, 17, 10, 24, 39, 29
]

-- ============================================================================
-- §5  Dependency Edges (from gate_manifest.json "after" fields)
-- ============================================================================

/-- Each edge (a, b) means gate `a` depends on gate `b` (a must run after b). -/
def edges : List (GateId × GateId) := [
  (.binaryFreshnessGate,     .cliBuild),
  (.debtReductionGate,       .nimtry),
  (.debtReductionGate,       .dagEnforcementGate),
  (.externalCliSmoke,        .cliBuild),
  (.externalCliSmokeHard,    .cliBuild),
  (.gatewayTest,             .nimCheck),
  (.hotspotEnforcement,      .hotspotGate),
  (.hotspotRatchetGate,      .hotspotGate),
  (.integrityTest,           .cliBuild),
  (.monotonicWhitelistGate,  .nimtry),
  (.policyValidator,         .nimtry),
  (.proofUniverseLockGate,   .nimCheck),
  (.verificationAuditor,     .nimCheck)
]

-- ============================================================================
-- §6  FNV-1a 32-bit Hash (port of axiom_topology.nim fnv1a32)
-- ============================================================================

/-- FNV-1a 32-bit hash — pure, deterministic. Matches the Nim implementation.
    Uses ByteArray.foldl to avoid manual recursion. -/
def fnv1a32 (input : String) : UInt32 :=
  input.toUTF8.foldl (init := 0x811c9dc5) fun h b =>
    (h ^^^ UInt32.ofNat b.toNat) * 0x01000193

-- ============================================================================
-- §7  MPHF Lookup (port of axiom_topology.nim mphfLookup)
-- ============================================================================

/-- O(n) amortized gate lookup via displacement table.
    Returns gate index (0..54) or -1 if not found. -/
def mphfLookup (input : String) : Int :=
  let h := fnv1a32 input
  let bucket0 := h.toNat % AxiomTotalGates
  Id.run do
    let mut bucket := bucket0
    let mut result := -1
    for _ in [:AxiomTotalGates] do
      let idx := displacement[bucket]!
      if gateIdStrings[idx]! == input then
        result := (idx : Int)
      bucket := (bucket + 1) % AxiomTotalGates
    pure result

-- ============================================================================
-- §8  Gate ID List (for iteration in proofs)
-- ============================================================================

def gateIdList : List String := gateIdStrings.toList

-- ============================================================================
-- §9  Dependency Relation
-- ============================================================================

/-- Gate `a` directly depends on gate `b`. -/
def dependsOn (a b : GateId) : Prop := (a, b) ∈ edges

-- ============================================================================
-- §10  Topological Rank (for acyclicity proof)
-- ============================================================================

/-- Rank function for topological ordering.
    Gates with no outgoing edges get rank 0; gates with outgoing edges get rank 1.
    This is a valid topological order for our DAG. -/
def rank : GateId → Nat
  | .cliBuild              => 0
  | .nimCheck              => 0
  | .nimtry                => 0
  | .hotspotGate           => 0
  | .dagEnforcementGate    => 0
  | _                      => 1

-- ============================================================================
-- §11  Cached Computation for native_decide
-- ============================================================================

/-- Check that all edges respect the topological rank ordering. -/
def edgesRespectRank : Bool :=
  edges.all fun (a, b) => rank a > rank b

/-- Compute all MPHF indices for the 55 gate strings. -/
def mphfIndices : Array Int :=
  gateIdStrings.map mphfLookup

/-- Check that all MPHF indices are in [0, 54]. -/
def mphfIndicesValid : Bool :=
  mphfIndices.all fun i => i ≥ 0 && i < 55

/-- Check that all MPHF indices are distinct. -/
def mphfIndicesDistinct : Bool :=
  mphfIndices.toList.Nodup
