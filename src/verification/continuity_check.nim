import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Continuity predicate v2 — Model B (certification-continuity, ratified
## Verdict B 2026-09-10). Pure core + IO wrapper. Fail-visible.
## Journal NEVER consulted (forensic record only).
##
## PASS ⟺ ALL of:
##  1. cert kind == subject-continuity, Ed25519 attestation verifies
##     (certificate identity re-derivation stays with the certificate
##     writer/verifier chain; the continuity module re-verifies the signature)
##  2. main head is a 2-parent merge commit (shape evidence provided by the
##     caller: parent1/parent2 resolved via `git rev-parse <main>^1` / `^2`;
##     a non-merge commit cannot resolve ^2 → ccMismatch)
##  3. parent1 == cert.baseSha   (exact equality — no descendant-base semantics)
##  4. parent2 == cert.headSha
##  5. sha256Hex(tree OID of parent2) == cert.headTreeDigest
##  6. policyDigest(current config/policy/merge_admission.json) == cert.policyDigest
##  7. scopeDigest(current data/verification_scope.lock) == cert.scopeDigest
##
## The module NEVER executes git itself: the caller (actuator, workflow job)
## resolves main/parent/tree OIDs and passes them in as strings, so the pure
## predicate stays free of I/O beyond the two tracked digest files.

import std/[json, strutils, os]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import infrastructure/certificate_attestation
import verification/certificate_identity

axiomIoBoundary()

type
  ## Continuity verdict — the single outcome of one post-merge check.
  ContinuityVerdict* = enum
    ccPassed      ## main is the certified native merge commit (all stages green)
    ccMismatch    ## main shape/parents/tree disagree with the certificate
    ccNoCert      ## no certificate to check against — fail-closed (missing ≠ valid empty)
    ccError       ## certificate invalid/tampered or check inputs malformed — fail-closed

  ## Journal-free continuity check detail — the verdict PLUS per-stage
  ## booleans so the journal record keeps failure reasons machine-
  ## distinguishable (mergeShapeOk/ancestryOk/treeOk/policyOk/scopeOk —
  ## the record is audit/forensic only and never feeds the verdict).
  ContinuityCheckDetail* = object
    verdict*: ContinuityVerdict
    mergeShapeOk*: bool
    ancestryOk*: bool
    treeOk*: bool
    policyOk*: bool
    scopeOk*: bool

func isOid40(s: string): bool {.raises: [].} =
  ## Lowercase 40-hex git object id grammar (duplicated from the object-id
  ## grammar used at the admission boundary so the pure predicate never
  ## depends on an I/O module).
  if s.len != 40:
    return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}:
      return false
  true

type
  ## Pure input surface — everything continuity reads about the observed
  ## main state, resolved by the caller at the I/O boundary.
  MainShape* = object
    mainSha*: string        ## observed main tip (40-hex)
    parent1*: string        ## `git rev-parse <main>^1` ("") when unresolvable
    parent2*: string        ## `git rev-parse <main>^2` ("") when unresolvable —
                            ## "" ⇒ NOT a 2-parent merge commit
    headTreeOid*: string    ## `git rev-parse <parent2>^{tree}` (40-hex, "" when unresolvable)

func verifyContinuity*(observed: MainShape; cert: JsonNode): ContinuityVerdict {.raises: [].} =
  ## Pure Model B continuity predicate (stages 1-5 of the spec; stages 6-7
  ## are file-digest stages evaluated by the IO wrapper into Detail fields).
  ##
  ##   1. no certificate → ccNoCert (fail-closed — missing is never "clean").
  ##  1a. the certificate itself must be valid: subject-continuity kind and
  ##      the Ed25519 attestation block MUST verify (tampered → ccError).
  ##   2. main must be a 2-parent merge commit (parent1 and parent2 both
  ##      resolvable 40-hex OIDs — parent2 == "" means main is not a merge
  ##      commit → ccMismatch, never an error: the shape is the violation).
  ##   3. parent1 == cert.baseSha (exact).
  ##   4. parent2 == cert.headSha.
  ##   5. sha256Hex(tree OID of parent2) == cert.headTreeDigest (tree-content
  ##      binding of the certified head, preserved across the native merge).
  if cert.isNil or cert.kind != JObject:
    return ccNoCert
  if cert.getOrDefault("kind").getStr("") != "subject-continuity":
    return ccError
  # Stage 1 — certificate validity (Ed25519 attestation must verify).
  if not verifyCertificateAttestation(cert).isOk:
    return ccError
  # Stage 2 — merge-commit shape.
  if not isOid40(observed.mainSha):
    return ccError
  if not isOid40(observed.parent1) or not isOid40(observed.parent2):
    return ccMismatch
  # Stages 3-4 — certified-input ancestry (exact equality).
  let certBaseSha = cert.getOrDefault("baseSha").getStr("")
  let certHeadSha = cert.getOrDefault("headSha").getStr("")
  if not isOid40(certBaseSha) or not isOid40(certHeadSha):
    return ccError
  if observed.parent1 != certBaseSha or observed.parent2 != certHeadSha:
    return ccMismatch
  # Stage 5 — certified head tree content binding.
  let certTreeDigest = cert.getOrDefault("headTreeDigest").getStr("")
  if certTreeDigest.len != 64:
    return ccError
  if sha256Hex(observed.headTreeOid) != certTreeDigest:
    return ccMismatch
  ccPassed

proc fileSha256Hex*(path: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256 over the CURRENT file bytes ("" = unreadable/absent → caller fails
  ## closed). Convention: sha256 of the current tracked policy/scope file;
  ## duplicated here so the journal-free continuity module never depends on
  ## the CLI layer.
  if not fileExists(path):
    return ""
  try:
    sha256Hex(readFile(path))
  except CatchableError:
    ""

func certHeadTreeDigest(cert: JsonNode): string {.raises: [].} =
  cert.getOrDefault("headTreeDigest").getStr("")

proc verifyContinuityCertDetailed*(observed: MainShape; certPath: string): ContinuityCheckDetail
    {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The journal-free continuity predicate WITH per-stage detail
  ## (mergeShapeOk/ancestryOk/treeOk/policyOk/scopeOk). All fail-closed, in
  ## spec order; a mismatch at any stage short-circuits with the verdict and
  ## the booleans evaluated so far.
  if not fileExists(certPath):
    return ContinuityCheckDetail(verdict: ccNoCert)
  var node: JsonNode
  try:
    node = parseJson(readFile(certPath))
  except CatchableError:
    return ContinuityCheckDetail(verdict: ccError)
  if node.isNil or node.kind != JObject:
    return ContinuityCheckDetail(verdict: ccError)
  # Stage 1 (+ 1a) — kind + Ed25519 attestation.
  if node.getOrDefault("kind").getStr("") != "subject-continuity":
    return ContinuityCheckDetail(verdict: ccError)
  if not verifyCertificateAttestation(node).isOk:
    return ContinuityCheckDetail(verdict: ccError)
  # Stages 2-5 — pure predicate (shape / ancestry / tree).
  let verdict = verifyContinuity(observed, node)
  if verdict != ccPassed:
    let shapeOk = isOid40(observed.parent1) and isOid40(observed.parent2)
    let ancestryOk = shapeOk and observed.parent1 == node.getOrDefault("baseSha").getStr("") and
      observed.parent2 == node.getOrDefault("headSha").getStr("")
    let treeOk = ancestryOk and certHeadTreeDigest(node).len > 0 and
      sha256Hex(observed.headTreeOid) == certHeadTreeDigest(node)
    return ContinuityCheckDetail(verdict: verdict, mergeShapeOk: shapeOk, ancestryOk: ancestryOk,
      treeOk: treeOk)
  # Stage 6-7 — current tracked policy/scope digest equality ("" = unreadable
  # → fail-closed).
  let policyNow = fileSha256Hex("config/policy/merge_admission.json")
  let scopeNow = fileSha256Hex("data/verification_scope.lock")
  let policyOk = policyNow.len > 0 and policyNow == node.getOrDefault("policyDigest").getStr("")
  let scopeOk = scopeNow.len > 0 and scopeNow == node.getOrDefault("scopeDigest").getStr("")
  if not policyOk or not scopeOk:
    return ContinuityCheckDetail(verdict: ccError, mergeShapeOk: true, ancestryOk: true,
      treeOk: true, policyOk: policyOk, scopeOk: scopeOk)
  ContinuityCheckDetail(verdict: ccPassed, mergeShapeOk: true, ancestryOk: true, treeOk: true,
    policyOk: policyOk, scopeOk: scopeOk)

proc verifyContinuityCert*(observed: MainShape; certPath: string): ContinuityVerdict
    {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Thin verdict-only wrapper over verifyContinuityCertDetailed — the
  ## existing verdict surface (used by the CLI and the tests).
  verifyContinuityCertDetailed(observed, certPath).verdict

func continuityVerdictCode*(verdict: ContinuityVerdict): string {.raises: [].} =
  ## Machine reason code for journaling (mirrors the reasonCode convention of
  ## merge-admission / merge-publish records).
  case verdict
  of ccPassed: "CC_PASSED"
  of ccMismatch: "CC_MISMATCH"
  of ccNoCert: "CC_NO_CERT"
  of ccError: "CC_ERROR"

{.pop.}
