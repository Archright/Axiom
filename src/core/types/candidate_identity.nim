import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/[json, options, sequtils, strutils]
import core/crypto/hash_kernel
import core/results

## Candidate Identity — 3-layer logical identity + materialized candidate (ADR-0020).
##
## Defines the pure domain types used throughout the speculative candidate
## graph. All digests follow the hash-of-parts convention from identity.nim:212-217
## (sha256Hex(a & "|" & b & "|" & c)). Epoch and depth are NEVER content identity.
##
## Layers:
##   CandidateStateIdentity   — WHAT repository state (treeDigest only)
##   CandidateProvenance      — WHERE FROM (baseCommit, orderedChanges, repoIdentity)
##   VerificationContextIdentity — UNDER WHAT CONTRACT (policy/toolchain/contract digests)
##   CandidateEvidenceDigest  — H(state | provenance | context) combined identity
##   MaterializedCandidate    — provider's claim (NOT trusted until verified)
##   MaterializationRecord    — independent re-derivation result (declared == resolved)

# ---------------------------------------------------------------------------
# ChangeDescriptor — identifies one queued change in the ordered prefix chain
# ---------------------------------------------------------------------------

type ChangeDescriptor* = object
  ## A single queued change. Minimal: identifies the PR and its head commit.
  prNumber*: int
  headSha*: string

func changeDescriptorHash*(cd: ChangeDescriptor): string {.raises: [].} =
  ## Deterministic hash of a ChangeDescriptor for ordering/dedup.
  sha256Hex($cd.prNumber & "|" & cd.headSha)

# ---------------------------------------------------------------------------
# CandidateStateIdentity — WHAT repository state
# ---------------------------------------------------------------------------

type CandidateStateIdentity* = object
  ## The WHAT layer: identifies a specific repository tree state.
  treeDigest*: string
  identityDigest*: string

func candidateStateIdentity*(treeDigest: string): CandidateStateIdentity {.raises: [].} =
  ## Derive CandidateStateIdentity from a tree digest. identityDigest is
  ## the sha256 of the treeDigest itself, providing a content-addressed
  ## identity stable across queue epochs and depth changes.
  CandidateStateIdentity(
    treeDigest: treeDigest,
    identityDigest: sha256Hex(treeDigest))

# ---------------------------------------------------------------------------
# CandidateProvenance — WHERE FROM
# ---------------------------------------------------------------------------

type CandidateProvenance* = object
  ## The WHERE FROM layer: describes how the candidate was constructed.
  baseCommit*: string
  orderedChanges*: seq[ChangeDescriptor]
  repositoryIdentity*: string
  provenanceDigest*: string

func candidateProvenance*(
  baseCommit: string; orderedChanges: seq[ChangeDescriptor];
  repositoryIdentity: string
): CandidateProvenance {.raises: [].} =
  ## Derive CandidateProvenance from its components. provenanceDigest is
  ## sha256 of baseCommit | orderedChanges | repositoryIdentity.
  let changesStr = orderedChanges.mapIt($it.prNumber & "|" & it.headSha).join("|")
  CandidateProvenance(
    baseCommit: baseCommit,
    orderedChanges: orderedChanges,
    repositoryIdentity: repositoryIdentity,
    provenanceDigest: sha256Hex(baseCommit & "|" & changesStr & "|" & repositoryIdentity))

# ---------------------------------------------------------------------------
# VerificationContextIdentity — UNDER WHAT CONTRACT
# ---------------------------------------------------------------------------

type VerificationContextIdentity* = object
  ## The UNDER WHAT CONTRACT layer: describes the verification context.
  policyDigest*: string
  toolchainDigest*: string
  verificationContractDigest*: string
  contextDigest*: string

func verificationContextIdentity*(
  policyDigest, toolchainDigest, verificationContractDigest: string
): VerificationContextIdentity {.raises: [].} =
  ## Derive VerificationContextIdentity from its three digest components.
  ## contextDigest is sha256 of the three constituent digests joined by "|".
  let ctx = sha256Hex(
    policyDigest & "|" & toolchainDigest & "|" & verificationContractDigest)
  VerificationContextIdentity(
    policyDigest: policyDigest,
    toolchainDigest: toolchainDigest,
    verificationContractDigest: verificationContractDigest,
    contextDigest: ctx)

# ---------------------------------------------------------------------------
# CandidateEvidenceDigest — H(state | provenance | context)
# ---------------------------------------------------------------------------

type CandidateEvidenceDigest* = object
  ## Combined identity: hash-of-parts of the three identity layers.
  stateIdentity*: string
  provenanceDigest*: string
  contextDigest*: string
  digest*: string

func candidateEvidenceDigest*(
  stateIdentity, provenanceDigest, contextDigest: string
): CandidateEvidenceDigest {.raises: [].} =
  ## Derive CandidateEvidenceDigest from the three layer digests.
  ## Follows identity.nim:212-217 hash-of-parts convention.
  let digest = sha256Hex(
    stateIdentity & "|" & provenanceDigest & "|" & contextDigest)
  CandidateEvidenceDigest(
    stateIdentity: stateIdentity,
    provenanceDigest: provenanceDigest,
    contextDigest: contextDigest,
    digest: digest)

# ---------------------------------------------------------------------------
# MaterializedCandidate — provider's claim (NOT trusted until verified)
# ---------------------------------------------------------------------------

type MaterializedCandidate* = object
  ## The provider-built ref/commit — a CLAIM, not trust.
  ## Must be independently verified before use (declaredTreeDigest == resolvedTreeDigest).
  candidateRef*: string
  candidateCommit*: string
  declaredTreeDigest*: string
  provenance*: CandidateProvenance

# ---------------------------------------------------------------------------
# MaterializationRecord — independent re-derivation result
# ---------------------------------------------------------------------------

type MaterializationRecord* = object
  ## Result of an independent read-path verification of a materialization claim.
  candidateRef*: string
  declaredTreeDigest*: string
  resolvedTreeDigest*: string
  readPath*: string
  match*: bool

func materializationMatches*(rec: MaterializationRecord): bool {.raises: [].} =
  ## Return true when the declared tree digest matches the independently
  ## resolved tree digest. Referentially transparent — no I/O.
  rec.declaredTreeDigest == rec.resolvedTreeDigest

# ---------------------------------------------------------------------------
# JSON serialization for journal persistence
# ---------------------------------------------------------------------------

func toJson*(cd: ChangeDescriptor): JsonNode {.raises: [].} =
  %*{
    "prNumber": cd.prNumber,
    "headSha": cd.headSha}

func toJson*(csi: CandidateStateIdentity): JsonNode {.raises: [].} =
  %*{
    "treeDigest": csi.treeDigest,
    "identityDigest": csi.identityDigest}

func toJson*(cp: CandidateProvenance): JsonNode {.raises: [].} =
  %*{
    "baseCommit": cp.baseCommit,
    "orderedChanges": cp.orderedChanges.mapIt(it.toJson),
    "repositoryIdentity": cp.repositoryIdentity,
    "provenanceDigest": cp.provenanceDigest}

func toJson*(vci: VerificationContextIdentity): JsonNode {.raises: [].} =
  %*{
    "policyDigest": vci.policyDigest,
    "toolchainDigest": vci.toolchainDigest,
    "verificationContractDigest": vci.verificationContractDigest,
    "contextDigest": vci.contextDigest}

func toJson*(ced: CandidateEvidenceDigest): JsonNode {.raises: [].} =
  %*{
    "stateIdentity": ced.stateIdentity,
    "provenanceDigest": ced.provenanceDigest,
    "contextDigest": ced.contextDigest,
    "digest": ced.digest}

func toJson*(mc: MaterializedCandidate): JsonNode {.raises: [].} =
  %*{
    "candidateRef": mc.candidateRef,
    "candidateCommit": mc.candidateCommit,
    "declaredTreeDigest": mc.declaredTreeDigest,
    "provenance": mc.provenance.toJson}

func toJson*(mr: MaterializationRecord): JsonNode {.raises: [].} =
  %*{
    "candidateRef": mr.candidateRef,
    "declaredTreeDigest": mr.declaredTreeDigest,
    "resolvedTreeDigest": mr.resolvedTreeDigest,
    "readPath": mr.readPath,
    "match": mr.match}

func changeDescriptorFromJson*(node: JsonNode): Result[ChangeDescriptor, string] {.raises: [].} =
  if node.kind != JObject:
    return err("ChangeDescriptor: expected object")
  ok(ChangeDescriptor(
    prNumber: node{"prNumber"}.getInt(),
    headSha: node{"headSha"}.getStr()))

func candidateStateIdentityFromJson*(node: JsonNode): Result[CandidateStateIdentity, string] {.raises: [].} =
  if node.kind != JObject:
    return err("CandidateStateIdentity: expected object")
  ok(CandidateStateIdentity(
    treeDigest: node{"treeDigest"}.getStr(),
    identityDigest: node{"identityDigest"}.getStr()))

func candidateProvenanceFromJson*(node: JsonNode): Result[CandidateProvenance, string] {.raises: [].} =
  if node.kind != JObject:
    return err("CandidateProvenance: expected object")
  let changes = node{"orderedChanges"}.getElems()
  var ordered: seq[ChangeDescriptor] = @[]
  for c in changes:
    let cd = changeDescriptorFromJson(c)
    if cd.isErr: return err("CandidateProvenance.change: " & cd.error)
    ordered.add(cd.value)
  ok(CandidateProvenance(
    baseCommit: node{"baseCommit"}.getStr(),
    orderedChanges: ordered,
    repositoryIdentity: node{"repositoryIdentity"}.getStr(),
    provenanceDigest: node{"provenanceDigest"}.getStr()))

func verificationContextIdentityFromJson*(node: JsonNode): Result[VerificationContextIdentity, string] {.raises: [].} =
  if node.kind != JObject:
    return err("VerificationContextIdentity: expected object")
  ok(VerificationContextIdentity(
    policyDigest: node{"policyDigest"}.getStr(),
    toolchainDigest: node{"toolchainDigest"}.getStr(),
    verificationContractDigest: node{"verificationContractDigest"}.getStr(),
    contextDigest: node{"contextDigest"}.getStr()))

func candidateEvidenceDigestFromJson*(node: JsonNode): Result[CandidateEvidenceDigest, string] {.raises: [].} =
  if node.kind != JObject:
    return err("CandidateEvidenceDigest: expected object")
  ok(CandidateEvidenceDigest(
    stateIdentity: node{"stateIdentity"}.getStr(),
    provenanceDigest: node{"provenanceDigest"}.getStr(),
    contextDigest: node{"contextDigest"}.getStr(),
    digest: node{"digest"}.getStr()))

func materializedCandidateFromJson*(node: JsonNode): Result[MaterializedCandidate, string] {.raises: [].} =
  if node.kind != JObject:
    return err("MaterializedCandidate: expected object")
  let prov = node{"provenance"}
  let cp = candidateProvenanceFromJson(prov)
  if cp.isErr: return err("MaterializedCandidate.provenance: " & cp.error)
  ok(MaterializedCandidate(
    candidateRef: node{"candidateRef"}.getStr(),
    candidateCommit: node{"candidateCommit"}.getStr(),
    declaredTreeDigest: node{"declaredTreeDigest"}.getStr(),
    provenance: cp.value))

func materializationRecordFromJson*(node: JsonNode): Result[MaterializationRecord, string] {.raises: [].} =
  if node.kind != JObject:
    return err("MaterializationRecord: expected object")
  ok(MaterializationRecord(
    candidateRef: node{"candidateRef"}.getStr(),
    declaredTreeDigest: node{"declaredTreeDigest"}.getStr(),
    resolvedTreeDigest: node{"resolvedTreeDigest"}.getStr(),
    readPath: node{"readPath"}.getStr(),
    match: node{"match"}.getBool()))

{.pop.}
