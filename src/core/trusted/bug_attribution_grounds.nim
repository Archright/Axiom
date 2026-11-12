import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import std/[json, sets, strutils]
import core/crypto/hash_kernel
import core/types/results

## Bug attribution axis — pure canonical-record validation (record layer).
##
## Two fail-closed validators, both pure over parsed JSON (no IO, no clock,
## no env — deterministic on identical input):
##
##   1. `validateClaimOwnership` — the additive `claimOwnership` block of an
##      explicit spec overlay. Closed owner value set, contract-path
##      agreement with the overlay's own `contract` field, non-empty
##      adoption reference. Missing/typo/contradiction -> error.
##   2. `validateGroundsFile` — an upstream-attribution grounds record
##      (`data/bug_attribution/<SPEC-ID>.json`): closed key set, subject
##      binding cross-checked against the cited spec overlay, C-carried
##      observation quartet (shared quartet, glossary §2.2), grounds
##      E1/E2/E3 shape (present:true => non-empty refs AND a quartet-complete
##      C-carried reproduction; present:false => empty refs AND no
##      reproduction), corroboration recorded as corroboration ONLY, and a
##      self-describing `recordDigest`.
##
## Display labels ("BUG_FOUND" / "BUG_SUSPECTED" / "Axiom-Defined Rule
## Violated") are projection-only and are NEITHER stored in these records
## NOR returned by this module (glossary §2.4; the closed key set makes a
## stored label a validation error). This module introduces no verdict
## value, no producer, no gate — it only rejects malformed records
## (fail closed).

const
  bugAttributionGroundsSchemaVersion* = "bug-attribution-grounds-v1"
  ## Closed owner value set of `claimOwnership.owner` (additive spec field).
  claimOwnershipOwners* = ["axiom-defined-rule", "software-requirement"]
  ## Closed value set of the grounds record's `requirementSourceStatus`
  ## (glossary §2.4c decision table). "unknown" is the 4th value: source
  ## determination incomplete — it records no binding, so it can never
  ## confirm (the display layer confirms only against "recordedBinding").
  requirementSourceStatuses* = ["recordedBinding", "recordedDisclaiming",
    "unrecorded", "unknown"]
  ## E-categories of the Bug Confirmed definition (glossary §2.4a).
  groundsCategories* = ["E1", "E2", "E3"]

type
  GroundsFileView* = object
    ## Field view projected out of a validated grounds record. Strings only —
    ## no verdict/label enum is introduced here.
    specId*: string
    subjectCommit*: string
    moduleSha256*: string
    requirementSourceStatus*: string
    corroborationSpecId*: string
    corroborationVerdict*: string
    corroborationReplayVerdict*: string

func isLowerHex(s: string; width: int): bool {.inline.} =
  if s.len != width:
    return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}:
      return false
  true

func isNonEmptyString(n: JsonNode): bool {.inline.} =
  not n.isNil and n.kind == JString and n.getStr("").len > 0

func isStringArray(n: JsonNode; allowEmpty: bool): bool =
  if n.isNil or n.kind != JArray:
    return false
  if not allowEmpty and n.len == 0:
    return false
  for item in n:
    if item.kind != JString or item.getStr("").len == 0:
      return false
  true

func hasUnexpectedKey(node: JsonNode; allowed: openArray[string]): string =
  ## First key of `node` outside `allowed` ("" when none) — closed-schema
  ## surface; also catches a stored display label.
  var allowedSet: HashSet[string]
  for k in allowed:
    allowedSet.incl(k)
  for k in keys(node):
    if k notin allowedSet:
      return k
  ""

func requireObject(node: JsonNode; path: string): Result[JsonNode, string] =
  if node.isNil or node.kind != JObject:
    err(path & ": object required")
  else:
    ok(node)

func validateReproduction(repro: JsonNode; path: string): Result[bool, string] =
  ## The reproduction element of the shared quartet (glossary §2.2 ④):
  ## observed output + replay command + toolchain/host fold + external
  ## source. Closed key set.
  let checked = requireObject(repro, path)
  if checked.isErr:
    return err(checked.error)
  let unexpected = hasUnexpectedKey(repro, ["observedOutput", "replayCommand",
    "toolchain", "hostPlatform", "source"])
  if unexpected.len > 0:
    return err(path & ": unexpected key '" & unexpected & "'")
  let observed = repro{"observedOutput"}
  if observed.isNil or observed.kind != JObject or observed.len == 0:
    return err(path & ".observedOutput: non-empty object required")
  for field in ["replayCommand", "toolchain", "hostPlatform", "source"]:
    if not isNonEmptyString(repro{field}):
      return err(path & "." & field & ": non-empty string required")
  ok(true)

func validateClaimOwnership*(node: JsonNode): Result[string, string] =
  ## Validate the additive `claimOwnership` block of a spec overlay node and
  ## return its owner on success. Fail closed on missing field, typo'd owner,
  ## or contradiction with the overlay's own `contract` field.
  let owner = node{"claimOwnership"}
  if owner.isNil:
    return err("claimOwnership: object required (a claim-bearing spec must " &
      "declare its claim owner)")
  if owner.kind != JObject:
    return err("claimOwnership: object required")
  # Closed key set: the three required members plus the OPTIONAL `provenance`
  # member the registry layer's validateOwnershipObject requires of adoption-
  # authority records (bv/d2 overlays carry it). Closed-set discipline is
  # preserved — any other key (incl. a stored display label) is still an
  # error.
  let unexpected = hasUnexpectedKey(owner, ["owner", "contract", "adoptionRef",
    "provenance"])
  if unexpected.len > 0:
    return err("claimOwnership: unexpected key '" & unexpected & "'")
  let ownerValue = owner{"owner"}.getStr("")
  if ownerValue notin claimOwnershipOwners:
    return err("claimOwnership.owner must be one of " &
      $claimOwnershipOwners & ", got '" & ownerValue & "'")
  let contract = owner{"contract"}.getStr("")
  if not contract.startsWith("docs/spec/"):
    return err("claimOwnership.contract must point at docs/spec/, got '" &
      contract & "'")
  let overlayContract = node{"contract"}.getStr("")
  if overlayContract.len > 0 and overlayContract != contract:
    return err("claimOwnership.contract '" & contract &
      "' contradicts the overlay's contract field '" & overlayContract & "'")
  if not isNonEmptyString(owner{"adoptionRef"}):
    return err("claimOwnership.adoptionRef: non-empty string required " &
      "(where adoption is recorded)")
  ok(ownerValue)

func deepCopySansKey(node: JsonNode; omitKey: string): JsonNode =
  ## Pure deep copy of a JSON tree omitting one top-level object member.
  ## Constructor-based (no parseJson) — cannot raise, so it stays inside the
  ## `{.raises: [].}` discipline of this module.
  case node.kind
  of JObject:
    result = newJObject()
    for k, v in pairs(node):
      if k != omitKey:
        result[k] = deepCopySansKey(v, omitKey)
  of JArray:
    result = newJArray()
    for item in items(node):
      result.add(deepCopySansKey(item, omitKey))
  of JString:
    result = newJString(node.getStr())
  of JInt:
    result = newJInt(node.getInt())
  of JFloat:
    result = newJFloat(node.getFloat())
  of JBool:
    result = newJBool(node.getBool())
  of JNull:
    result = newJNull()

func computeRecordDigest*(node: JsonNode): string =
  ## sha256 hex of the record's canonical serialization: the node re-serialized
  ## with the `recordDigest` member REMOVED, std/json `pretty` (2-space
  ## indent), one trailing LF. Pure and deterministic — the digest never
  ## covers itself.
  sha256Hex(pretty(deepCopySansKey(node, "recordDigest")) & "\n")

func validateGroundsEnvelope(grounds: JsonNode): Result[bool, string] =
  ## Root-object, closed-key-set, and schema-version gates of the record.
  let root = requireObject(grounds, "grounds file")
  if root.isErr:
    return err(root.error)
  let unexpected = hasUnexpectedKey(grounds, ["schema", "specId",
    "subjectCommit", "moduleSha256", "requirementSourceStatus",
    "requirementSourceRefs", "anomaly", "confirmation", "corroboration",
    "recordDigest"])
  if unexpected.len > 0:
    return err("grounds file: unexpected key '" & unexpected &
      "' (closed schema — display labels are projection-only and are not stored)")
  if grounds{"schema"}.getStr("") != bugAttributionGroundsSchemaVersion:
    return err("grounds file: schema must be '" &
      bugAttributionGroundsSchemaVersion & "'")
  ok(true)

func validateGroundsSubjectBinding(grounds, spec: JsonNode):
    Result[tuple[specId, subjectCommit, moduleSha256: string], string] =
  ## specId agreement + pinned subject commit + pinned subject blob,
  ## cross-checked against the cited spec overlay.
  let specId = grounds{"specId"}.getStr("")
  if specId.len == 0:
    return err("grounds file: specId required")
  if spec{"specId"}.getStr("") != specId:
    return err("grounds file: specId '" & specId &
      "' does not match the cited spec's specId")

  let subjectCommit = grounds{"subjectCommit"}.getStr("")
  if not isLowerHex(subjectCommit, 40):
    return err("grounds file: subjectCommit must be a 40-hex commit OID")
  let specCommit = spec{"subject"}{"commit"}.getStr("")
  if specCommit.len == 0 or subjectCommit != specCommit:
    return err("grounds file: subjectCommit is not the cited spec's pinned " &
      "subject commit (spec.subject.commit)")

  let moduleSha256 = grounds{"moduleSha256"}.getStr("")
  if not isLowerHex(moduleSha256, 64):
    return err("grounds file: moduleSha256 must be 64-hex sha256")
  if spec{"subject"}{"blobSha256"}.getStr("") != moduleSha256:
    return err("grounds file: moduleSha256 does not match the cited spec's " &
      "pinned subject blob")
  ok((specId: specId, subjectCommit: subjectCommit,
    moduleSha256: moduleSha256))

func validateGroundsQuartet(grounds: JsonNode;
    subjectCommit: string): Result[bool, string] =
  ## C-carried observation quartet gates (shared quartet, glossary §2.2).
  let anomaly = requireObject(grounds{"anomaly"}, "grounds file: anomaly")
  if anomaly.isErr:
    return err(anomaly.error)
  let anomalyUnexpected = hasUnexpectedKey(grounds{"anomaly"},
    ["observationQuartet"])
  if anomalyUnexpected.len > 0:
    return err("grounds file: anomaly: unexpected key '" & anomalyUnexpected &
      "'")
  let quartet = requireObject(grounds{"anomaly"}{"observationQuartet"},
    "grounds file: anomaly.observationQuartet")
  if quartet.isErr:
    return err(quartet.error)
  let quartetUnexpected = hasUnexpectedKey(grounds{"anomaly"}{"observationQuartet"},
    ["exactCommit", "exactInput", "violationStatement", "reproduction"])
  if quartetUnexpected.len > 0:
    return err("grounds file: anomaly.observationQuartet: unexpected key '" &
      quartetUnexpected & "'")
  if grounds{"anomaly"}{"observationQuartet"}{"exactCommit"}.getStr("") !=
      subjectCommit:
    return err("grounds file: anomaly.observationQuartet.exactCommit must " &
      "equal subjectCommit")
  let exactInput = grounds{"anomaly"}{"observationQuartet"}{"exactInput"}
  if exactInput.isNil or exactInput.kind != JObject or exactInput.len == 0:
    return err("grounds file: anomaly.observationQuartet.exactInput: " &
      "non-empty object required")
  if not isNonEmptyString(grounds{"anomaly"}{"observationQuartet"}{"violationStatement"}):
    return err("grounds file: anomaly.observationQuartet.violationStatement: " &
      "non-empty string required")
  let reproRes = validateReproduction(
    grounds{"anomaly"}{"observationQuartet"}{"reproduction"},
    "grounds file: anomaly.observationQuartet.reproduction")
  if reproRes.isErr:
    return err(reproRes.error)
  ok(true)

func validateGroundsConfirmation(grounds: JsonNode): Result[bool, string] =
  ## confirmation.grounds map envelope: closed key set of both levels.
  let confirmation = requireObject(grounds{"confirmation"},
    "grounds file: confirmation")
  if confirmation.isErr:
    return err(confirmation.error)
  let confirmationUnexpected = hasUnexpectedKey(grounds{"confirmation"},
    ["grounds"])
  if confirmationUnexpected.len > 0:
    return err("grounds file: confirmation: unexpected key '" &
      confirmationUnexpected & "'")
  let groundsMap = requireObject(grounds{"confirmation"}{"grounds"},
    "grounds file: confirmation.grounds")
  if groundsMap.isErr:
    return err(groundsMap.error)
  let groundsUnexpected = hasUnexpectedKey(grounds{"confirmation"}{"grounds"},
    groundsCategories)
  if groundsUnexpected.len > 0:
    return err("grounds file: confirmation.grounds: unexpected key '" &
      groundsUnexpected & "'")
  ok(true)

func validateGroundsCategories(grounds: JsonNode): Result[bool, string] =
  ## E1/E2/E3 grounds records: present:true => non-empty refs AND a
  ## quartet-complete C-carried reproduction; present:false => empty refs
  ## AND no reproduction.
  for category in groundsCategories:
    let ground = grounds{"confirmation"}{"grounds"}{category}
    if ground.isNil or ground.kind != JObject:
      return err("grounds file: confirmation.grounds." & category &
        ": object required")
    let groundUnexpected = hasUnexpectedKey(ground,
      ["present", "refs", "reproduction"])
    if groundUnexpected.len > 0:
      return err("grounds file: confirmation.grounds." & category &
        ": unexpected key '" & groundUnexpected & "'")
    let present = ground{"present"}
    if present.isNil or present.kind != JBool:
      return err("grounds file: confirmation.grounds." & category &
        ".present: boolean required")
    if not isStringArray(ground{"refs"}, allowEmpty = true):
      return err("grounds file: confirmation.grounds." & category &
        ".refs: array of reference strings required")
    if present.getBool():
      if ground{"refs"}.len == 0:
        return err("groundsValidation: " & category & " present:true " &
          "requires non-empty refs")
      let groundRepro = ground{"reproduction"}
      if groundRepro.isNil or groundRepro.kind != JObject or groundRepro.len == 0:
        return err("groundsValidation: " & category & " present:true " &
          "requires a C-carried reproduction quartet (shared quartet, " &
          "glossary §2.2)")
      let groundReproRes = validateReproduction(groundRepro,
        "grounds file: confirmation.grounds." & category & ".reproduction")
      if groundReproRes.isErr:
        return err(groundReproRes.error)
    else:
      if ground{"refs"}.len != 0:
        return err("groundsValidation: " & category & " present:false " &
          "requires empty refs")
      let groundRepro = ground{"reproduction"}
      if not groundRepro.isNil and groundRepro.kind == JObject and
          groundRepro.len != 0:
        return err("groundsValidation: " & category & " present:false " &
          "requires no reproduction block")
  ok(true)

func validateGroundsCorroboration(grounds: JsonNode;
    specId: string): Result[JsonNode, string] =
  ## Corroboration recorded as corroboration ONLY; returns the machineRef
  ## node for the view projection.
  let corroboration = requireObject(grounds{"corroboration"},
    "grounds file: corroboration")
  if corroboration.isErr:
    return err(corroboration.error)
  let corroborationUnexpected = hasUnexpectedKey(grounds{"corroboration"},
    ["machineRef", "note"])
  if corroborationUnexpected.len > 0:
    return err("grounds file: corroboration: unexpected key '" &
      corroborationUnexpected & "'")
  let machineRef = grounds{"corroboration"}{"machineRef"}
  if machineRef.isNil or machineRef.kind != JObject:
    return err("grounds file: corroboration.machineRef: object required")
  let machineRefUnexpected = hasUnexpectedKey(machineRef,
    ["specId", "verdict", "replayVerdict"])
  if machineRefUnexpected.len > 0:
    return err("grounds file: corroboration.machineRef: unexpected key '" &
      machineRefUnexpected & "'")
  if machineRef{"specId"}.getStr("") != specId:
    return err("grounds file: corroboration.machineRef.specId must equal " &
      "the record's specId")
  if not isNonEmptyString(machineRef{"verdict"}) or
      not isNonEmptyString(machineRef{"replayVerdict"}):
    return err("grounds file: corroboration.machineRef.verdict and " &
      "replayVerdict: non-empty strings required")
  if not isNonEmptyString(grounds{"corroboration"}{"note"}):
    return err("grounds file: corroboration.note: non-empty string required " &
      "(corroboration ONLY — it can never satisfy the C-carried reproduction " &
      "requirement)")
  ok(machineRef)

func validateGroundsDigest(grounds: JsonNode): Result[bool, string] =
  ## Self-describing recordDigest gate (the digest never covers itself).
  let recordDigest = grounds{"recordDigest"}.getStr("")
  if not isLowerHex(recordDigest, 64):
    return err("grounds file: recordDigest must be 64-hex sha256")
  if recordDigest != computeRecordDigest(grounds):
    return err("grounds file: recordDigest does not match the canonical " &
      "serialization (pretty JSON without the recordDigest member, +LF)")
  ok(true)

func validateGroundsFile*(grounds, spec: JsonNode): Result[GroundsFileView, string] =
  ## Validate a grounds record against its cited spec overlay.
  ## Fail closed on: schema drift, unexpected keys (incl. stored display
  ## labels), subject-binding mismatch, incomplete C-carried quartet,
  ## malformed grounds (present:true without reproduction / present:false
  ## with refs or reproduction), unknown requirementSourceStatus,
  ## corroboration not marked as corroboration-only, digest mismatch.
  let envelope = validateGroundsEnvelope(grounds)
  if envelope.isErr:
    return err(envelope.error)
  let binding = validateGroundsSubjectBinding(grounds, spec)
  if binding.isErr:
    return err(binding.error)
  let specId = binding.value.specId
  let subjectCommit = binding.value.subjectCommit
  let moduleSha256 = binding.value.moduleSha256

  let status = grounds{"requirementSourceStatus"}.getStr("")
  if status notin requirementSourceStatuses:
    return err("grounds file: requirementSourceStatus must be one of " &
      $requirementSourceStatuses & ", got '" & status & "'")
  if not isStringArray(grounds{"requirementSourceRefs"}, allowEmpty = false):
    return err("grounds file: requirementSourceRefs must be >= 1 non-empty " &
      "reference string")

  let quartet = validateGroundsQuartet(grounds, subjectCommit)
  if quartet.isErr:
    return err(quartet.error)
  let confirmation = validateGroundsConfirmation(grounds)
  if confirmation.isErr:
    return err(confirmation.error)
  let categories = validateGroundsCategories(grounds)
  if categories.isErr:
    return err(categories.error)
  let corroboration = validateGroundsCorroboration(grounds, specId)
  if corroboration.isErr:
    return err(corroboration.error)
  let machineRef = corroboration.value
  let digest = validateGroundsDigest(grounds)
  if digest.isErr:
    return err(digest.error)

  ok(GroundsFileView(
    specId: specId,
    subjectCommit: subjectCommit,
    moduleSha256: moduleSha256,
    requirementSourceStatus: status,
    corroborationSpecId: machineRef{"specId"}.getStr(""),
    corroborationVerdict: machineRef{"verdict"}.getStr(""),
    corroborationReplayVerdict: machineRef{"replayVerdict"}.getStr("")))

{.pop.}
