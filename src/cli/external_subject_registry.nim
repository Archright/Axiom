import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
## VS-2 External-Subject Binding Registry — schema v2 envelope core (PR-0).
##
## SSOT: docs/design/vs2_external_subject_registry_spec_2026-10-24.md
## (§1 schema, §2 registry).
## PR-0 coexistence contract: this module owns the envelope TYPES, the
## deterministic loader, the CLOSED replay-template registry, the shared
## `verifySubjectBlobPin`, and the envelope rejection rules. PR-1 promoted
## the loader to the authoritative dispatch input for the FLIPPED lane
## (arithmetic-law — the engine's §2.7 adapter loop); PR-2 flips the second
## lane (constructed-gate) the same way; the four remaining lanes keep their
## legacy loads in `axiom_engine.nim` and this loader still feeds only the
## observability-only parity shadow for them.
##
## PR-2 also hosts the shared subject-pin/ownership/carrier validation kit
## (§3.7): the d2 validator trio (validateD2SubjectPin/validateD2Ownership/
## validateD2Carriers) folded here verbatim, the carrier half parameterized
## by the required carrier-name pair (the only difference between the d2 and
## bv copies). Each still-unflipped lane's own copy stays byte-untouched
## until its flip PR absorbs it.
##
## Fail-closed rules (HARD, §0.9): an unknown capability / presencePolicy /
## observation kind / templateId / slot token is an explicit load error —
## never a fallback, never a best-effort projection. Spec text can never
## reach harness source: a document names a `templateId` (a key into the
## engine-owned registry below); the template BODY never travels in JSON.
##
## PR-0 compatibility mapping (transitional, removed when the six
## config/spec documents carry the v2 envelope keys): a document WITHOUT a
## `capability` key is classified by `compatLaneEnvelopeProjection` — a
## deterministic, content-derived projection of the lane-shaped payload
## (adoption → body-carry/optional/10 …). A document WITH a `capability`
## key takes the strict v2 path and never sees the compat layer.
##
## The 2026-11-08 §1b prove-config rotation adds a second consumer: the
## `axiom_engine.nim` axiom.toml call-site resolves through the exported
## `findRepoRootStrict` seam below.

import std/[algorithm, json, options, os, strutils]
import core/results
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/trusted/env_access
import core/trusted/specification_artifact
import core/utils/repo_root
import infrastructure/logging_facade
import verification/counterexample_replay

proc findRepoRootStrict*(startDir: string = getAppDir()):
    Result[string, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Strict runtime root resolution for the catalog seam (VS-2 §2.3
  ## root-resolution amendment 2026-11-08; productization contract §1b;
  ## bytesview contract §3.1): `AXIOM_ROOT` env first, else the anchor walk
  ## up from `startDir` — the FIRST `.axiom_root` terminates.
  ## Unlike `core/utils/repo_root.findRepoRoot` there is NO legacy
  ## one-level-up fallback: a tree-external anchor miss is an error
  ## (fail-closed), never `parentDir(startDir)` and never a CWD-relative
  ## `""` join (Q-013: `parentDir("/")` returns `""` and `"" / anchor`
  ## probes the CWD, so the walk below breaks BEFORE probing an empty
  ## path). Deliberately a call-site sibling of the loader seam (the spec
  ## amendment's "call-site change rather than an engine redesign"), not a
  ## `src/core/` proc.
  let envRoot = getAxiomEnv(evRoot)
  if envRoot.len > 0:
    var norm = envRoot
    while norm.len > 1 and norm[^1] == '/':
      norm = norm[0 .. ^2]
    return ok(norm)
  var current = startDir
  for _ in 0..10:
    if current.len == 0:
      break
    try:
      if fileExists(current / axiomRoot):
        return ok(current)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    let parent = parentDir(current)
    if parent.len == 0 or parent == current:
      break
    current = parent
  err("catalog root unresolved (fail-closed): AXIOM_ROOT is unset and no " &
      ".axiom_root anchor found from \"" & startDir &
      "\" — a tree-external binary must set AXIOM_ROOT (productization " &
      "contract §1b, Q-013)")

proc resolveExternalSubjectSpecDir*(): Result[string, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The production spec directory, resolved at CALL TIME per the runtime
  ## root-resolution contract (VS-2 §2.3 root-resolution amendment
  ## 2026-11-08; productization contract §1b; bytesview contract §3.1):
  ## `AXIOM_ROOT` env first, else the STRICT anchor walk from the binary
  ## location (`findRepoRootStrict` — first `.axiom_root`
  ## terminates). A tree-external anchor miss is a catalog read failure,
  ## fail-closed — the legacy one-level-up fallback and the CWD-relative
  ## `""` join (Q-013) are both unreachable. Source-tree behavior is
  ## preserved: with `AXIOM_ROOT` unset and the binary inside the tree the
  ## walk reproduces the root the compile-time `repoRootConst()` join
  ## previously baked in. The loader seam itself (`specDir` as a parameter,
  ## REGISTRY_SPEC §4) is unchanged — a test still points it at
  ## tests/fixtures/spec_overlays/ with zero engine hooks.
  let rootRes = findRepoRootStrict()
  if rootRes.isErr():
    return err(rootRes.error)
  ok(rootRes.get / "config" / "spec")

proc resolvedExternalSubjectSpecDirOrEmpty(): string {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## String form of the seam for default-parameter positions: the resolved
  ## production spec directory, or "" when the anchor walk missed. "" is
  ## NEVER a joinable root — every consumer treats it as the fail-closed
  ## catalog read failure (`loadExternalSubjectRegistry` rejects an empty
  ## `specDir` outright; Q-013).
  let dirRes = resolveExternalSubjectSpecDir()
  if dirRes.isErr():
    return ""
  dirRes.get

template defaultExternalSubjectSpecDir*: string =
  ## The production spec directory — RUNTIME-resolved at each use (the
  ## S2b seam replacing the former `repoRootConst()` compile-time const,
  ## 2026-11-08). Used as a default-parameter adapter so parameter
  ## positions (`specDir: string = defaultExternalSubjectSpecDir`) compile
  ## unchanged and now evaluate the resolution at call time. The value is
  ## `resolvedExternalSubjectSpecDirOrEmpty()`: "" ⇒ tree-external anchor
  ## miss, fail-closed at the consumer — never joined (Q-013).
  resolvedExternalSubjectSpecDirOrEmpty()

const reservedExprSlot* = "<expr>"
  ## Reserved slot vocabulary for the VS-3 `write-read-roundtrip`
  ## observation kind. No v2 template and no v2 slot list may contain it
  ## (REGISTRY_SPEC §1.5 — a v2 document naming it is a load error).

type
  ExternalSubjectCapability* = enum
    capConstructedGate = "constructed-gate"
    capArithmeticLaw   = "arithmetic-law"
    capBodyCarry       = "body-carry"
    capTermSplice      = "term-splice"
    capBetaComposition = "beta-composition"

  PresencePolicy* = enum
    ppMandatory = "mandatory"
    ppOptional  = "optional"

  ReplayObservationKind* = enum
    obsRaiseBool      = "raise-bool"
    obsSingleCallInt  = "single-call-int"
    obsSingleCallBool = "single-call-bool"   ## v2: test-overlay only

  ReplaySpec* = object
    templateId*: string        ## closed registry key; source never travels in JSON
    importModule*: string      ## stated + recomputed + cross-checked (§1.6)
    observation*: ReplayObservationKind
    slots*: seq[string]        ## validated against the fixed vocabulary + positions

  ConstructedTargets* = object
    symbols*: seq[string]
    allowBare*: bool

  RegistryEntry* = object
    specRelPath*: string       ## normalized relative path under specDir (log/evidence identity)
    specId*: string            ## document label (NOT the computed SpecID — specIdentity)
    ruleId*: string            ## carried; never dispatched on (preserves today's semantics)
    precedence*: int           ## lower = earlier in the dispatch cascade
    presence*: PresencePolicy
    capability*: ExternalSubjectCapability
    governedModule*: string    ## envelope-derived governed module (overlap rule + pin wiring)
    governedSymbols*: seq[string]
    governedBlobSha256*: string ## "" = the payload declares no subject blob pin
    constructed*: Option[ConstructedTargets]
    replay*: Option[ReplaySpec]
    raw*: JsonNode             ## the full document; adapters validate their payload
                               ## from THIS node only (no second semantic source)

  ExternalSubjectRegistry* = object
    entries*: seq[RegistryEntry] ## sorted by (precedence, specRelPath) — total, deterministic

# ---------------------------------------------------------------------------
# The CLOSED replay-template registry (§1.5 rule 1)
# ---------------------------------------------------------------------------
# The template bodies live ONLY here (engine-owned). A spec document names a
# templateId; it never carries harness source. The legacy engine consts die
# at their lane's flip PR (bv in PR-1, d2 in PR-2 — the unit test pins each
# body as the literal the retired const held). Placeholders are the
# counterexample_replay consts (one shared definition with the renderer).

const replayTemplateD2GateRejectV1* = "import " & ReplayModulePlaceholder & "\n" &
  "var observedReject = false\n" &
  "try:\n" &
  "  discard Toml.decode(\"k = \\\"a\" & chr(" & ReplayValuePlaceholder & ") & \"b\\\"\", TomlValueRef)\n" &
  "except TomlError:\n" &
  "  observedReject = true\n" &
  "echo \"" & ReplayBeginMarker & "\"\n" &
  "echo $observedReject\n" &
  "echo \"" & ReplayEndMarker & "\"\n"
  ## raise-bool: echoes true iff the original decoder RAISED on a document
  ## embedding the raw byte chr(<lit>). The sole d2 harness body since the
  ## PR-2 lane flip (the engine stamps it via
  ## `replayTemplate(D2AgentReplayTemplateId)`).

const replayTemplateBvSliceLenV1* = "import " & ReplayModulePlaceholder & "\n" &
  "var bv = BytesView.init(@[byte 1, 2, 3, 4, 5, 6])\n" &
  "echo \"" & ReplayBeginMarker & "\"\n" &
  "echo $(bv.toOpenArray(1, " & ReplayValuePlaceholder & ").len)\n" &
  "echo \"" & ReplayEndMarker & "\"\n"
  ## single-call-int: echoes the integer result of ONE call through the
  ## subject's public API. The sole bv harness body since the PR-1 lane flip
  ## (the engine stamps it via `replayTemplate(BvSliceLenReplayTemplateId)`).

const replayTemplateSingleCallBoolV1* = "import " & ReplayModulePlaceholder & "\n" &
  "echo \"" & ReplayBeginMarker & "\"\n" &
  "echo $(gateAccept(" & ReplayValuePlaceholder & "))\n" &
  "echo \"" & ReplayEndMarker & "\"\n"
  ## single-call-bool: echoes the bool result of ONE call (no exception
  ## coupling). v2 declares the kind for the P0-1 test overlay only — no
  ## production lane uses it yet (REGISTRY_SPEC §1.5).

proc replayTemplate*(templateId: string): Result[string, string] {.
    raises: [], axiomDecision.} =
  ## The closed template registry. Unknown id → explicit UNKNOWN error —
  ## never synthesized text.
  case templateId
  of "d2-gate-reject-v1": ok(replayTemplateD2GateRejectV1)
  of "bv-slice-len-v1": ok(replayTemplateBvSliceLenV1)
  of "single-call-bool-v1": ok(replayTemplateSingleCallBoolV1)
  else:
    err("UNKNOWN replay templateId \"" & templateId &
      "\" — the closed registry has no such template (fail-closed)")

# ---------------------------------------------------------------------------
# Shared subject-pin byte verification (§2.4) — PR-0 wired this ONE proc into
# the registry path beside the three per-lane pin procs; PR-1/PR-2 folded the
# bv/d2 lane bodies into delegation, PR-3 the sidecar body. The byte-verify
# logic has exactly one definition from here on.
# ---------------------------------------------------------------------------

type SubjectPinMismatchWording* = enum
  ## The blob-mismatch diagnostic's subject voice. The three retired lane
  ## bodies shared every byte of the mismatch message EXCEPT the subject
  ## noun phrase (the d2/bv overlays say "the overlay … the claim"; the
  ## sidecar's adoption record says "adoption … the proposition"), and the
  ## unmodified lane suites are the byte-identity proof — so the shared proc
  ## carries both wordings, closed, and the default keeps the PR-1/PR-2
  ## messages byte-identical.
  spwOverlayPins     ## "the overlay does not bind this subject tree … the overlay pins … — the claim was not adopted for these bytes"
  spwAdoptionRecord  ## "adoption does not bind this subject tree … the adoption record pins … — the proposition was not adopted for these bytes"

const subjectPinMismatchPhrases: array[SubjectPinMismatchWording, tuple[
    binder, pinNoun, notAdopted: string]] = [
  ("the overlay does not bind this subject ",
   "the overlay pins",
   " — the claim was not adopted for these bytes"),
  ("adoption does not bind this subject ",
   "the adoption record pins",
   " — the proposition was not adopted for these bytes")]
  ## The mismatch phrases per wording, table-selected (the retired lane
  ## bodies' exact bytes; a table lookup, not a case split — the module's
  ## branch counts stay where the baseline anchors them).

proc verifySubjectBlobPin*(lane: string; moduleRelPath: string;
    expectedBlobSha256: string; subjectRoot: string;
    wording: SubjectPinMismatchWording = spwOverlayPins): Result[bool, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## ONE pin-verify generalizing verifyLibp2pBytesviewSubjectPin /
  ## verifyTomlD2AgentSubjectPin / verifySidecarSubjectPin (the common
  ## logic those three share verbatim). `lane` feeds only the error-message
  ## prefix; `wording` selects the mismatch subject voice (default = the
  ## overlay wording the d2/bv lanes and the registry tests pin), preserving
  ## every lane's diagnostic byte-for-byte.
  ##   module absent under subjectRoot → ok(false) (binding inert on trees
  ##                                     it does not govern)
  ##   unreadable                      → err (fail-closed)
  ##   sha256Hex(bytes) != expected    → err (blob mismatch — not adopted
  ##                                     for these bytes)
  ##   else                            → ok(true)
  let moduleAbs = subjectRoot / moduleRelPath
  if not fileExists(moduleAbs):
    return ok(false)
  var bytes = ""
  try:
    bytes = readFile(moduleAbs)
  except CatchableError as e:
    return err(lane & " subject pin: the governed module exists but is " &
      "unreadable (fail-closed): " & moduleAbs & ": " & e.msg)
  let measured = sha256Hex(bytes)
  if measured != expectedBlobSha256:
    let phrases = subjectPinMismatchPhrases[wording]
    return err(lane & " subject pin: " & phrases.binder &
      "tree (blob mismatch): " & moduleAbs & " hashes to " & measured &
      ", " & phrases.pinNoun & " " & expectedBlobSha256 & phrases.notAdopted)
  ok(true)

# ---------------------------------------------------------------------------
# Shared subject-pin/ownership/carrier validation kit (§3.7) — the d2/bv
# validator trios were ~199 duplicated lines; the d2 copy folds here at its
# flip PR (PR-2) and the lane validator delegates. The carrier half is
# parameterized by the required carrier-name pair — the only difference
# between the d2 and bv copies — so every rejection message stays
# byte-identical to the retired per-lane bodies. Each still-unflipped
# lane's own copy stays byte-untouched until its flip PR absorbs it.
# ---------------------------------------------------------------------------

proc validateSubjectPinObject*(subject: JsonNode): Result[
    tuple[modulePath: string; symbols: seq[string]; blobSha256: string],
    string] {.raises: [].} =
  ## Fail-closed subject pin: module + symbols, and the exact-commit binding
  ## fields (repository, commit, sourceLines, blobSha256) present and
  ## well-formed — the claim names ONE immutable subject state.
  if subject.isNil or subject.kind != JObject:
    return err("spec overlay: subject object required")
  let modulePath = subject{"module"}.getStr("")
  let symbolsNode = subject{"symbols"}
  if modulePath.len == 0 or symbolsNode.isNil or symbolsNode.kind != JArray or
      symbolsNode.len < 1:
    return err("spec overlay: subject.module and >= 1 subject.symbols required")
  var symbols: seq[string]
  for s in symbolsNode:
    if s.kind != JString or s.getStr("").len == 0:
      return err("spec overlay: subject.symbols entries must be non-empty strings")
    symbols.add(s.getStr(""))
  for field in ["repository", "commit", "sourceLines"]:
    if subject{field}.getStr("").len == 0:
      return err("spec overlay: subject." & field & " is required (exact-commit pin)")
  let blob = subject{"blobSha256"}.getStr("")
  if blob.len != 64 or not blob.allCharsInSet(
      {'0'..'9', 'a'..'f', 'A'..'F'}):
    return err("spec overlay: subject.blobSha256 must be a 64-hex digest")
  ok((modulePath, symbols, blob))

proc validateOwnershipObject*(node: JsonNode): Result[void, string] {.raises: [].} =
  ## Fail-closed adoption record: the adopted-content provenance and the
  ## adoption act must both be named — an overlay without them would claim
  ## verified-by-nobody content.
  let owner = node{"claimOwnership"}
  if owner.isNil or owner.kind != JObject:
    return err("spec overlay: claimOwnership object required")
  for field in ["owner", "contract", "adoptionRef", "provenance"]:
    if owner{field}.getStr("").len == 0:
      return err("spec overlay: claimOwnership." & field & " is required " &
        "(adoption authority record)")
  if node{"description"}.getStr("").len == 0:
    return err("spec overlay: description is required (the claim's prose)")
  for field in ["semanticCaveats", "nonClaims"]:
    let arr = node{field}
    if arr.isNil or arr.kind != JArray or arr.len < 1:
      return err("spec overlay: " & field & " must be a non-empty array")
    for e in arr:
      if e.kind != JString or e.getStr("").len == 0:
        return err("spec overlay: " & field & " entries must be non-empty strings")
  Result[void, string](ok: true)

proc validateCarrierPair*(node: JsonNode; defectCarrierName,
    controlCarrierName: string): Result[tuple[
    defectSymbol, defectLines, controlSymbol, controlLines: string], string] {.
    raises: [].} =
  ## Fail-closed carrier grounding: exactly one defect and one control
  ## carrier, named by the binding's kernel names (the parameters — the
  ## lane's carrier-name consts), each with a non-empty grounding symbol +
  ## lines. The clause semantics live only in canonicalSpecIR — this block
  ## is provenance metadata, and the validator requires the two blocks to
  ## name the SAME carriers (no second semantic source).
  let carriers = node{"carriers"}
  if carriers.isNil or carriers.kind != JArray or carriers.len != 2:
    return err("spec overlay: exactly 2 carriers (defect + control) required")
  var seen: array[2, bool]
  var defectSymbol, defectLines, controlSymbol, controlLines = ""
  for c in carriers:
    if c.kind != JObject:
      return err("spec overlay: carrier entries must be objects")
    let name = c{"name"}.getStr("")
    let kind = c{"kind"}.getStr("")
    let gs = c{"groundingSymbol"}.getStr("")
    let gl = c{"groundingLines"}.getStr("")
    if gs.len == 0 or gl.len == 0:
      return err("spec overlay: carrier " & name &
        " needs groundingSymbol and groundingLines")
    if c{"grounding"}.getStr("").len == 0:
      return err("spec overlay: carrier " & name & " needs a grounding note")
    case kind
    of "defect":
      if name != defectCarrierName:
        return err("spec overlay: the defect carrier must be named " &
          defectCarrierName)
      if seen[0]:
        return err("spec overlay: duplicate defect carrier")
      seen[0] = true
      defectSymbol = gs
      defectLines = gl
    of "control":
      if name != controlCarrierName:
        return err("spec overlay: the control carrier must be named " &
          controlCarrierName)
      if seen[1]:
        return err("spec overlay: duplicate control carrier")
      seen[1] = true
      controlSymbol = gs
      controlLines = gl
    else:
      return err("spec overlay: carrier kind must be defect or control")
  if not (seen[0] and seen[1]):
    return err("spec overlay: exactly one defect and one control carrier required")
  ok((defectSymbol, defectLines, controlSymbol, controlLines))

proc entryFor*(reg: ExternalSubjectRegistry;
    capability: ExternalSubjectCapability): Option[RegistryEntry] {.raises: [].} =
  ## Direct-consumer accessor (probeSubjectIdentity / buildBugVerdictDisplayJson
  ## rewire at their flip PR). Returns the FIRST entry with the capability in
  ## (precedence, specRelPath) order. PR-0 note: two body-carry lanes exist
  ## (sidecar prec 10, cout prec 20) — consumers that need one specific
  ## payload must discriminate on the payload (raw node), which is what the
  ## §2.8 rewiring does; this accessor alone cannot.
  for entry in reg.entries:
    if entry.capability == capability:
      return some(entry)
  none(RegistryEntry)

func normalizedRelativePath(path: string): string {.raises: [].} =
  ## Forward slashes, no `./` — the enumeration identity for logs/evidence.
  ## The PR-0 enumeration is the specDir's immediate children, so the
  ## normalized relative path is the final path component (raise-free).
  let rel = lastPathPart(path).replace('\\', '/')
  if rel.startsWith("./"): rel[2 ..^ 1] else: rel

# ---------------------------------------------------------------------------
# Envelope parsing helpers — every rejection names the rule (fail-closed)
# ---------------------------------------------------------------------------

func isHexDigest(s: string; length: int): bool {.raises: [].} =
  s.len == length and s.allCharsInSet({'0'..'9', 'a'..'f', 'A'..'F'})

func parseCapabilityTag(s: string): Option[ExternalSubjectCapability] {.raises: [].} =
  ## The closed 5-kind discriminator. Any other value names a claim this
  ## engine version cannot state → explicit UNKNOWN (same posture as
  ## SidecarGrammarV1).
  case s
  of $capConstructedGate: some(capConstructedGate)
  of $capArithmeticLaw: some(capArithmeticLaw)
  of $capBodyCarry: some(capBodyCarry)
  of $capTermSplice: some(capTermSplice)
  of $capBetaComposition: some(capBetaComposition)
  else: none(ExternalSubjectCapability)

func parsePresenceTag(s: string): Option[PresencePolicy] {.raises: [].} =
  case s
  of $ppMandatory: some(ppMandatory)
  of $ppOptional: some(ppOptional)
  else: none(PresencePolicy)

func parseObservationTag(s: string): Option[ReplayObservationKind] {.raises: [].} =
  ## The CLOSED 3-kind grammar (§1.5). `write-read-roundtrip` is the named
  ## FUTURE kind — a v2 document declaring it gets the explicit UNKNOWN
  ## error like any other unknown kind.
  case s
  of $obsRaiseBool: some(obsRaiseBool)
  of $obsSingleCallInt: some(obsSingleCallInt)
  of $obsSingleCallBool: some(obsSingleCallBool)
  else: none(ReplayObservationKind)

func derivedReplayImportModule(capability: ExternalSubjectCapability;
    modulePath: string): Result[string, string] {.raises: [].} =
  ## The §1.6 derivation, recomputed from subject.module: constructed-gate →
  ## the module's parent directory (toml_serialization/lexer.nim →
  ## toml_serialization); arithmetic-law → the module path without its
  ## extension (libp2p/utils/bytesview.nim → libp2p/utils/bytesview).
  case capability
  of capConstructedGate:
    let dir = splitFile(modulePath).dir
    if dir.len == 0 or dir == ".":
      err("subject.module must name a module inside a package directory " &
        "(replay import derivation): " & modulePath)
    else:
      ok(dir.lastPathPart())
  of capArithmeticLaw:
    let parts = splitFile(modulePath)
    if parts.name.len == 0:
      err("subject.module must name a Nim module file (replay import derivation): " &
        modulePath)
    elif parts.dir.len == 0 or parts.dir == ".":
      ok(parts.name)
    else:
      ok(parts.dir / parts.name)
  else:
    err("capability " & $capability & " stamps no replay harness in v2 — " &
      "a replay block is a load error here")

func declaredSlotsValid(kind: ReplayObservationKind; slots: seq[string];
    reason: var string): bool {.raises: [].} =
  ## Position-constrained slot vocabulary: exactly ["<module>", "<lit>"] —
  ## the kind's declared positions in v2. `<expr>` has NO v2 position
  ## (reserved for VS-3); any unknown token, wrong count or wrong order is
  ## an explicit `illegal slot` error (§1.5 rule 2).
  let declared = @["<module>", "<lit>"]
  for tok in slots:
    if tok == reservedExprSlot:
      reason = "illegal slot \"" & reservedExprSlot &
        "\" — reserved vocabulary, no v2 position"
      return false
    if tok notin declared:
      reason = "illegal slot \"" & tok & "\""
      return false
  if slots != declared:
    reason = "replay.observation.slots for " & $kind &
      " must be exactly [\"<module>\", \"<lit>\"] (declared positions)"
    return false
  true

func templateBodyStructurallyValid(body: string; templateId: string;
    reason: var string): bool {.raises: [].} =
  ## Structural anti-injection checks on the ENGINE-OWNED template body:
  ## no `<expr>` anywhere; the `<module>` and `<lit>` placeholders each
  ## occur exactly once (the renderer's contract).
  if body.contains(reservedExprSlot):
    reason = "replay template \"" & templateId & "\" contains " &
      reservedExprSlot & " — reserved vocabulary, a v2 template must not"
    return false
  if body.count(ReplayModulePlaceholder) != 1:
    reason = "replay template \"" & templateId & "\" must contain " &
      ReplayModulePlaceholder & " exactly once (leading import slot)"
    return false
  if body.count(ReplayValuePlaceholder) != 1:
    reason = "replay template \"" & templateId & "\" must contain " &
      ReplayValuePlaceholder & " exactly once (observed-call argument slot)"
    return false
  true

func extractGoverned(raw: JsonNode;
    module: var string; symbols: var seq[string]; blob: var string): Result[void, string] {.
    raises: [].} =
  ## The entry's governed (module, symbol) set + declared blob pin, from the
  ## payload shape: an adoption record governs its adoption.subject key; a
  ## subject object governs subject.module + subject.symbols. The blob is
  ## read from wherever the payload declares it (subject.blobSha256 or
  ## adoption.subject.blobSha256) and format-checked at load when present.
  let adoptionSubject = raw{"adoption"}{"subject"}
  if not adoptionSubject.isNil and adoptionSubject.kind == JObject:
    module = adoptionSubject{"module"}.getStr("")
    let symbol = adoptionSubject{"symbol"}.getStr("")
    if module.len == 0 or symbol.len == 0:
      return err("adoption.subject.module and adoption.subject.symbol are required")
    symbols = @[symbol]
    blob = adoptionSubject{"blobSha256"}.getStr("")
  else:
    let subject = raw{"subject"}
    if subject.isNil or subject.kind != JObject:
      return err("subject object required")
    module = subject{"module"}.getStr("")
    let symbolsNode = subject{"symbols"}
    if module.len == 0 or symbolsNode.isNil or symbolsNode.kind != JArray or
        symbolsNode.len < 1:
      return err("subject.module and >= 1 subject.symbols required")
    for s in symbolsNode:
      if s.kind != JString or s.getStr("").len == 0:
        return err("subject.symbols entries must be non-empty strings")
      symbols.add(s.getStr(""))
    blob = subject{"blobSha256"}.getStr("")
  if blob.len > 0 and not isHexDigest(blob, 64):
    return err("malformed pin: subject blobSha256 must be a 64-hex digest, got " &
      $blob.len & " chars")
  Result[void, string](ok: true)

func compatLaneEnvelopeProjection(raw: JsonNode): Result[
    tuple[capability: ExternalSubjectCapability, presence: PresencePolicy,
      precedence: int], string] {.raises: [].} =
  ## PR-0 TRANSITIONAL compatibility mapping (deleted when the six
  ## config/spec documents carry the v2 envelope keys): classifies a
  ## lane-shaped payload by deterministic content discriminators and
  ## derives the (capability, presencePolicy, precedence) triple the
  ## audit-verified lane table pins (REGISTRY_SPEC §1.2-§1.4). The
  ## discriminators are payload-shape facts, not names:
  ##   adoption object              → body-carry, optional, 10 (sidecar)
  ##   claimConstant object         → body-carry, mandatory, 20 (C_out)
  ##   theorem + a ` mod ` clause   → term-splice, mandatory, 40 (rem)
  ##   theorem (no mod clause)      → beta-composition, mandatory, 30 (sizing)
  ##   carriers + a ` != ` clause   → constructed-gate, optional, 50 (d2)
  ##   carriers (no ` != ` clause)  → arithmetic-law, optional, 60 (bv)
  ## No discriminator matches → explicit UNKNOWN error (fail-closed).
  let irNode = raw{"canonicalSpecIR"}
  var clauses: seq[string]
  if not irNode.isNil and irNode.kind == JArray:
    for c in irNode:
      if c.kind == JString:
        clauses.add(c.getStr(""))
  var hasModClause = false
  var hasExclusionClause = false
  for clause in clauses:
    if clause.contains(" mod "): hasModClause = true
    if clause.contains(" != "): hasExclusionClause = true
  if not raw{"adoption"}.isNil and raw{"adoption"}.kind == JObject:
    ok((capBodyCarry, ppOptional, 10))
  elif not raw{"claimConstant"}.isNil and raw{"claimConstant"}.kind == JObject:
    ok((capBodyCarry, ppMandatory, 20))
  elif not raw{"carriers"}.isNil and raw{"carriers"}.kind == JArray:
    if hasExclusionClause:
      ok((capConstructedGate, ppOptional, 50))
    else:
      ok((capArithmeticLaw, ppOptional, 60))
  elif not raw{"theorem"}.isNil and raw{"theorem"}.kind == JObject:
    if hasModClause:
      ok((capTermSplice, ppMandatory, 40))
    else:
      ok((capBetaComposition, ppMandatory, 30))
  else:
    err("UNKNOWN capability — no v2 envelope key and no lane-shaped payload " &
      "discriminator (adoption/claimConstant/carriers/theorem) found; the " &
      "compatibility mapping refuses to guess (fail-closed)")

func envelopeEntryForNode(specRelPath: string; raw: JsonNode): Result[RegistryEntry, string] {.
    raises: [].} =
  ## One document → one envelope entry (§2.3 rules, in document order).
  # Authority first: the soExplicit pin runs at envelope level, exactly as
  # every legacy loader funnels through it.
  let specRes = explicitSpecFromOverlay(raw)
  if specRes.isErr():
    return err("spec overlay rejected: " & specRes.error)
  let specId = raw{"specId"}.getStr("")
  if specId.len == 0:
    return err("specId is required (document label)")
  # Capability: strict v2 key, else the PR-0 compat projection.
  var capability: ExternalSubjectCapability
  var presence: PresencePolicy
  var precedence = 0
  let capabilityNode = raw{"capability"}
  if capabilityNode.isNil:
    let compat = compatLaneEnvelopeProjection(raw)
    if compat.isErr():
      return err(compat.error)
    capability = compat.value.capability
    presence = compat.value.presence
    precedence = compat.value.precedence
  else:
    if capabilityNode.kind != JString:
      return err("capability must be a string")
    let capParsed = parseCapabilityTag(capabilityNode.getStr(""))
    if capParsed.isNone:
      return err("UNKNOWN capability \"" & capabilityNode.getStr("") &
        "\" — the closed discriminator has 5 kinds (constructed-gate, " &
        "arithmetic-law, body-carry, term-splice, beta-composition)")
    capability = capParsed.get
    let presenceNode = raw{"presencePolicy"}
    if presenceNode.isNil or presenceNode.kind != JString:
      return err("presencePolicy is required (mandatory | optional)")
    let presenceParsed = parsePresenceTag(presenceNode.getStr(""))
    if presenceParsed.isNone:
      return err("UNKNOWN presencePolicy \"" & presenceNode.getStr("") &
        "\" — must be mandatory | optional")
    presence = presenceParsed.get
    let precedenceNode = raw{"precedence"}
    if precedenceNode.isNil or precedenceNode.kind != JInt:
      return err("precedence must be a JSON integer")
    precedence = precedenceNode.getInt()
    if precedence < 0:
      return err("precedence must be >= 0, got " & $precedence)
  # Governed set + pin format (before the cross-checks that need it).
  var governedModule = ""
  var governedSymbols: seq[string] = @[]
  var governedBlob = ""
  let governedRes = extractGoverned(raw, governedModule, governedSymbols,
    governedBlob)
  if governedRes.isErr():
    return err(governedRes.error)
  # Replay envelope (§1.5-§1.6) — only the two harness-stamping capabilities
  # may declare one in v2.
  var replayOpt = none(ReplaySpec)
  let replayNode = raw{"replay"}
  if not replayNode.isNil and replayNode.kind == JObject:
    if capability notin {capConstructedGate, capArithmeticLaw}:
      return err("replay declared for capability " & $capability &
        " which stamps no replay harness in v2")
    let templateId = replayNode{"templateId"}.getStr("")
    let templateRes = replayTemplate(templateId)
    if templateRes.isErr():
      return err(templateRes.error)
    var bodyReason = ""
    if not templateBodyStructurallyValid(templateRes.get, templateId, bodyReason):
      return err(bodyReason)
    let importModule = replayNode{"importModule"}.getStr("")
    if importModule.len == 0:
      return err("replay.importModule is required")
    let obsNode = replayNode{"observation"}
    if obsNode.isNil or obsNode.kind != JObject:
      return err("replay.observation object required")
    let kindNode = obsNode{"kind"}
    if kindNode.isNil or kindNode.kind != JString:
      return err("replay.observation.kind must be a string")
    let obsParsed = parseObservationTag(kindNode.getStr(""))
    if obsParsed.isNone:
      return err("unknown observation kind \"" & kindNode.getStr("") &
        "\" — the closed v2 grammar is raise-bool | single-call-int | " &
        "single-call-bool (write-read-roundtrip is a named FUTURE kind)")
    let slotsNode = obsNode{"slots"}
    if slotsNode.isNil or slotsNode.kind != JArray:
      return err("replay.observation.slots must be an array")
    var slots: seq[string] = @[]
    for s in slotsNode:
      if s.kind != JString or s.getStr("").len == 0:
        return err("replay.observation.slots entries must be non-empty strings")
      slots.add(s.getStr(""))
    var slotReason = ""
    if not declaredSlotsValid(obsParsed.get, slots, slotReason):
      return err(slotReason)
    let derived = derivedReplayImportModule(capability, governedModule)
    if derived.isErr():
      return err(derived.error)
    if derived.get != importModule:
      return err("replay.importModule \"" & importModule &
        "\" != the recomputed derivation \"" & derived.get &
        "\" from subject.module (the statement must stay honest, §1.6)")
    replayOpt = some(ReplaySpec(
      templateId: templateId, importModule: importModule,
      observation: obsParsed.get, slots: slots))
  # Constructed-IR targets (§1.1) — only the two constructed-carrier
  # capabilities may declare them, and they must name exactly the payload's
  # carriers (no second semantic source).
  var constructedOpt = none(ConstructedTargets)
  let constructedNode = raw{"constructedIrTargets"}
  if not constructedNode.isNil and constructedNode.kind == JObject:
    if capability notin {capConstructedGate, capArithmeticLaw}:
      return err("constructedIrTargets declared for capability " & $capability &
        " which synthesizes no constructed carriers in v2")
    let symbolsNode = constructedNode{"symbols"}
    if symbolsNode.isNil or symbolsNode.kind != JArray or symbolsNode.len < 1:
      return err("constructedIrTargets.symbols must be a non-empty array")
    var targetSymbols: seq[string] = @[]
    for s in symbolsNode:
      if s.kind != JString or s.getStr("").len == 0:
        return err("constructedIrTargets.symbols entries must be non-empty strings")
      targetSymbols.add(s.getStr(""))
    for i in 0 ..< targetSymbols.len:
      for j in (i + 1) ..< targetSymbols.len:
        if targetSymbols[i] == targetSymbols[j]:
          return err("constructedIrTargets.symbols must be distinct, got duplicate \"" &
            targetSymbols[i] & "\"")
    var allowBare = false
    let allowBareNode = constructedNode{"allowBare"}
    if not allowBareNode.isNil:
      if allowBareNode.kind != JBool:
        return err("constructedIrTargets.allowBare must be a boolean")
      allowBare = allowBareNode.getBool()
    # Cross-check vs the payload's carriers: multiset equality.
    var carrierNames: seq[string] = @[]
    let carriersNode = raw{"carriers"}
    if not carriersNode.isNil and carriersNode.kind == JArray:
      for c in carriersNode:
        if c.kind != JObject:
          return err("carriers entries must be objects")
        carrierNames.add(c{"name"}.getStr(""))
    var sortedTargets = targetSymbols
    var sortedCarriers = carrierNames
    sortedTargets.sort()
    sortedCarriers.sort()
    if sortedTargets != sortedCarriers:
      return err("constructedIrTargets.symbols must equal the payload carriers " &
        "[\"" & carrierNames.join("\", \"") & "\"], got [\"" &
        targetSymbols.join("\", \"") & "\"]")
    constructedOpt = some(ConstructedTargets(
      symbols: targetSymbols, allowBare: allowBare))
  ok(RegistryEntry(
    specRelPath: specRelPath, specId: specId,
    ruleId: specRes.value.ruleId,
    precedence: precedence, presence: presence, capability: capability,
    governedModule: governedModule, governedSymbols: governedSymbols,
    governedBlobSha256: governedBlob,
    constructed: constructedOpt, replay: replayOpt, raw: raw))

proc loadExternalSubjectRegistry*(specDir: string = defaultExternalSubjectSpecDir;
                                  overlayDir: string = ""):
    Result[ExternalSubjectRegistry, string] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deterministic registry load (§2.3): enumerate `specDir` children
  ## matching `*.json` sorted by normalized relative path; parse + envelope-
  ## validate each in path order; reject duplicate specId and equal-
  ## precedence subject overlap fail-closed; return the registry sorted by
  ## (precedence, specRelPath). Same input directory ⇒ identical registry.
  ## `overlayDir` (BYOA runtime overlay seam): when non-empty, its `*.json`
  ## children shadow-merge over `specDir` BEFORE validation — a document
  ## with the same normalized relative path (the enumeration identity)
  ## replaces the committed one, new names extend the load. The envelope +
  ## duplicate-specId + overlap checks below run over the effective merged
  ## set, unchanged and fail-closed.
  ## NOTE (PR-0 divergence, documented): absence of a FILE cannot be
  ## classified here — presencePolicy travels IN the document, so an absent
  ## file has no policy to evaluate; the parity consumer compares the
  ## legacy lane outcomes against the loaded entries instead.
  if specDir.len == 0:
    # Runtime root seam (S2b): "" is the anchor-miss sentinel of the
    # `defaultExternalSubjectSpecDir` adapter (or an explicitly empty
    # argument — the same fail-closed class). Re-resolving yields the
    # precise reason; an empty specDir is NEVER walked (Q-013: walkDir on a
    # relative join would enumerate the CWD).
    let seamRes = resolveExternalSubjectSpecDir()
    return err(if seamRes.isErr(): seamRes.error
               else: "spec directory argument must not be empty (fail-closed)")
  var jsonPaths: seq[string] = @[]
  try:
    for kind, path in walkDir(specDir):
      if kind == pcFile and path.endsWith(".json"):
        jsonPaths.add(path)
  except CatchableError as e:
    return err("spec directory not readable (fail-closed): " & specDir & ": " & e.msg)
  if overlayDir.len > 0:
    try:
      for kind, path in walkDir(overlayDir):
        if kind == pcFile and path.endsWith(".json"):
          let rel = lastPathPart(path)
          var replaced = false
          for i in 0 ..< jsonPaths.len:
            if lastPathPart(jsonPaths[i]) == rel:
              jsonPaths[i] = path
              replaced = true
              break
          if not replaced:
            jsonPaths.add(path)
    except CatchableError as e:
      return err("overlay spec directory not readable (fail-closed): " &
        overlayDir & ": " & e.msg)
  jsonPaths.sort()
  var entries: seq[RegistryEntry] = @[]
  for path in jsonPaths:
    let relPath = normalizedRelativePath(path)
    var node: JsonNode
    try:
      node = parseJson(readFile(path))
    except CatchableError as e:
      return err("cannot read spec overlay " & relPath &
        " (missing, unreadable, or not valid JSON): " & e.msg)
    let entryRes = envelopeEntryForNode(relPath, node)
    if entryRes.isErr():
      return err(relPath & ": " & entryRes.error)
    let entry = entryRes.get
    for existing in entries:
      if existing.specId == entry.specId:
        return err("duplicate specId \"" & entry.specId & "\": " &
          existing.specRelPath & " and " & entry.specRelPath)
      if existing.precedence == entry.precedence:
        for sym in entry.governedSymbols:
          if entry.governedModule == existing.governedModule and
              sym in existing.governedSymbols:
            return err("same-precedence (" & $entry.precedence &
              ") subject overlap: " & existing.specRelPath & " and " &
              entry.specRelPath & " both govern " & entry.governedModule &
              "::" & sym)
    entries.add(entry)
  entries.sort(proc(a, b: RegistryEntry): int {.raises: [].} =
    var c = cmp(a.precedence, b.precedence)
    if c != 0: return c
    cmp(a.specRelPath, b.specRelPath))
  ok(ExternalSubjectRegistry(entries: entries))

proc loadRegistryEntryRaw*(specRelPath: string): Option[JsonNode] {.
    raises: [], axiomDecision, axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §2.8 direct-consumer seam for callers OUTSIDE a prepared run (the
  ## bug-verdict display suite): the entry's OWN raw document, resolved
  ## through the one deterministic registry load — no direct path read, no
  ## second semantic source. The prepared run (axiom_engine) passes
  ## `entry.raw` directly and never comes through here. Load failure or an
  ## absent document ⇒ none() — the consumers' fail-soft posture (probeOk=
  ## false / nil display block), never a fabricated payload.
  let regRes = loadExternalSubjectRegistry()
  if regRes.isErr():
    return none(JsonNode)
  for entry in regRes.get.entries:
    if entry.specRelPath == specRelPath:
      return some(entry.raw)
  none(JsonNode)
