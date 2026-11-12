import core/trusted/layer_declaration
infrastructureLayer()
{.push raises: [].}

## evidence_artifact_io.nim — WP4-j.2 Phase D step 2 + WP4-j.4 witness artifact IO.
##
## Saves and loads CompletenessEvidence JSON artifacts at:
##   $AXIOM_STATE_DIR/.axiom/cache/evidence/<irDigest>.json
## Fallback base: getCurrentDir() when AXIOM_STATE_DIR is unset.
##
## Also persists the strict CompletenessBinding admission wrapper at
##   $AXIOM_STATE_DIR/.axiom/cache/evidence/<evidenceKey>.binding.json
## (see loadCompletenessBinding — the only canonical admission path; the legacy
## 5-field save/load below is kept for compatibility only).
##
## Fail-closed boundary: IO failure is silently ignored — it must not
## interrupt the verification pipeline.

import std/json
import std/os
import std/options
import std/strutils
import std/sequtils
import std/tables
import core/trusted/axiom_pragmas
import core/trusted/semantic_fact_types
import core/trusted/completeness_binding
import core/trusted/semantic_profile
import core/trusted/binding_inventory
import core/crypto/hash_kernel

proc evidenceCacheDir*(irDigest: string): string {.raises: [].} =
  ## Completeness evidence artifact path — <irDigest>.json
  let sr = getEnv("AXIOM_STATE_DIR", "").strip()
  let base = if sr.len > 0: sr
             else:
               try: getCurrentDir()
               except CatchableError: "."
  let dir = joinPath(base, ".axiom", "cache", "evidence")
  try: createDir(dir)
  except CatchableError: discard  # axiom:best-effort(cache dir creation non-blocking)
  joinPath(dir, irDigest & ".json")

proc witnessCachePath*(irDigest: string): string {.raises: [].} =
  ## WP4-j.4 lock: completeness evidence and instantiation witnesses are
  ## DIFFERENT artifacts — separate files prevent overwriting each other.
  let sr = getEnv("AXIOM_STATE_DIR", "").strip()
  let base = if sr.len > 0: sr
             else:
               try: getCurrentDir()
               except CatchableError: "."
  let dir = joinPath(base, ".axiom", "cache", "evidence")
  try: createDir(dir)
  except CatchableError: discard  # axiom:best-effort(cache dir creation non-blocking)
  joinPath(dir, irDigest & ".witness.json")

func evidenceToJson*(e: CompletenessEvidence): JsonNode {.raises: [].} =
  ## Serialize CompletenessEvidence to a JSON object.
  result = %* {
    "translationLossFree": e.translationLossFree,
    "bindingUniverseComplete": e.bindingUniverseComplete,
    "opaqueExpansionStatus": e.opaqueExpansionStatus,
    "sourceBindingCount": e.sourceBindingCount,
    "irBindingCount": e.irBindingCount
  }

proc jsonToEvidence*(j: JsonNode): CompletenessEvidence {.raises: [].} =
  ## Parse a JSON object into CompletenessEvidence.
  ## Missing fields fall back to defaults (false / "" / 0).
  try:
    if j.kind == JObject:
      result.translationLossFree =
        if j.hasKey("translationLossFree"): j["translationLossFree"].getBool
        else: false
      result.bindingUniverseComplete =
        if j.hasKey("bindingUniverseComplete"): j["bindingUniverseComplete"].getBool
        else: false
      result.opaqueExpansionStatus =
        if j.hasKey("opaqueExpansionStatus"): j["opaqueExpansionStatus"].getStr
        else: ""
      result.sourceBindingCount =
        if j.hasKey("sourceBindingCount"): j["sourceBindingCount"].getInt
        else: 0
      result.irBindingCount =
        if j.hasKey("irBindingCount"): j["irBindingCount"].getInt
        else: 0
  except CatchableError:
    # axiom:best-effort(evidence artifact IO failure is non-blocking boundary)
    discard

proc saveEvidenceArtifact*(irDigest: string, evidence: CompletenessEvidence) {.raises: [].} =
  ## Persist CompletenessEvidence to disk as a JSON artifact.
  ## IO failure is silently ignored (boundary — must not interrupt pipeline).
  try:
    let path = evidenceCacheDir(irDigest)
    let j = evidenceToJson(evidence)
    writeFile(path, $j)
  except CatchableError:
    # axiom:best-effort(evidence artifact IO failure is non-blocking boundary)
    discard

proc loadEvidenceArtifact*(irDigest: string): Option[CompletenessEvidence] {.axiomDecision, raises: [].} =
  ## Load CompletenessEvidence from disk. Returns none if artifact
  ## is absent, unreadable, or malformed (boundary — never crashes).
  try:
    let path = evidenceCacheDir(irDigest)
    if fileExists(path):
      let content = readFile(path)
      let j = parseJson(content)
      if j.kind == JObject:
        return some(jsonToEvidence(j))
  except CatchableError:
    # axiom:best-effort(evidence artifact IO failure is non-blocking boundary)
    discard
  return none(CompletenessEvidence)

# ---------------------------------------------------------------------------
# WP4-j.4 — Instantiation witness artifact (evidence ladder)
# ---------------------------------------------------------------------------

func witnessToJson*(w: InstantiationWitness): JsonNode {.raises: [].} =
  ## Serialize a single InstantiationWitness to a JSON object.
  result = %* {
    "callSite": w.callSite,
    "calleeSymbol": w.calleeSymbol,
    "actualArgs": w.actualArgs,
    "formalNames": w.formalNames,
    "formalTypedesc": w.formalTypedesc,
    "positionalRelation": w.positionalRelation,
    "concreteTypeArgument": w.concreteTypeArgument,
    "modulePath": w.modulePath,
    "occurrenceRef": w.occurrenceRef
  }

func witnessesToJson*(witnesses: seq[InstantiationWitness]): JsonNode {.raises: [].} =
  ## Serialize a seq of InstantiationWitnesses to a JSON array.
  result = %* []
  for w in witnesses:
    result.add(witnessToJson(w))

func computeWitnessDigest*(witnesses: seq[InstantiationWitness]): string {.raises: [].} =
  ## Deterministic witness integrity digest — fixed-order concatenation.
  ## identity ≠ integrity: this is content consistency, not authenticity.
  var parts: seq[string]
  for w in witnesses:
    parts.add(w.callSite & ":" & w.calleeSymbol & ":" &
              w.actualArgs.join(",") & ":" & w.concreteTypeArgument)
  sha256Hex(parts.join("|"))

proc saveInstantiationWitnesses*(irDigest, sourceIdentity, collectorIdentity,
    collectorRevision, schemaVersion: string; witnesses: seq[InstantiationWitness]) {.raises: [].} =
  ## Persist InstantiationWitnesses as a JSON artifact alongside the
  ## completeness evidence artifact. witnessDigest guards integrity.
  try:
    let path = witnessCachePath(irDigest)
    let j = %* {
      "sourceIdentity": sourceIdentity,
      "irDigest": irDigest,
      "collectorIdentity": collectorIdentity,
      "collectorRevision": collectorRevision,
      "schemaVersion": schemaVersion,
      "witnessDigest": computeWitnessDigest(witnesses),
      "witnesses": witnessesToJson(witnesses)
    }
    writeFile(path, $j)
  except CatchableError:
    # axiom:best-effort(evidence artifact IO failure is non-blocking boundary)
    discard

proc loadInstantiationWitnesses*(irDigest: string): Option[seq[InstantiationWitness]] {.axiomDecision, raises: [].} =
  ## Load InstantiationWitnesses from disk and verify witnessDigest.
  ## Recomputes digest from loaded witnesses and compares with the
  ## stored value; returns none on missing, unreadable, malformed,
  ## or digest mismatch (fail-closed integrity gate).
  try:
    let path = witnessCachePath(irDigest)
    if fileExists(path):
      let content = readFile(path)
      let j = parseJson(content)
      if j.kind == JObject:
        let storedDigest = j["witnessDigest"].getStr
        let arr = j["witnesses"]
        if arr.kind != JArray:
          return none(seq[InstantiationWitness])
        var witnesses: seq[InstantiationWitness]
        for elem in arr:
          if elem.kind != JObject: continue
          func parseStrArr(j: JsonNode): seq[string] =
            if j.kind != JArray: return @[]
            for e in j: result.add(e.getStr)
          func parseBoolArr(j: JsonNode): seq[bool] =
            if j.kind != JArray: return @[]
            for e in j: result.add(e.getBool)
          func parseIntArr(j: JsonNode): seq[int] =
            if j.kind != JArray: return @[]
            for e in j: result.add(e.getInt)
          func jStr(j: JsonNode; key: string; default: string): string =
            if j.kind == JObject:
              let val = j.fields.getOrDefault(key)
              if val.kind == JString: return val.getStr
            default
          witnesses.add(InstantiationWitness(
            callSite: jStr(elem, "callSite", ""),
            calleeSymbol: jStr(elem, "calleeSymbol", ""),
            actualArgs: parseStrArr(elem["actualArgs"]),
            formalNames: parseStrArr(elem["formalNames"]),
            formalTypedesc: parseBoolArr(elem["formalTypedesc"]),
            positionalRelation: parseIntArr(elem["positionalRelation"]),
            concreteTypeArgument: jStr(elem, "concreteTypeArgument", ""),
            modulePath: jStr(elem, "modulePath", ""),
            occurrenceRef: jStr(elem, "occurrenceRef", "")))
        let computed = computeWitnessDigest(witnesses)
        if computed != storedDigest:
          return none(seq[InstantiationWitness])
        return some(witnesses)
  except CatchableError:
    # axiom:best-effort(evidence artifact IO failure is non-blocking boundary)
    discard
  return none(seq[InstantiationWitness])

# ---------------------------------------------------------------------------
# CompletenessBinding — strict admission wrapper over CompletenessEvidence
# ---------------------------------------------------------------------------
## The legacy loadEvidenceArtifact path accepts any parseable object at the
## anchor path and silently defaults missing fields — admissible for the
## compatibility boundary, never for canonical admission. A CompletenessBinding
## is the strict alternative: key equality, schema version, recomputed evidence
## digest, and caller-provided current-source / profile / toolchain equality
## are ALL required; any mismatch or missing field yields none.
##
## Artifact path: <evidenceKey>.binding.json — a distinct extension is
## load-bearing on both sides: loadCompletenessBinding can never read a legacy
## 5-field artifact, and the legacy loader's silent-default parser can never
## project a binding onto all-false defaults.

proc completenessBindingCachePath*(evidenceKey: string): string {.raises: [].} =
  ## CompletenessBinding artifact path — <evidenceKey>.binding.json
  ## (sibling of <irDigest>.json and <irDigest>.witness.json).
  let sr = getEnv("AXIOM_STATE_DIR", "").strip()
  let base = if sr.len > 0: sr
             else:
               try: getCurrentDir()
               except CatchableError: "."
  let dir = joinPath(base, ".axiom", "cache", "evidence")
  try: createDir(dir)
  except CatchableError: discard  # axiom:best-effort(cache dir creation non-blocking)
  joinPath(dir, evidenceKey & ".binding.json")

const StrictCompletenessGenerationTag* = "strict-completeness-generation-v1"

proc strictGenerationMarkerPath*(evidenceKey: string): string {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Sibling of <evidenceKey>.binding.json. The marker records WHICH GENERATION
  ## produced the record, never the evidence: admission still requires the
  ## binding artifact and re-verifies its full digest/context contract.
  let bindingPath = completenessBindingCachePath(evidenceKey)
  const suffix = ".binding.json"
  if bindingPath.endsWith(suffix):
    bindingPath[0 ..< bindingPath.len - suffix.len] & ".strict-gen"
  else:
    bindingPath & ".strict-gen"

proc markStrictGeneration*(evidenceKey: string): bool {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Written by the strict producer BEFORE the binding write is attempted, so
  ## a measurement/IO failure leaves a permanent generation tag: the reader
  ## then refuses the legacy fallback for this anchor even when
  ## AXIOM_EVIDENCE_STRICT is unset. Without the marker an older legacy-only
  ## record keeps the compatibility path; the tag is what distinguishes "this
  ## generation tried and could not measure" from "pre-generation record".
  if evidenceKey.len == 0:
    return false
  var tmp = ""
  try:
    let path = strictGenerationMarkerPath(evidenceKey)
    tmp = path & ".tmp." & $getCurrentProcessId()
    writeFile(tmp, StrictCompletenessGenerationTag & "\n")
    moveFile(tmp, path)
    return true
  except CatchableError, Exception:
    # axiom:best-effort(marker IO failure is non-blocking; strict mode still
    # fails closed, and the absence of a marker never admits anything by itself)
    if tmp.len > 0:
      try: removeFile(tmp)
      except CatchableError: discard  # axiom:best-effort(marker temp cleanup non-blocking)
    return false

proc hasStrictGenerationMarker*(evidenceKey: string): bool {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if evidenceKey.len == 0:
    return false
  # Content read (not fileExists): the marker is judged by its recorded
  # generation tag, so a truncated/foreign file is not a marker. Reading also
  # makes the I/O reach explicit to the purity analyzer, which cannot see
  # through fileExists' side-effect-only signature.
  try:
    readFile(strictGenerationMarkerPath(evidenceKey)).startsWith(
      StrictCompletenessGenerationTag)
  except CatchableError:
    false

func isCanonicalSha256Hex(s: string): bool {.raises: [].} =
  if s.len != 64:
    return false
  for ch in s:
    if ch notin {'0'..'9', 'a'..'f'}:
      return false
  true

proc parseCompletenessPayloadStrict(p: JsonNode): Option[CompletenessEvidence] {.
    raises: [].} =
  ## Strict payload parse: exact key set, exact JSON types, no defaults.
  const payloadKeys = ["translationLossFree", "bindingUniverseComplete",
                       "opaqueExpansionStatus", "sourceBindingCount",
                       "irBindingCount"]
  if p.isNil or p.kind != JObject:
    return none(CompletenessEvidence)
  for k in payloadKeys:
    if not p.hasKey(k):
      return none(CompletenessEvidence)
  for k in p.keys:
    if k notin payloadKeys:
      return none(CompletenessEvidence)
  template field(key: string): JsonNode =
    p.fields.getOrDefault(key)
  let tlf = field("translationLossFree")
  if tlf.isNil or tlf.kind != JBool:
    return none(CompletenessEvidence)
  let buc = field("bindingUniverseComplete")
  if buc.isNil or buc.kind != JBool:
    return none(CompletenessEvidence)
  let oes = field("opaqueExpansionStatus")
  if oes.isNil or oes.kind != JString:
    return none(CompletenessEvidence)
  let sbc = field("sourceBindingCount")
  if sbc.isNil or sbc.kind != JInt:
    return none(CompletenessEvidence)
  let ibc = field("irBindingCount")
  if ibc.isNil or ibc.kind != JInt:
    return none(CompletenessEvidence)
  some(CompletenessEvidence(
    translationLossFree: tlf.getBool,
    bindingUniverseComplete: buc.getBool,
    opaqueExpansionStatus: oes.getStr,
    sourceBindingCount: sbc.getInt,
    irBindingCount: ibc.getInt))

proc parseCompletenessBindingJson(j: JsonNode): Option[CompletenessBinding] {.
    raises: [].} =
  ## Strict binding parse: exact top-level key set (no missing, no unknown),
  ## string kind for the eight scalar fields, object payload. Returns none on
  ## any deviation — a binding with a gap is not a binding.
  const fieldKeys = ["schemaVersion", "evidenceKey", "irDigest",
                     "irDigestCanonical", "sourceIdentity",
                     "subjectModuleSha256", "semanticProfileId",
                     "toolchainFingerprint", "payload", "evidenceDigest"]
  if j.isNil or j.kind != JObject:
    return none(CompletenessBinding)
  for k in fieldKeys:
    if not j.hasKey(k):
      return none(CompletenessBinding)
  for k in j.keys:
    if k notin fieldKeys:
      return none(CompletenessBinding)
  var b: CompletenessBinding
  template strField(fieldName: untyped; key: string): bool =
    let v = j.fields.getOrDefault(key)
    if not v.isNil and v.kind == JString:
      b.fieldName = v.getStr
      true
    else:
      false
  if not (strField(schemaVersion, "schemaVersion") and
          strField(evidenceKey, "evidenceKey") and
          strField(irDigest, "irDigest") and
          strField(irDigestCanonical, "irDigestCanonical") and
          strField(sourceIdentity, "sourceIdentity") and
          strField(subjectModuleSha256, "subjectModuleSha256") and
          strField(semanticProfileId, "semanticProfileId") and
          strField(toolchainFingerprint, "toolchainFingerprint") and
          strField(evidenceDigest, "evidenceDigest")):
    return none(CompletenessBinding)
  let payload = parseCompletenessPayloadStrict(j.fields.getOrDefault("payload"))
  if payload.isNone:
    return none(CompletenessBinding)
  b.payload = payload.get
  some(b)

proc saveCompletenessBinding*(binding: CompletenessBinding): bool {.raises: [].} =
  ## Persist a CompletenessBinding atomically (temp file + rename within the
  ## cache dir). Fail-closed at the write boundary: refuses non-v1
  ## schemaVersion, empty anchor, non-canonical sha256-hex digest fields, and a
  ## binding whose evidenceDigest does not match its own content. Returns true
  ## only when the rename landed; never raises (pipeline boundary).
  if binding.schemaVersion != CompletenessBindingSchemaVersion:
    return false
  if binding.evidenceKey.len == 0:
    return false
  for d in [binding.evidenceKey, binding.irDigest, binding.irDigestCanonical,
            binding.subjectModuleSha256, binding.semanticProfileId,
            binding.toolchainFingerprint, binding.evidenceDigest]:
    if not isCanonicalSha256Hex(d):
      return false
  if binding.evidenceDigest != computeCompletenessBindingDigest(binding):
    return false
  var tmp = ""
  try:
    let path = completenessBindingCachePath(binding.evidenceKey)
    tmp = path & ".tmp." & $getCurrentProcessId()
    writeFile(tmp, $completenessBindingToJson(binding))
    moveFile(tmp, path)
    return true
  except CatchableError, Exception:
    # axiom:best-effort(evidence artifact IO failure is non-blocking boundary)
    # Exception is listed because std/os moveFile declares base-Exception
    # raises; CatchableError keeps IOError/OSError handling explicit.
    if tmp.len > 0:
      try: removeFile(tmp)
      except CatchableError: discard  # axiom:best-effort(temp cleanup non-blocking)
    return false

proc saveStrictCompletenessBinding*(evidenceKey, irDigestCanonical,
    sourceIdentity, subjectModuleSha256, toolchainFingerprint: string;
    payload: CompletenessEvidence): bool {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Producer-side dual-write half (Phase 1A): the strict sibling a
  ## CompletenessEvidence producer saves alongside its legacy
  ## `saveEvidenceArtifact(key, payload)` write. The strict binding records
  ## `irDigest` = the SAME flavor-③ anchor the legacy artifact is keyed by
  ## (`evidenceKey` — "artifact key MUST match the runner cache scheme"),
  ## `irDigestCanonical` = the caller-measured flavor-② digest
  ## (computeIrDigest), and the caller-measured source identity / module
  ## sha256 / toolchain fingerprint.
  ##
  ## Fail-closed at the producer boundary: ANY unmeasured identity component
  ## (empty sourceIdentity, non-64-hex module sha / canonical IR digest /
  ## toolchain fingerprint, empty anchor) refuses the write and returns
  ## false — an identity-less binding is never fabricated. The caller keeps
  ## its legacy artifact regardless, so an unmeasured capture degrades to
  ## the legacy generation (which the strict-first reader accepts only while
  ## AXIOM_EVIDENCE_STRICT is unset) instead of a forged strict record.
  if evidenceKey.len == 0:
    return false
  if sourceIdentity.len == 0:
    return false
  for d in [evidenceKey, irDigestCanonical, subjectModuleSha256,
            toolchainFingerprint]:
    if not isCanonicalSha256Hex(d):
      return false
  let binding = makeCompletenessBinding(
    evidenceKey = evidenceKey,
    irDigest = evidenceKey,
    irDigestCanonical = irDigestCanonical,
    sourceIdentity = sourceIdentity,
    subjectModuleSha256 = subjectModuleSha256,
    semanticProfileId = SemanticProfileV1Hash,
    toolchainFingerprint = toolchainFingerprint,
    payload = payload)
  saveCompletenessBinding(binding)

proc loadCompletenessBinding*(evidenceKey: string; currentSourceIdentity,
    currentSubjectModuleSha256, currentSemanticProfileId,
    currentToolchainFingerprint: string): Option[CompletenessBinding] {.
    axiomDecision, raises: [].} =
  ## Load and fully verify a CompletenessBinding. Every check below is
  ## fail-closed — a single failure yields none, never a defaulted record:
  ##   1. strict parse: exact key set + exact JSON types (no missing/unknown)
  ##   2. schemaVersion == CompletenessBindingSchemaVersion (unknown → none)
  ##   3. key equality: stored evidenceKey == the requested load anchor
  ##   4. evidenceDigest recomputed from parsed content == stored digest
  ##   5. sourceIdentity / subjectModuleSha256 == caller-provided current source
  ##      (a comment-only source edit changes the module sha256 → stale → none)
  ##   6. semanticProfileId == current profile (SemanticProfileV1Hash)
  ##   7. toolchainFingerprint == current pinned fingerprint
  ## Absent file, unreadable or malformed bytes are equally none.
  try:
    let path = completenessBindingCachePath(evidenceKey)
    if not fileExists(path):
      return none(CompletenessBinding)
    let j = parseJson(readFile(path))
    let parsed = parseCompletenessBindingJson(j)
    if parsed.isNone:
      return none(CompletenessBinding)
    let b = parsed.get
    if b.schemaVersion != CompletenessBindingSchemaVersion:
      return none(CompletenessBinding)
    if b.evidenceKey != evidenceKey:
      return none(CompletenessBinding)
    if b.evidenceDigest != computeCompletenessBindingDigest(b):
      return none(CompletenessBinding)
    if b.sourceIdentity != currentSourceIdentity:
      return none(CompletenessBinding)
    if b.subjectModuleSha256 != currentSubjectModuleSha256:
      return none(CompletenessBinding)
    if b.semanticProfileId != currentSemanticProfileId:
      return none(CompletenessBinding)
    if b.toolchainFingerprint != currentToolchainFingerprint:
      return none(CompletenessBinding)
    return some(b)
  except CatchableError:
    # axiom:best-effort(evidence artifact IO failure is non-blocking boundary)
    discard
  return none(CompletenessBinding)

{.pop.}
