import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[json, strutils]
import core/crypto/hash_kernel
import core/results
import verification/canonical_json

## VerificationSubject — the certified subject of a subject certificate
## (certification continuity contract v10, §1 / INV-1..INV-3).
##
## Schema v2 (`axiom.subject.v2`): identity wire binds baseSha, headSha,
## headTreeDigest, policyDigest, scopeDigest, evidenceDigest via
## sha256Hex of a scheme-prefixed `\x1f`-separated wire. provenance
## records the construction source ("merge_admission").
##
## Identity semantics follow the contract exactly:
##   * identity = baseSha + headSha + headTreeDigest + policyDigest +
##     scopeDigest + evidenceDigest (the six field set bound by the
##     cert; no candidate OID / treeDigest-of-synthetic-M / chain
##     provenance in the wire).
##   * subjectId = sha256Hex("axiom.subject.v2\n" + baseSha + '\x1f' +
##     headSha + '\x1f' + headTreeDigest + '\x1f' + policyDigest +
##     '\x1f' + scopeDigest + '\x1f' + evidenceDigest).
##   * provenance = {scheme: "axiom.subject.v2", source: "merge_admission"}
##     — never part of the identity wire.
##   * prNumber and createdAt are bookkeeping fields on the schema,
##     NOT part of the identity wire.
##
## Tree re-derivation is FORBIDDEN downstream (INV-3): verifySubject
## and verifySubjectMatch perform exact equality only, never recompute
## trees.

const
  SubjectScheme* = "axiom.subject.v2"
    ## schemaVersion const + provenance.scheme (wire prefix).
  SubjectSource* = "merge_admission"
    ## provenance.source — the sanctioned merge-admission path.
  WireSeparator = '\x1f'
    ## Unit separator — cannot appear in any validated field (hex OIDs
    ## or 64-hex digest strings).

type
  SubjectProvenance* = object
    source*: string
    scheme*: string

  VerificationSubject* = object
    subjectId*: string
    baseSha*: string            ## 40-hex construction base B (origin/main at capture)
    headSha*: string            ## 40-hex PR head OID at capture
    headTreeDigest*: string     ## 64-hex sha256 of `git rev-parse headSha^{tree}`
    policyDigest*: string       ## 64-hex sha256 of config/policy/merge_admission.json
    scopeDigest*: string        ## 64-hex sha256 of data/verification_scope.lock
    evidenceDigest*: string     ## 64-hex sha256 over the evidence bundle wire
    prNumber*: int              ## bookkeeping only — NOT in identity wire
    createdAt*: string          ## ISO8601 Z ("yyyy-MM-dd'T'HH:mm:ss'Z'")
    provenance*: SubjectProvenance

  SubjectVerdict* = enum
    svMatch            ## every identity field equal — MATCH
    svEmptyInput       ## any required identity field missing/empty — REJECT (fail-closed)
    svBaseMismatch     ## baseSha differs
    svHeadMismatch     ## headSha differs
    svHeadTreeMismatch ## headTreeDigest differs
    svPolicyMismatch   ## policyDigest differs
    svScopeMismatch    ## scopeDigest differs
    svEvidenceMismatch ## evidenceDigest differs
    svIdMismatch       ## subjectId differs (field-level equality + re-derived id)

# ---------------------------------------------------------------------------
# Field validation — fail-closed input discipline
# ---------------------------------------------------------------------------

func isHexOfLen*(s: string; n: int): bool {.raises: [].} =
  if s.len != n:
    return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}:
      return false
  true

func isValidIso8601Zulu*(s: string): bool {.raises: [].} =
  ## Canonical creation timestamp: exactly "yyyy-MM-dd'T'HH:mm:ss'Z'"
  ## (merge_cli.getTimestamp output form) with sane ranges (month 01-12,
  ## day 01-31, hour 00-23, minute/second 00-59). Shape + range check, pure.
  if s.len != 20 or s[^1] != 'Z' or s[10] != 'T':
    return false
  for i in {4, 7}:
    if s[i] != '-':
      return false
  for i in {13, 16}:
    if s[i] != ':':
      return false
  for i in {0..3, 5..6, 8..9, 11..12, 14..15, 17..18}:
    if s[i] notin {'0'..'9'}:
      return false
  let month = (ord(s[5]) - ord('0')) * 10 + (ord(s[6]) - ord('0'))
  if month < 1 or month > 12:
    return false
  let day = (ord(s[8]) - ord('0')) * 10 + (ord(s[9]) - ord('0'))
  if day < 1 or day > 31:
    return false
  let hour = (ord(s[11]) - ord('0')) * 10 + (ord(s[12]) - ord('0'))
  if hour > 23:
    return false
  let minute = (ord(s[14]) - ord('0')) * 10 + (ord(s[15]) - ord('0'))
  if minute > 59:
    return false
  let second = (ord(s[17]) - ord('0')) * 10 + (ord(s[18]) - ord('0'))
  if second > 59:
    return false
  true

# ---------------------------------------------------------------------------
# Identity wire — the canonical subject id derivation (v2)
# ---------------------------------------------------------------------------

func subjectIdentityWire*(baseSha, headSha, headTreeDigest, policyDigest,
                           scopeDigest, evidenceDigest: string): string {.raises: [].} =
  ## The canonical wire hashed into subjectId: scheme prefix line + the six
  ## identity fields '\x1f'-separated. Header/separator layout is the frozen
  ## contract of the id — changing it changes every subjectId.
  SubjectScheme & "\n" & baseSha & WireSeparator & headSha & WireSeparator &
    headTreeDigest & WireSeparator & policyDigest & WireSeparator &
    scopeDigest & WireSeparator & evidenceDigest

func computeSubjectId*(baseSha, headSha, headTreeDigest, policyDigest,
                         scopeDigest, evidenceDigest: string): string {.raises: [].} =
  sha256Hex(subjectIdentityWire(baseSha, headSha, headTreeDigest,
    policyDigest, scopeDigest, evidenceDigest))

# ---------------------------------------------------------------------------
# Construction — makeSubject
# ---------------------------------------------------------------------------

func makeSubject*(baseSha, headSha, headTreeDigest, policyDigest,
                  scopeDigest, evidenceDigest: string;
                  prNumber: int; createdAt: string): Result[VerificationSubject, string] {.raises: [].} =
  ## Build a VerificationSubject from its parts. FAIL-CLOSED on every
  ## malformed input: 64-hex digest violations, 40-hex OID violations,
  ## non-canonical createdAt, or a negative prNumber. subjectId is
  ## derived from the canonical wire, never accepted as an input.
  if not isHexOfLen(baseSha, 40):
    return err("verification_subject: baseSha must be 40 lowercase hex chars (fail-closed)")
  if not isHexOfLen(headSha, 40):
    return err("verification_subject: headSha must be 40 lowercase hex chars (fail-closed)")
  if not isHexOfLen(headTreeDigest, 64):
    return err("verification_subject: headTreeDigest must be 64 lowercase hex chars (fail-closed)")
  if not isHexOfLen(policyDigest, 64):
    return err("verification_subject: policyDigest must be 64 lowercase hex chars (fail-closed)")
  if not isHexOfLen(scopeDigest, 64):
    return err("verification_subject: scopeDigest must be 64 lowercase hex chars (fail-closed)")
  if not isHexOfLen(evidenceDigest, 64):
    return err("verification_subject: evidenceDigest must be 64 lowercase hex chars (fail-closed)")
  if not isValidIso8601Zulu(createdAt):
    return err("verification_subject: createdAt must be ISO8601 UTC 'yyyy-MM-ddTHH:mm:ssZ' (fail-closed)")
  if prNumber < 0:
    return err("verification_subject: prNumber must be non-negative (fail-closed)")
  ok(VerificationSubject(
    subjectId: computeSubjectId(baseSha, headSha, headTreeDigest,
      policyDigest, scopeDigest, evidenceDigest),
    baseSha: baseSha,
    headSha: headSha,
    headTreeDigest: headTreeDigest,
    policyDigest: policyDigest,
    scopeDigest: scopeDigest,
    evidenceDigest: evidenceDigest,
    prNumber: prNumber,
    createdAt: createdAt,
    provenance: SubjectProvenance(source: SubjectSource, scheme: SubjectScheme)))

# ---------------------------------------------------------------------------
# Canonical serialization — single serializer (RFC 8785 via canonical_json)
# ---------------------------------------------------------------------------

func toCanonicalJson*(s: VerificationSubject): string {.raises: [].} =
  ## RFC 8785 canonical JSON of the subject record — the byte representation
  ## stored in data/trusted/subjects/ and bound by the certificate.
  canonicalJsonString(%*{
    "schemaVersion": SubjectScheme,
    "subjectId": s.subjectId,
    "baseSha": s.baseSha,
    "headSha": s.headSha,
    "headTreeDigest": s.headTreeDigest,
    "policyDigest": s.policyDigest,
    "scopeDigest": s.scopeDigest,
    "evidenceDigest": s.evidenceDigest,
    "prNumber": s.prNumber,
    "createdAt": s.createdAt,
    "provenance": {
      "source": s.provenance.source,
      "scheme": s.provenance.scheme
    }
  })

# ---------------------------------------------------------------------------
# Parsing — strict, self-validating (fail-closed)
# ---------------------------------------------------------------------------

func subjectFromJson*(node: JsonNode): Result[VerificationSubject, string] {.raises: [].} =
  ## Parse + fully validate a subject record. Missing/wrong-typed fields,
  ## malformed hex, wrong provenance source/scheme, or a subjectId that does
  ## not match the re-derived canonical wire → err (fail-closed: a tampered
  ## record is never read as "equal").
  if node.isNil or node.kind != JObject:
    return err("verification_subject: subject record must be a JSON object")
  template need(key: string): string =
    block:
      let v = node{key}
      if v.isNil or v.kind != JString or v.getStr().len == 0:
        return err("verification_subject: missing or empty field '" & key & "' (fail-closed)")
      v.getStr()
  let schemaVersion = need("schemaVersion")
  if schemaVersion != SubjectScheme:
    return err("verification_subject: unsupported schemaVersion '" &
      schemaVersion[0 ..< min(schemaVersion.len, 32)] & "' (fail-closed)")
  let recordedId = need("subjectId")
  let baseSha = need("baseSha")
  let headSha = need("headSha")
  let headTreeDigest = need("headTreeDigest")
  let policyDigest = need("policyDigest")
  let scopeDigest = need("scopeDigest")
  let evidenceDigest = need("evidenceDigest")
  let prNumberNode = node{"prNumber"}
  if prNumberNode.isNil or prNumberNode.kind != JInt:
    return err("verification_subject: prNumber missing or not an int (fail-closed)")
  let prNumber = prNumberNode.getInt()
  let createdAt = need("createdAt")
  let prov = node{"provenance"}
  if prov.isNil or prov.kind != JObject:
    return err("verification_subject: provenance must be an object (fail-closed)")
  let source = prov{"source"}
  let scheme = prov{"scheme"}
  if source.isNil or source.kind != JString or source.getStr().len == 0:
    return err("verification_subject: provenance.source missing or empty (fail-closed)")
  if scheme.isNil or scheme.kind != JString or scheme.getStr() != SubjectScheme:
    return err("verification_subject: provenance.scheme must be '" & SubjectScheme & "' (fail-closed)")
  let built = makeSubject(baseSha, headSha, headTreeDigest, policyDigest,
    scopeDigest, evidenceDigest, prNumber, createdAt)
  if built.isErr:
    return err("verification_subject: " & built.error)
  let subject = built.get
  if subject.subjectId != recordedId:
    return err("verification_subject: subjectId does not match the canonical wire re-derivation (fail-closed)")
  ok(subject)

func validateSubject*(s: VerificationSubject): string {.raises: [].} =
  ## Structural self-check used by the store before a durable write: "" =
  ## well-formed; otherwise the rejection reason (fail-closed — a malformed
  ## subject must never be persisted).
  let rebuilt = makeSubject(s.baseSha, s.headSha, s.headTreeDigest,
    s.policyDigest, s.scopeDigest, s.evidenceDigest, s.prNumber, s.createdAt)
  if rebuilt.isErr:
    return rebuilt.error
  if rebuilt.get.subjectId != s.subjectId:
    return "verification_subject: subjectId inconsistent with fields"
  ""

# ---------------------------------------------------------------------------
# Equality-only verification — INV-3: OID binding, no tree re-derivation
# ---------------------------------------------------------------------------

func isSubjectMatch*(v: SubjectVerdict): bool {.raises: [].} =
  v == svMatch

func verifySubject*(baseSha, headSha, headTreeDigest, policyDigest,
                    scopeDigest, evidenceDigest: string;
                    subject: VerificationSubject): SubjectVerdict {.raises: [].} =
  ## Verify a candidate claim against the stored subject — EQUALITY ONLY
  ## (contract INV-3: tree re-derivation comparison is forbidden; the binding
  ## is the recorded field values). Any missing/empty input denies
  ## (svEmptyInput, fail-closed — missing ≠ valid empty).
  if baseSha.len == 0 or headSha.len == 0 or headTreeDigest.len == 0 or
     policyDigest.len == 0 or scopeDigest.len == 0 or evidenceDigest.len == 0:
    return svEmptyInput
  if baseSha != subject.baseSha:
    return svBaseMismatch
  if headSha != subject.headSha:
    return svHeadMismatch
  if headTreeDigest != subject.headTreeDigest:
    return svHeadTreeMismatch
  if policyDigest != subject.policyDigest:
    return svPolicyMismatch
  if scopeDigest != subject.scopeDigest:
    return svScopeMismatch
  if evidenceDigest != subject.evidenceDigest:
    return svEvidenceMismatch
  svMatch

func verifySubjectMatch*(certSubject: VerificationSubject;
                         actualSubject: VerificationSubject): SubjectVerdict {.raises: [].} =
  ## The Phase 3+ admission entry point: EXACT equality on ALL identity
  ## fields (subjectId, baseSha, headSha, headTreeDigest, policyDigest,
  ## scopeDigest, evidenceDigest). Any missing/empty field on either side
  ## → svEmptyInput (fail-closed: an empty field is never "equal"), any
  ## difference → REJECT.
  if certSubject.subjectId.len == 0 or certSubject.baseSha.len == 0 or
     certSubject.headSha.len == 0 or certSubject.headTreeDigest.len == 0 or
     certSubject.policyDigest.len == 0 or certSubject.scopeDigest.len == 0 or
     certSubject.evidenceDigest.len == 0 or
     actualSubject.subjectId.len == 0 or actualSubject.baseSha.len == 0 or
     actualSubject.headSha.len == 0 or actualSubject.headTreeDigest.len == 0 or
     actualSubject.policyDigest.len == 0 or actualSubject.scopeDigest.len == 0 or
     actualSubject.evidenceDigest.len == 0:
    return svEmptyInput
  if certSubject.subjectId != actualSubject.subjectId:
    return svIdMismatch
  if certSubject.baseSha != actualSubject.baseSha:
    return svBaseMismatch
  if certSubject.headSha != actualSubject.headSha:
    return svHeadMismatch
  if certSubject.headTreeDigest != actualSubject.headTreeDigest:
    return svHeadTreeMismatch
  if certSubject.policyDigest != actualSubject.policyDigest:
    return svPolicyMismatch
  if certSubject.scopeDigest != actualSubject.scopeDigest:
    return svScopeMismatch
  if certSubject.evidenceDigest != actualSubject.evidenceDigest:
    return svEvidenceMismatch
  svMatch

{.pop.}