import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}

## BYO-Agent propositions intake — `ax prove --proposals <path>` (Phase 5.1).
##
## Contract: docs/spec/byo_agent_proposition_contract.md (schema v2). The
## propositions document is an external agent's declaration: which catalog
## specIds it adopts or which claim it states (logic + expression), over
## which claimed subject, with which target symbols to verify.
##
## Intake is a fail-closed pre-processing gate, not an engine lane:
## 1. load + JSON-parse the file (document byte bound),
## 2. validate the closed schema (schema_version == 2; per-proposition id
##    required and unique; lane-form {specId} or claim-form {logic,
##    expression} — exactly one),
## 3. cross-check the subject claims against AXIOM_SUBJECT_REPOSITORY /
##    AXIOM_SUBJECT_COMMIT when those env are set (unset env — local mode —
##    accepts the recorded claims without cross-validation),
## 4. resolve every lane-form specId against the committed catalog via the
##    registry loader (the single authority for spec documents). An
##    unresolvable specId is NOT a document rejection — it seeds that
##    proposition's INCAPABLE{UNKNOWN_SPEC} capability fact (decided here,
##    while the catalog is in hand) and installs no overlay for it; the
##    other propositions' overlays install as before,
## 5. install the runtime registry overlay under $AXIOM_STATE_DIR/specs/:
##    the resolved catalog document with subject.repository re-bound to the
##    authoritative slug; subject.commit / governedBlobSha256 pins stay
##    byte-identical (the engine's existing pin verification owns the
##    actual-checkout comparison),
## 6. project the propositions' single target onto the existing --target
##    filter (the engine consumes one target per run; propositions naming
##    multiple distinct targets are rejected — one prove run per target).
##
## Document-level rejections carry a machine-greppable reason code and
## surface as CliOutcome.INVALID_INPUT (exit 3) at the CLI boundary:
##   BAD_SCHEMA / NO_PROPOSALS / SUBJECT_MISMATCH / MULTIPLE_TARGETS.
## Per-proposition capability facts are NOT rejections: they ride the
## intake result as INCAPABLE seeds {id → reason} and surface in the
## report's display.propositions[] rollup (runs with INCAPABLE propositions
## complete in-contract, exit 0/1).

import std/[json, options, os, strutils]
import cli/external_subject_registry
import core/axiom_pragmas
import core/results

const supportedPropositionsSchemaVersion* = 2
  ## The only propositions schema_version this engine version validates.

const maxPropositionsDocumentBytes* = 262144
  ## The propositions document's byte bound (BAD_SCHEMA on violation).

const maxPropositionsPerDocument* = 32
  ## The propositions array's count bound (BAD_SCHEMA on violation).

const maxPropositionIdLength* = 128
  ## proposition.id's character bound (BAD_SCHEMA on violation).

const maxPropositionLogicLength* = 128
  ## claim-form proposition.logic's character bound (BAD_SCHEMA on violation).

const maxPropositionExpressionLength* = 4096
  ## claim-form proposition.expression's character bound (BAD_SCHEMA).

const subjectRepositoryEnv* = "AXIOM_SUBJECT_REPOSITORY"
  ## When set, must equal the propositions document's subject.repository
  ## (SUBJECT_MISMATCH otherwise) and supplies the authoritative overlay slug.

const subjectCommitEnv* = "AXIOM_SUBJECT_COMMIT"
  ## When set, must equal the propositions document's subject.commit
  ## (SUBJECT_MISMATCH otherwise).

type
  PropositionForm* = enum
    pfLane      ## lane-form: catalog specId + target (overlay-parameterized)
    pfClaim     ## claim-form: logic + expression + target (never verified in v1)

  PropositionCapabilityReason* = enum
    ## The closed per-proposition INCAPABLE reason taxonomy (contract §3).
    ## The producer (intake/dispatch) decides; the display layer projects
    ## the spelling via `$` — never a re-derivation.
    pcrUnknownSpec = "UNKNOWN_SPEC"
    pcrLaneNotEquipped = "LANE_NOT_EQUIPPED"
    pcrUnsupportedLogic = "UNSUPPORTED_LOGIC"

  PropositionInput* = object
    id*: string
    target*: string
    form*: PropositionForm
    specId*: string      ## lane-form payload ("" on claim-form)
    logic*: string       ## claim-form payload ("" on lane-form)
    expression*: string  ## claim-form payload ("" on lane-form)
    sourceFile*: string
    sourceLine*: int
    explanation*: string

  PropositionsDocument* = object
    subjectRepository*: string
    subjectCommit*: string
    agentId*: string
    agentVersion*: string
    propositions*: seq[PropositionInput]

  PropositionIntake* = object
    subjectRepository*: string
    subjectCommit*: string
    agentId*: string
    agentVersion*: string
    target*: string                       ## the propositions' single run target
    overlaySpecRelPaths*: seq[string]     ## installed under $AXIOM_STATE_DIR/specs/
    propositions*: seq[PropositionInput]  ## the retained parsed propositions
    incapableSeeds*: seq[tuple[id: string; reason: PropositionCapabilityReason]]
      ## Per-proposition capability facts decided at intake (UNKNOWN_SPEC —
      ## specId unresolvable in the catalog; UNSUPPORTED_LOGIC — claim-form,
      ## no parser in v1). LANE_NOT_EQUIPPED is decided at display-build time
      ## (dispatch-winner absence) and never appears here.

func isFortyHexClaim(s: string): bool {.raises: [].} =
  s.len == 40 and s.allCharsInSet({'0'..'9', 'a'..'f', 'A'..'F'})

proc parseOptionalProvenance(p: JsonNode):
    Result[tuple[sourceFile: string, sourceLine: int, explanation: string], string] {.
    raises: [].} =
  ## Optional source_location {file, line} + explanation — shape discipline
  ## only; absent fields parse to the empty/0 defaults.
  let loc = p{"source_location"}
  var sourceFile = ""
  var sourceLine = 0
  if not loc.isNil:
    if loc.kind != JObject:
      return err("BAD_SCHEMA: proposition.source_location must be an object")
    let file = loc{"file"}
    if file.isNil or file.kind != JString or file.getStr("").len == 0:
      return err("BAD_SCHEMA: proposition.source_location.file must be a non-empty string")
    let line = loc{"line"}
    if line.isNil or line.kind != JInt or line.getInt() < 0:
      return err("BAD_SCHEMA: proposition.source_location.line must be a non-negative integer")
    sourceFile = file.getStr("")
    sourceLine = line.getInt()
  let explanation = p{"explanation"}
  var explanationValue = ""
  if not explanation.isNil:
    if explanation.kind != JString:
      return err("BAD_SCHEMA: proposition.explanation must be a string")
    explanationValue = explanation.getStr("")
  ok((sourceFile: sourceFile, sourceLine: sourceLine, explanation: explanationValue))

proc parsePropositionPayload(id: JsonNode; specId, logic, expression: JsonNode):
    Result[tuple[form: PropositionForm, specId, logic, expression: string], string] {.
    raises: [].} =
  ## lane/claim form discipline (contract §2): exactly one form — both or
  ## neither is BAD_SCHEMA; the claim payload bounds apply.
  let hasSpecId = not specId.isNil
  let hasClaimForm = not logic.isNil or not expression.isNil
  if hasSpecId and hasClaimForm:
    return err("BAD_SCHEMA: proposition \"" & id.getStr("") &
      "\" must be lane-form (specId) or claim-form (logic + expression), not both")
  var form = pfLane
  var specIdValue = ""
  var logicValue = ""
  var expressionValue = ""
  if hasSpecId:
    if specId.kind != JString or specId.getStr("").len == 0:
      return err("BAD_SCHEMA: proposition.specId must be a non-empty string")
    specIdValue = specId.getStr("")
  elif hasClaimForm:
    if logic.isNil or logic.kind != JString or logic.getStr("").len == 0:
      return err("BAD_SCHEMA: claim-form proposition.logic must be a non-empty string")
    if logic.getStr("").len > maxPropositionLogicLength:
      return err("BAD_SCHEMA: proposition.logic exceeds " &
        $maxPropositionLogicLength & " characters")
    if expression.isNil or expression.kind != JString or expression.getStr("").len == 0:
      return err("BAD_SCHEMA: claim-form proposition.expression must be a non-empty string")
    if expression.getStr("").len > maxPropositionExpressionLength:
      return err("BAD_SCHEMA: proposition.expression exceeds " &
        $maxPropositionExpressionLength & " characters")
    form = pfClaim
    logicValue = logic.getStr("")
    expressionValue = expression.getStr("")
  else:
    return err("BAD_SCHEMA: proposition \"" & id.getStr("") &
      "\" must declare lane-form specId or claim-form logic + expression")
  ok((form: form, specId: specIdValue, logic: logicValue, expression: expressionValue))

proc parsePropositionEntry(p: JsonNode; seenIds: var seq[string]):
    Result[PropositionInput, string] {.raises: [].} =
  ## Closed-shape validation of ONE proposition entry — id uniqueness rides
  ## the caller's seenIds; lane/claim form discipline per contract §2.
  if p.kind != JObject:
    return err("BAD_SCHEMA: each proposition must be an object")
  let id = p{"id"}
  if id.isNil or id.kind != JString or id.getStr("").len == 0:
    return err("BAD_SCHEMA: proposition.id must be a non-empty string")
  if id.getStr("").len > maxPropositionIdLength:
    return err("BAD_SCHEMA: proposition.id exceeds " & $maxPropositionIdLength & " characters")
  if id.getStr("") in seenIds:
    return err("BAD_SCHEMA: duplicate proposition.id \"" & id.getStr("") &
      "\" — proposition ids must be unique within the document")
  seenIds.add(id.getStr(""))
  let target = p{"target"}
  if target.isNil or target.kind != JString or target.getStr("").len == 0:
    return err("BAD_SCHEMA: proposition.target must be a non-empty string (--target syntax)")
  let payloadRes = parsePropositionPayload(id, p{"specId"}, p{"logic"}, p{"expression"})
  if payloadRes.isErr():
    return err(payloadRes.error)
  let payload = payloadRes.get
  let provenanceRes = parseOptionalProvenance(p)
  if provenanceRes.isErr():
    return err(provenanceRes.error)
  let provenance = provenanceRes.get
  ok(PropositionInput(
    id: id.getStr(""), target: target.getStr(""), form: payload.form,
    specId: payload.specId, logic: payload.logic, expression: payload.expression,
    sourceFile: provenance.sourceFile, sourceLine: provenance.sourceLine,
    explanation: provenance.explanation))

proc parseDocumentEnvelope(raw: JsonNode):
    Result[tuple[subjectRepository, subjectCommit, agentId, agentVersion: string], string] {.
    raises: [].} =
  ## schema_version + subject + agent envelope checks — shape and type
  ## discipline only (contract §2).
  if raw.isNil or raw.kind != JObject:
    return err("BAD_SCHEMA: top-level propositions document must be a JSON object")
  let schemaVersion = raw{"schema_version"}
  if schemaVersion.isNil or schemaVersion.kind != JInt:
    return err("BAD_SCHEMA: schema_version must be a JSON integer")
  if schemaVersion.getInt() != supportedPropositionsSchemaVersion:
    return err("BAD_SCHEMA: schema_version must be " &
      $supportedPropositionsSchemaVersion & ", got " & $schemaVersion.getInt())
  let subject = raw{"subject"}
  if subject.isNil or subject.kind != JObject:
    return err("BAD_SCHEMA: subject object is required")
  let repository = subject{"repository"}
  if repository.isNil or repository.kind != JString or repository.getStr("").len == 0:
    return err("BAD_SCHEMA: subject.repository must be a non-empty string")
  let commit = subject{"commit"}
  if commit.isNil or commit.kind != JString or not isFortyHexClaim(commit.getStr("")):
    return err("BAD_SCHEMA: subject.commit must be a 40-hex commit claim")
  let agent = raw{"agent"}
  if agent.isNil or agent.kind != JObject:
    return err("BAD_SCHEMA: agent object is required")
  let agentId = agent{"id"}
  if agentId.isNil or agentId.kind != JString or agentId.getStr("").len == 0:
    return err("BAD_SCHEMA: agent.id must be a non-empty string")
  let agentVersion = agent{"version"}
  if agentVersion.isNil or agentVersion.kind != JString or agentVersion.getStr("").len == 0:
    return err("BAD_SCHEMA: agent.version must be a non-empty string")
  ok((subjectRepository: repository.getStr(""), subjectCommit: commit.getStr(""),
      agentId: agentId.getStr(""), agentVersion: agentVersion.getStr("")))

func parsePropositionsSchema*(raw: JsonNode): Result[PropositionsDocument, string] {.
    raises: [].} =
  ## Closed-shape validation of one propositions intake document. Pure —
  ## shape and type discipline only; claim cross-check and catalog resolution
  ## stay in the I/O intake proc.
  let envelopeRes = parseDocumentEnvelope(raw)
  if envelopeRes.isErr():
    return err(envelopeRes.error)
  let propsNode = raw{"propositions"}
  if propsNode.isNil or propsNode.kind != JArray:
    return err("BAD_SCHEMA: propositions must be an array")
  var props: seq[PropositionInput] = @[]
  var seenIds: seq[string] = @[]
  for p in propsNode:
    let entryRes = parsePropositionEntry(p, seenIds)
    if entryRes.isErr():
      return err(entryRes.error)
    props.add(entryRes.get)
  if props.len == 0:
    return err("NO_PROPOSALS: propositions array is empty — at least one proposition is required")
  if props.len > maxPropositionsPerDocument:
    return err("BAD_SCHEMA: propositions array exceeds " &
      $maxPropositionsPerDocument & " entries, got " & $props.len)
  let env = envelopeRes.get
  ok(PropositionsDocument(
    subjectRepository: env.subjectRepository, subjectCommit: env.subjectCommit,
    agentId: env.agentId, agentVersion: env.agentVersion,
    propositions: props))

proc axiomStateDir*(): string {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The §10.3 state root, stripped; empty when unset. Same fail-closed
  ## pairing discipline as the --project handler in axiom_engine.
  let v = getEnv("AXIOM_STATE_DIR", "")
  if v.len > 0: v.strip() else: ""

proc runtimeOverlaySpecDir*(): string {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The runtime proposition-overlay spec directory: $AXIOM_STATE_DIR/specs
  ## when it exists, else "" (nothing to merge). Read-only probe — directory
  ## creation is ingestPropositionsFile's job, so a bare state root never
  ## fabricates an overlay source.
  let stateRoot = axiomStateDir()
  if stateRoot.len == 0: return ""
  let d = stateRoot / "specs"
  if dirExists(d): d else: ""

proc crossCheckSubjectClaims(doc: PropositionsDocument): Result[string, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Subject claim cross-check: env is authoritative when set; unset env
  ## (local mode) accepts the recorded claims per the contract. Returns the
  ## authoritative slug for the overlay re-binding.
  let envRepo = getEnv(subjectRepositoryEnv, "").strip()
  let envCommit = getEnv(subjectCommitEnv, "").strip()
  if envRepo.len > 0 and envRepo != doc.subjectRepository:
    return err("SUBJECT_MISMATCH: " & subjectRepositoryEnv & "=\"" & envRepo &
      "\" != propositions subject.repository=\"" & doc.subjectRepository & "\"")
  if envCommit.len > 0 and envCommit != doc.subjectCommit:
    return err("SUBJECT_MISMATCH: " & subjectCommitEnv & "=\"" & envCommit &
      "\" != propositions subject.commit=\"" & doc.subjectCommit & "\"")
  ok(if envRepo.len > 0: envRepo else: doc.subjectRepository)

proc resolvePropositionOverlays(doc: PropositionsDocument;
    catalog: ExternalSubjectRegistry; authoritativeSlug: string):
    tuple[overlays: seq[tuple[specRelPath: string, doc: JsonNode]],
          incapableSeeds: seq[tuple[id: string; reason: PropositionCapabilityReason]]] {.
    raises: [].} =
  ## Per-proposition resolution against the committed catalog: claim-form
  ## seeds UNSUPPORTED_LOGIC (no v1 parser), an unresolvable specId seeds
  ## UNKNOWN_SPEC (no overlay install), resolvable lane specs install the
  ## catalog document as a runtime overlay with subject.repository re-bound
  ## to the authoritative slug (subject.commit / blobSha256 pins copied
  ## byte-identical — the engine's pin verification owns the actual-checkout
  ## comparison; intake never rewrites a pin).
  var overlays: seq[tuple[specRelPath: string, doc: JsonNode]] = @[]
  var incapableSeeds: seq[tuple[id: string; reason: PropositionCapabilityReason]] = @[]
  var seenRelPaths: seq[string] = @[]
  for p in doc.propositions:
    case p.form
    of pfClaim:
      # v1 has no parser for any declared logic — the claim-form proposition
      # is an intake-decided capability fact, never a document rejection.
      incapableSeeds.add((p.id, pcrUnsupportedLogic))
    of pfLane:
      var entryOpt = none(RegistryEntry)
      for entry in catalog.entries:
        if entry.specId == p.specId:
          entryOpt = some(entry)
          break
      if entryOpt.isNone:
        # Unresolvable specIds are decided HERE, while the catalog is in
        # hand — an INCAPABLE{UNKNOWN_SPEC} seed for this proposition only;
        # no overlay install, the other propositions proceed unchanged.
        incapableSeeds.add((p.id, pcrUnknownSpec))
        continue
      let entry = entryOpt.get
      if entry.specRelPath in seenRelPaths:
        continue
      seenRelPaths.add(entry.specRelPath)
      var overlayDoc = entry.raw.copy()
      let subjectNode = overlayDoc{"subject"}
      if not subjectNode.isNil and subjectNode.kind == JObject:
        subjectNode["repository"] = %authoritativeSlug
      overlays.add((entry.specRelPath, overlayDoc))
  (overlays: overlays, incapableSeeds: incapableSeeds)

proc installRuntimeOverlays(
    overlays: seq[tuple[specRelPath: string, doc: JsonNode]];
    stateRoot: string): Result[seq[string], string] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Writes the runtime overlay documents under <stateRoot>/specs/ (fail-closed
  ## on any write failure); returns the installed relPaths in input order.
  var installed: seq[string] = @[]
  for (relPath, overlayDoc) in overlays:
    let outPath = stateRoot / "specs" / relPath
    try:
      createDir(outPath.parentDir)
      writeFile(outPath, pretty(overlayDoc) & "\n")
    except CatchableError as e:
      return err("cannot write runtime overlay spec (fail-closed): " & outPath &
        ": " & e.msg)
    installed.add(relPath)
  ok(installed)

func distinctPropositionTargets(doc: PropositionsDocument): seq[string] {.
    raises: [].} =
  ## One target per run: the engine's --target filter is scalar, and the
  ## dispatch lanes route a single target. Multiple distinct proposition
  ## targets are the caller's separate prove runs, not a silent partial run.
  var distinctTargets: seq[string] = @[]
  for p in doc.propositions:
    if p.target notin distinctTargets:
      distinctTargets.add(p.target)
  distinctTargets

func multipleTargetsError(targets: seq[string]): string {.raises: [].} =
  "MULTIPLE_TARGETS: propositions name " & $targets.len &
    " distinct targets (\"" & targets.join("\", \"") &
    "\") — ax prove consumes one --target per run; run one " &
    "ax prove --proposals invocation per target"

proc ingestPropositionsFile*(path: string;
    specDir: string = defaultExternalSubjectSpecDir;
    stateDirOverride: string = ""): Result[PropositionIntake, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## One propositions file → validated claims + installed runtime overlay.
  ## Fail-closed at every step; the reason-code contract lives in the module
  ## doc. `specDir` / `stateDirOverride` are loader seams for tests (the
  ## engine passes defaults); `stateDirOverride` bypasses AXIOM_STATE_DIR.
  var rawText = ""
  try:
    rawText = readFile(path)
  except CatchableError as e:
    return err("BAD_SCHEMA: cannot read propositions file " & path & ": " & e.msg)
  if rawText.len > maxPropositionsDocumentBytes:
    return err("BAD_SCHEMA: propositions document exceeds " &
      $maxPropositionsDocumentBytes & " bytes, got " & $rawText.len)
  var raw: JsonNode
  try:
    raw = parseJson(rawText)
  except CatchableError as e:
    return err("BAD_SCHEMA: propositions file is not valid JSON: " & e.msg)
  let docRes = parsePropositionsSchema(raw)
  if docRes.isErr():
    return err(docRes.error)
  let doc = docRes.get
  let slugRes = crossCheckSubjectClaims(doc)
  if slugRes.isErr():
    return err(slugRes.error)
  # specId resolution — the committed catalog, through the one deterministic
  # loader (envelope-validated entries; any catalog rejection fails the run
  # exactly as the engine's own load would).
  let catalogRes = loadExternalSubjectRegistry(specDir)
  if catalogRes.isErr():
    return err("propositions intake cannot resolve specIds: committed catalog " &
      "unavailable (fail-closed): " & catalogRes.error)
  let resolution = resolvePropositionOverlays(doc, catalogRes.get, slugRes.get)
  let distinctTargets = distinctPropositionTargets(doc)
  if distinctTargets.len > 1:
    return err(multipleTargetsError(distinctTargets))
  let stateRoot = if stateDirOverride.len > 0: stateDirOverride.strip()
                  else: axiomStateDir()
  if stateRoot.len == 0:
    return err("[AXIOM] --proposals requires AXIOM_STATE_DIR (fail-closed): " &
      "no runtime overlay destination")
  let installedRes = installRuntimeOverlays(resolution.overlays, stateRoot)
  if installedRes.isErr():
    return err(installedRes.error)
  ok(PropositionIntake(
    subjectRepository: doc.subjectRepository, subjectCommit: doc.subjectCommit,
    agentId: doc.agentId, agentVersion: doc.agentVersion,
    target: distinctTargets[0], overlaySpecRelPaths: installedRes.get,
    propositions: doc.propositions, incapableSeeds: resolution.incapableSeeds))
