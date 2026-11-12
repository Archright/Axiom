## VS-2 external-subject binding registry — PR-0 unit tests
## (REGISTRY_SPEC.md §2 registry core + §4 P0-1 test overlay).
##
## Measured here:
##   1.  Load: the fixture overlay registers through the GENERIC loader with
##       specDir pointed at tests/fixtures/spec_overlays/ — an engine-unknown
##       document, zero engine registration. The six production lanes parse
##       into schema v2 through the compat mapping (lane-shaped JSONs, files
##       untouched).
##   2.  Envelope rejections: every closed-vocabulary violation fails the
##       load with a message naming the rule (duplicate specId, UNKNOWN
##       capability, unknown observation kind incl. the named FUTURE kind
##       write-read-roundtrip, the reserved <expr> slot, unknown templateId,
##       importModule != recomputed derivation, constructedIrTargets !=
##       carriers, equal-precedence subject overlap, malformed pin).
##   3.  Adapter validation (pure): the d2 grammar rules verbatim, exercised
##       through the UNMODIFIED lane validator validateTomlD2AgentOverlayNode
##       (wrong clause count, non-set-equal control, duplicate defect
##       carrier, exclusion duplicates, bad 64-hex blob).
##   4.  Synthesize → census: fixture carriers published through the shared
##       publishExternalCandidate core; single-origin parse bound with the
##       stamped single-call-bool replay harness.
##   5.  Tri-state + fail-closed legs.
##   6.  Wave entry rename asymmetry (wrDefectOnly / wrOwnName).
##   7.  Determinism: two loads — identical projections, identical order.
##   8.  NOT-an-adoption guard: the fixture carries no adoption object and
##       no real subject identity, and the registry requires none for
##       constructed-gate.
##
## DIVERGENCE NOTE (spec §4 vs PR-0 reality, documented for the report):
## the d2 lane validator pins carrier NAMES (d2StringGateReject/
## d2CommentGateReject — axiom_engine.nim validateD2Carriers), so the
## fixture-named document cannot pass the d2 GRAMMAR validator; the grammar
## rules are therefore exercised with d2-named mutations of the committed
## spec (group 3), while the REGISTRY envelope — the generic layer PR-0
## introduces — accepts the fixture names (group 1/2). The name
## parameterization is the PR-2 adapter work.

import std/[json, os, options, strutils, unittest]
import ../../src/core/results
import ../../src/core/crypto/hash_kernel
import ../../src/core/utils/repo_root
import ../../src/core/trusted/axiom_ir
import ../../src/core/trusted/axiom_ir_helpers
import ../../src/core/trusted/axiom_pragmas
import ../../src/core/trusted/specification_artifact
import ../../src/infrastructure/external_ir_materializer
import ../../src/cli/axiom_engine
import ../../src/cli/external_subject_registry
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/counterexample_replay

putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_vs2_registry_test_state")

const fixtureSpecDir = repoRootConst() / "tests" / "fixtures" / "spec_overlays"
const fixtureDocName = "constructed_gate_fixture.json"
const fixtureModuleRel = "fixture_gate_subject/fixture_gate_subject.nim"
const fixtureModuleAbs = fixtureSpecDir / fixtureModuleRel
const fixtureExaminedFn = "gateAccept"
const fixtureRuleId = "external:fixture/constructed-gate"
const fixtureDerivationRule = "fixture-gate-model-v1|rule=" & fixtureRuleId &
  "|grounding=" & fixtureModuleRel & ":21-23"

proc fixtureDoc(): JsonNode =
  parseJson(readFile(fixtureSpecDir / fixtureDocName))

proc fixtureModuleBytes(): string =
  readFile(fixtureModuleAbs)

proc fixtureResolver(): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    try:
      if modulePath == fixtureModuleRel:
        some(readFile(fixtureModuleAbs))
      else:
        none(string)
    except CatchableError:
      none(string)

proc writeTempSpecDir(name: string; docs: seq[tuple[n, c: string]]): string =
  ## A temp specDir the generic loader can be pointed at (the loader seam —
  ## no engine hook, no env var).
  result = getTempDir() / "ax_vs2_registry_specs" / name
  if dirExists(result):
    removeDir(result)
  createDir(result)
  for d in docs:
    writeFile(result / d.n, d.c)

proc registryProjection(reg: ExternalSubjectRegistry): seq[string] =
  ## Deterministic (precedence, specRelPath)-ordered identity projection —
  ## the parity-summary shape.
  for entry in reg.entries:
    result.add($entry.precedence & "|" & entry.specRelPath & "|" &
      entry.specId & "|" & $entry.capability & "|" & $entry.presence)

proc fixtureCarriers(): tuple[defect, control: IRFuncDef] =
  ## The fixture carriers as CONSTRUCTED IR (built fresh per call — IRExpr
  ## is a ref and parents must not share nodes). The claim is stated
  ## post-splice directly: gate(c) == forbid(c) for the defect, forbid ==
  ## forbid for the control — free variables exactly the byte parameter.
  proc gateIr(): IRExpr =
    let cVar = irVar("c", irTypeBitVec64())
    irOr(irOr(irEq(cVar, irLit(2)), irEq(cVar, irLit(9))),
         irOr(irEq(cVar, irLit(11)), irEq(cVar, irLit(127))))
  proc forbidIr(): IRExpr =
    let cVar = irVar("c", irTypeBitVec64())
    irOr(irOr(irLe(cVar, irLit(8)),
              irAnd(irGe(cVar, irLit(10)), irLe(cVar, irLit(31)))),
         irEq(cVar, irLit(127)))
  proc domainPreconditions(): seq[IRExpr] =
    let cVar = irVar("c", irTypeBitVec64())
    result = @[irGe(cVar, irLit(1)), irLe(cVar, irLit(255))]
    for e in @[10'i64, 13, 34, 92]:
      result.add(irNot(irEq(cVar, irLit(e))))
  var defect = IRFuncDef(
    name: "fixtureGateReject",
    params: @[IRFuncParam(name: "c", ty: irTypeBitVec64())],
    retType: irTypeBool(),
    body: gateIr())
  defect.preConditions = domainPreconditions()
  defect.postConditions = @[irEq(gateIr(), forbidIr())]
  defect.translationLossFree = true
  defect.bindingUniverseComplete = true
  defect.propositionRegionLossFree = true
  defect.lossOutsideBindingRegions = false
  var control = IRFuncDef(
    name: "fixtureControlReject",
    params: @[IRFuncParam(name: "c", ty: irTypeBitVec64())],
    retType: irTypeBool(),
    body: forbidIr())
  control.preConditions = domainPreconditions()
  control.postConditions = @[irEq(forbidIr(), forbidIr())]
  control.translationLossFree = true
  control.bindingUniverseComplete = true
  control.propositionRegionLossFree = true
  control.lossOutsideBindingRegions = false
  (defect, control)

proc stampedFixtureParseBound(): SubjectParseBoundComponents =
  ## The single-origin claim-carrier measurement over the REAL fixture
  ## bytes, plus the replay harness stamped from the CLOSED template
  ## registry (the <module> slot fixed at synthesis).
  var parseBound = measureClaimCarrierParseBoundComponents(
    fixtureModuleBytes(), fixtureExaminedFn, fixtureDerivationRule)
  parseBound.replayHarnessTemplate =
    replayTemplate("single-call-bool-v1").get.replace(
      ReplayModulePlaceholder, "fixture_gate_subject")
  parseBound

# ---------------------------------------------------------------------------
# Group 1 — Load (generic loader, fixture + the six production lanes)
# ---------------------------------------------------------------------------

suite "registry load — generic loader over fixtureDir and config/spec":

  test "the engine-unknown fixture overlay registers through the generic loader":
    let regRes = loadExternalSubjectRegistry(fixtureSpecDir)
    check regRes.isOk()
    let reg = regRes.get()
    check reg.entries.len == 1
    let entry = reg.entries[0]
    check entry.capability == capConstructedGate
    check entry.presence == ppOptional
    check entry.precedence == 50
    check entry.specRelPath == fixtureDocName
    check entry.specId == "SPEC-FIXTURE-CONSTRUCTED-GATE"
    check entry.ruleId == fixtureRuleId
    check entry.governedModule == fixtureModuleRel
    check entry.governedSymbols == @["gateAccept"]
    check entry.governedBlobSha256 ==
      "22bcb66d6e8261b8b2924f6909017003b50a87ed1e9385cbe5416475f83c015a"
    check entry.constructed.isSome
    check entry.constructed.get.symbols ==
      @["fixtureGateReject", "fixtureControlReject"]
    check entry.constructed.get.allowBare == false
    check entry.replay.isSome
    check entry.replay.get.templateId == "single-call-bool-v1"
    check entry.replay.get.importModule == "fixture_gate_subject"
    check entry.replay.get.observation == obsSingleCallBool
    check entry.replay.get.slots == @["<module>", "<lit>"]

  test "the six production lanes parse into schema v2 without touching the files":
    let regRes = loadExternalSubjectRegistry(
      repoRootConst() / "config" / "spec")
    check regRes.isOk()
    let reg = regRes.get()
    check reg.entries.len == 6
    # (precedence, specRelPath, specId, capability, presence) — the
    # audit-verified lane table (REGISTRY_SPEC §1.2-§1.4), reproduced by
    # the PR-0 compat mapping over the lane-shaped documents.
    let expected: seq[tuple[prec: int; rel, sid: string; cap: ExternalSubjectCapability;
        pres: PresencePolicy]] = @[
      (10, "nim_stew_base36_sidecar.json", "SPEC-B36-SIDECAR", capBodyCarry, ppOptional),
      (20, "nim_stew_base36_cout_spec.json", "SPEC-B36-COUT", capBodyCarry, ppMandatory),
      (30, "base36_sizing_relational_spec.json", "SPEC-B36-RELATIONAL", capBetaComposition, ppMandatory),
      (40, "nim_stew_base32_rem_spec.json", "SPEC-B32-REM-RANGE", capTermSplice, ppMandatory),
      (50, "toml_d2_agent_spec.json", "SPEC-TOML-D2-AGENT", capConstructedGate, ppOptional),
      (60, "nim_libp2p_bytesview_slice.json", "SPEC-LIBP2P-BV-SLICE", capArithmeticLaw, ppOptional)]
    for i, want in expected:
      check reg.entries[i].precedence == want.prec
      check reg.entries[i].specRelPath == want.rel
      check reg.entries[i].specId == want.sid
      check reg.entries[i].capability == want.cap
      check reg.entries[i].presence == want.pres
    # strictly ascending (precedence, specRelPath) — the total order
    for i in 1 ..< reg.entries.len:
      let a = reg.entries[i - 1]
      let b = reg.entries[i]
      check (a.precedence, a.specRelPath) < (b.precedence, b.specRelPath)
    # governed sets, envelope-derived
    check reg.entries[0].governedModule == "stew/base36.nim"
    check reg.entries[0].governedSymbols == @["decodedLength"]
    check reg.entries[3].governedModule == "stew/base32.nim"
    check reg.entries[4].governedModule == "toml_serialization/lexer.nim"
    check reg.entries[5].governedModule == "libp2p/utils/bytesview.nim"

  test "VS-2 PR-3: the sidecar SpecID is byte-stable across the lane flip":
    # REGISTRY_SPEC §6.1 / §5 PR-3: the flip moves the two-stage validator
    # behind the adapter WITHOUT rotating the SpecID — specIdentity (the
    # H(sorted canonicalSpecIR | ord(soExplicit) | ruleVersion) carrier) and
    # adoption.adoptedSpecHash must both still be the hash the adoption
    # recorded, so every sealed artifact chain stays valid. The stage-(ii)
    # recompute runs on every load; this pins the VALUE as well.
    const sidecarDoc = repoRootConst() / "config" / "spec" /
      "nim_stew_base36_sidecar.json"
    const sidecarAdoptedSpecHash =
      "3f55eaa79f3708894a04d62bc7ac32c9e2a8fe84d4f575348318d7290d237ea8"
    let node = parseJson(readFile(sidecarDoc))
    check node{"adoption"}{"adoptedSpecHash"}.getStr("") == sidecarAdoptedSpecHash
    let specRes = explicitSpecFromOverlay(node)
    check specRes.isOk()
    check specRes.value.specIdentity == sidecarAdoptedSpecHash
    # And the registry load itself stays green (the validator's stage-ii
    # recompute accepts the document — the flip moved no identity input).
    let regRes = loadExternalSubjectRegistry(
      repoRootConst() / "config" / "spec")
    check regRes.isOk()

  test "the closed template registry matches the engine's legacy templates byte-for-byte":
    # VS-2 PR-2: the d2 harness body moved INTO the closed registry (the
    # engine's legacy const died with the lane flip); the byte-identity pin
    # survives as the literal the retired const held.
    check replayTemplate("d2-gate-reject-v1").get ==
      "import <module>\n" &
      "var observedReject = false\n" &
      "try:\n" &
      "  discard Toml.decode(\"k = \\\"a\" & chr(<lit>) & \"b\\\"\", TomlValueRef)\n" &
      "except TomlError:\n" &
      "  observedReject = true\n" &
      "echo \"AXIOM_REPLAY_BEGIN\"\n" &
      "echo $observedReject\n" &
      "echo \"AXIOM_REPLAY_END\"\n"
    # VS-2 PR-1: the bv harness body moved INTO the closed registry (the
    # engine's legacy const died with the lane flip); the byte-identity pin
    # survives as the literal the retired const held.
    check replayTemplate("bv-slice-len-v1").get ==
      "import <module>\n" &
      "var bv = BytesView.init(@[byte 1, 2, 3, 4, 5, 6])\n" &
      "echo \"AXIOM_REPLAY_BEGIN\"\n" &
      "echo $(bv.toOpenArray(1, <lit>).len)\n" &
      "echo \"AXIOM_REPLAY_END\"\n"

# ---------------------------------------------------------------------------
# Group 2 — Envelope rejections (each → err naming the rule)
# ---------------------------------------------------------------------------

suite "envelope rejections — fail-closed, message names the rule":

  template expectLoadErr(dir: string; fragment: string) =
    let regRes = loadExternalSubjectRegistry(dir)
    check regRes.isErr()
    if regRes.isErr():
      check regRes.error.contains(fragment)

  test "duplicate specId is rejected naming both paths":
    let doc = fixtureDoc()
    let dir = writeTempSpecDir("dupspecid", @[
      ("a.json", $doc),
      ("b.json", $doc)])
    expectLoadErr(dir, "duplicate specId \"SPEC-FIXTURE-CONSTRUCTED-GATE\": a.json and b.json")

  test "unknown capability is rejected as UNKNOWN (closed 5-kind discriminator)":
    var doc = fixtureDoc()
    doc["capability"] = %"gate-constructed"
    let dir = writeTempSpecDir("badcap", @[("x.json", $doc)])
    expectLoadErr(dir, "UNKNOWN capability \"gate-constructed\"")

  test "unknown observation.kind is rejected — including the named FUTURE kind":
    for kind in ["write-read-roundtrip", "state-probe"]:
      var doc = fixtureDoc()
      doc["replay"]["observation"]["kind"] = %kind
      let dir = writeTempSpecDir("badobs", @[("x.json", $doc)])
      expectLoadErr(dir, "unknown observation kind \"" & kind & "\"")

  test "the reserved <expr> slot is a load error (no v2 position)":
    var doc = fixtureDoc()
    doc["replay"]["observation"]["slots"] = %["<module>", "<lit>", "<expr>"]
    let dir = writeTempSpecDir("exprslot", @[("x.json", $doc)])
    expectLoadErr(dir, "illegal slot \"<expr>\"")

  test "slot vocabulary is position-constrained — count and order":
    block wrongCount:
      var doc = fixtureDoc()
      doc["replay"]["observation"]["slots"] = %["<module>"]
      let dir = writeTempSpecDir("slotcount", @[("x.json", $doc)])
      expectLoadErr(dir, "must be exactly [\"<module>\", \"<lit>\"]")
    block wrongToken:
      var doc = fixtureDoc()
      doc["replay"]["observation"]["slots"] = %["<module>", "<symbol>"]
      let dir = writeTempSpecDir("slottok", @[("x.json", $doc)])
      expectLoadErr(dir, "illegal slot \"<symbol>\"")

  test "unknown replay templateId is rejected (closed registry)":
    var doc = fixtureDoc()
    doc["replay"]["templateId"] = %"gate-reject-v2"
    let dir = writeTempSpecDir("badtmpl", @[("x.json", $doc)])
    expectLoadErr(dir, "UNKNOWN replay templateId \"gate-reject-v2\"")

  test "importModule must equal the recomputed derivation from subject.module":
    var doc = fixtureDoc()
    doc["replay"]["importModule"] = %"fixture_gate"
    let dir = writeTempSpecDir("badimport", @[("x.json", $doc)])
    expectLoadErr(dir, "replay.importModule \"fixture_gate\" != the recomputed derivation \"fixture_gate_subject\"")

  test "constructedIrTargets.symbols must equal the payload carriers":
    var doc = fixtureDoc()
    doc["constructedIrTargets"]["symbols"] = %["fixtureGateReject"]
    let dir = writeTempSpecDir("badtargets", @[("x.json", $doc)])
    expectLoadErr(dir, "constructedIrTargets.symbols must equal the payload carriers")

  test "equal-precedence subject overlap is a load error":
    var b = fixtureDoc()
    b["specId"] = %"SPEC-FIXTURE-CONSTRUCTED-GATE-B"
    let dir = writeTempSpecDir("overlap", @[
      ("a.json", $fixtureDoc()),
      ("b.json", $b)])
    expectLoadErr(dir, "same-precedence (50) subject overlap")

  test "presencePolicy is a closed 2-kind vocabulary":
    var doc = fixtureDoc()
    doc["presencePolicy"] = %"best-effort"
    let dir = writeTempSpecDir("badpresence", @[("x.json", $doc)])
    expectLoadErr(dir, "UNKNOWN presencePolicy \"best-effort\"")

  test "precedence must be a non-negative JSON integer":
    block negative:
      var doc = fixtureDoc()
      doc["precedence"] = %(-1)
      let dir = writeTempSpecDir("negprec", @[("x.json", $doc)])
      expectLoadErr(dir, "precedence must be >= 0")
    block notAnInt:
      var doc = fixtureDoc()
      doc["precedence"] = %"50"
      let dir = writeTempSpecDir("strprec", @[("x.json", $doc)])
      expectLoadErr(dir, "precedence must be a JSON integer")

  test "malformed subject pins are a load error (64-hex format)":
    var doc = fixtureDoc()
    doc["subject"]["blobSha256"] = %"19d69eed"
    let dir = writeTempSpecDir("badpin", @[("x.json", $doc)])
    expectLoadErr(dir, "malformed pin")

  test "invalid JSON and a missing specOrigin are rejected with the path":
    block badJson:
      let dir = writeTempSpecDir("badjson", @[("x.json", "{not json")])
      expectLoadErr(dir, "x.json")
    block badOrigin:
      var doc = fixtureDoc()
      doc["specOrigin"] = %"soMined"
      let dir = writeTempSpecDir("badorigin", @[("x.json", $doc)])
      expectLoadErr(dir, "soExplicit")

  test "registry self-test: no registered template contains <expr>; placeholders occur exactly once":
    for tid in ["d2-gate-reject-v1", "bv-slice-len-v1", "single-call-bool-v1"]:
      let tmplRes = replayTemplate(tid)
      check tmplRes.isOk()
      let body = tmplRes.get()
      check body.contains("<expr>") == false
      check body.count(ReplayModulePlaceholder) == 1
      check body.count(ReplayValuePlaceholder) == 1

# ---------------------------------------------------------------------------
# Group 3 — Adapter validation (pure): the d2 grammar rules VERBATIM through
# the UNMODIFIED lane validator, over d2-named mutations of the committed
# spec (see the divergence note in the file header).
# ---------------------------------------------------------------------------

suite "adapter validation (pure) — d2 grammar rules verbatim":

  proc committedD2Doc(): JsonNode =
    parseJson(readFile(repoRootConst() / "config" / "spec" /
      "toml_d2_agent_spec.json"))

  test "the committed d2 document validates; a fixture-named carrier pair does NOT (lane names are pinned)":
    check validateTomlD2AgentOverlayNode(committedD2Doc()).isOk()
    var renamed = committedD2Doc()
    renamed["carriers"][0]["name"] = %"fixtureGateReject"
    renamed["carriers"][1]["name"] = %"fixtureControlReject"
    renamed["canonicalSpecIR"].elems[7] = %"fixtureGateReject(c) == ((c == 2) or (c == 9) or (c == 11) or (c == 127))"
    renamed["canonicalSpecIR"].elems[8] = %"fixtureControlReject(c) == ((c <= 8) or ((10 <= c) and (c <= 31)) or (c == 127))"
    let res = validateTomlD2AgentOverlayNode(renamed)
    check res.isErr()
    check res.error.contains("must be named")

  test "wrong clause count (≠9) is rejected":
    var doc = committedD2Doc()
    doc["canonicalSpecIR"].elems.delete(8)
    let res = validateTomlD2AgentOverlayNode(doc)
    check res.isErr()
    check res.error.contains("exactly")

  test "a non-set-equal control carrier is rejected (the injection guard)":
    var doc = committedD2Doc()
    doc["canonicalSpecIR"].elems[8] = %"d2CommentGateReject(c) == ((c <= 8) or ((11 <= c) and (c <= 31)) or (c == 127))"
    let res = validateTomlD2AgentOverlayNode(doc)
    check res.isErr()
    check res.error.contains("set-equal to forbid")

  test "a duplicate defect carrier is rejected":
    var doc = committedD2Doc()
    let defectCarrier = doc["carriers"][0].copy()
    doc["carriers"] = %*[defectCarrier, defectCarrier]
    let res = validateTomlD2AgentOverlayNode(doc)
    check res.isErr()
    check res.error.contains("duplicate defect carrier")

  test "duplicate structural exclusions are rejected":
    var doc = committedD2Doc()
    doc["canonicalSpecIR"].elems[4] = %"c != 10"
    let res = validateTomlD2AgentOverlayNode(doc)
    check res.isErr()
    check res.error.contains("must be distinct")

  test "a malformed 64-hex blob is rejected":
    var doc = committedD2Doc()
    doc["subject"]["blobSha256"] = %"not-a-digest"
    let res = validateTomlD2AgentOverlayNode(doc)
    check res.isErr()
    check res.error.contains("64-hex digest")

# ---------------------------------------------------------------------------
# Groups 4-6 — Synthesize → census through the shared core; tri-state; wave
# entry rename asymmetry.
# ---------------------------------------------------------------------------

suite "synthesize → census through publishExternalCandidate (P0-1 core entry)":

  test "fixture carriers publish: 2 census records, single-origin parse bound, stamped single-call-bool harness":
    let (defect, control) = fixtureCarriers()
    var census = ExternalCandidateCensus()
    let defectRes = publishExternalCandidate(
      census, "fixtureGateReject", fixtureExaminedFn, fixtureModuleRel,
      "", fixtureModuleBytes(), defect, stampedFixtureParseBound(), wrDefectOnly)
    check defectRes.isOk()
    let controlRes = publishExternalCandidate(
      census, "fixtureControlReject", fixtureExaminedFn, fixtureModuleRel,
      "", fixtureModuleBytes(), control, stampedFixtureParseBound(), wrOwnName)
    check controlRes.isOk()
    # census.records gains exactly 2 records, named by the carriers
    check census.records.len == 2
    check census.records[0].functionName == "fixtureGateReject"
    check census.records[1].functionName == "fixtureControlReject"
    check census.records[0].modulePath == fixtureModuleRel
    check census.records[1].modulePath == fixtureModuleRel
    # both eligible ⇒ ok(true) tri-state (asserted via the returned value
    # above) and the parse bound rides the wave-facing eligible entries
    check census.eligible.len == 2
    for eligibleEntry in census.eligible:
      let pb = eligibleEntry.parseBound
      check pb.claimCarrierSingleOrigin == true
      check pb.replayHarnessTemplate.startsWith("import fixture_gate_subject")
      check pb.replayHarnessTemplate.count("<lit>") == 1
      check pb.synthesisDerivationDigest.len == 64

  test "wave entry rename asymmetry (wrDefectOnly / wrOwnName)":
    let (defect, control) = fixtureCarriers()
    var census = ExternalCandidateCensus()
    discard publishExternalCandidate(
      census, "fixtureGateReject", fixtureExaminedFn, fixtureModuleRel,
      "", fixtureModuleBytes(), defect, stampedFixtureParseBound(), wrDefectOnly)
    discard publishExternalCandidate(
      census, "fixtureControlReject", fixtureExaminedFn, fixtureModuleRel,
      "", fixtureModuleBytes(), control, stampedFixtureParseBound(), wrOwnName)
    var defectRidesExamined = false
    var controlRidesOwnName = false
    for eligibleEntry in census.eligible:
      if eligibleEntry.entry.name == fixtureExaminedFn:
        defectRidesExamined = true
        check eligibleEntry.funcDef.name == "fixtureGateReject"
      if eligibleEntry.entry.name == "fixtureControlReject":
        controlRidesOwnName = true
    check defectRidesExamined
    check controlRidesOwnName

  test "tri-state: an unmeasurable grounding leg is recorded fail-closed, never fabricated":
    ## DIVERGENCE (spec §4 group 5, documented): PR-0 has no adapter guard
    ## that turns an absent grounding symbol into a synthesis error — the
    ## honest engine behavior (today, unchanged) records the UNMEASURABLE
    ## leg and the seal gate refuses it downstream. Asserted here at that
    ## exact boundary: the differential records disagreement and the
    ## components never present as measured.
    let pbAbsent = measureClaimCarrierParseBoundComponents(
      fixtureModuleBytes(), "noSuchGroundingSymbol", fixtureDerivationRule)
    check pbAbsent.eaAgreed == false
    check pbAbsent.claimCarrierSingleOrigin == true
    check pbAbsent.synthesisDerivationDigest.len == 64
    check not pbAbsent.parseComponentsMeasured()

  test "tri-state: an adapter-level scope rejection errs and adds NO census record (fallback protocol)":
    ## The let-binding guard: the fixture module's gateLetVariant carries a
    ## let-binding, which is outside the body-carry family's
    ## pure-expression scope — the REAL adapter-level rejection in the
    ## PR-0 engine (constructed-gate's own guard arrives with its adapter).
    ## The err must fall back WITHOUT adding a census record.
    let coutDoc = %*{
      "specId": "SPEC-FIXTURE-COUT-LET-GUARD",
      "specOrigin": "soExplicit",
      "ruleId": "external:fixture/cout-let-guard",
      "ruleVersion": "1.0.0",
      "subject": {
        "module": fixtureModuleRel,
        "symbols": ["gateLetVariant"]
      },
      "canonicalSpecIR": [
        "3 <= L",
        "L <= 3",
        "gateLetVariant(L) >= 2"
      ],
      "claimConstant": {"K": 2},
      "canonicalDecisionVector": {"input": "kzz", "L": 3}
    }
    let domainRes = validateCoutOverlayNode(coutDoc)
    check domainRes.isOk()
    var census = ExternalCandidateCensus()
    let before = census.records.len
    let synth = synthesizeBase36CoutCandidate("gateLetVariant", fixtureModuleRel,
      fixtureResolver(), domainRes.get, census, "")
    check synth.isErr()
    if synth.isErr():
      check synth.error.contains("let-bindings")
    check census.records.len == before

# ---------------------------------------------------------------------------
# Group 7 — Determinism
# ---------------------------------------------------------------------------

suite "determinism — two loads, identical projections and ordering":

  test "two loads of the fixture dir produce identical projections":
    let a = registryProjection(loadExternalSubjectRegistry(fixtureSpecDir).get)
    let b = registryProjection(loadExternalSubjectRegistry(fixtureSpecDir).get)
    check a == b
    check a.len == 1

  test "two loads of config/spec produce identical projections (parity-summary determinism)":
    let specDir = repoRootConst() / "config" / "spec"
    let a = registryProjection(loadExternalSubjectRegistry(specDir).get)
    let b = registryProjection(loadExternalSubjectRegistry(specDir).get)
    check a == b
    check a.len == 6

# ---------------------------------------------------------------------------
# Group 8 — NOT-an-adoption guard
# ---------------------------------------------------------------------------

suite "NOT-an-adoption guard — the fixture is a grammar exercise":

  test "the fixture carries no adoption object and no real subject identity, and the registry requires none":
    let doc = fixtureDoc()
    check doc{"adoption"}.isNil
    check doc{"subject"}{"commit"}.isNil
    check doc{"subject"}{"repository"}.getStr("").startsWith("fixture-only")
    # the constructed-gate envelope needs none of them: the load succeeded
    # (group 1) on capability-scoped payload rules alone
    check loadExternalSubjectRegistry(fixtureSpecDir).isOk()

  test "the shared pin proc verifies the fixture's real blob bytes (generalized verifySubjectBlobPin)":
    let pin = verifySubjectBlobPin(fixtureDocName, fixtureModuleRel,
      "22bcb66d6e8261b8b2924f6909017003b50a87ed1e9385cbe5416475f83c015a",
      fixtureSpecDir)
    check pin.isOk()
    check pin.get == true
    block mismatch:
      let bad = verifySubjectBlobPin(fixtureDocName, fixtureModuleRel,
        "0000000000000000000000000000000000000000000000000000000000000000",
        fixtureSpecDir)
      check bad.isErr()
      check bad.error.contains("blob mismatch")
    block absent:
      let inert = verifySubjectBlobPin(fixtureDocName,
        "fixture_gate_subject/absent.nim",
        "22bcb66d6e8261b8b2924f6909017003b50a87ed1e9385cbe5416475f83c015a",
        fixtureSpecDir)
      check inert.isOk()
      check inert.get == false

# ---------------------------------------------------------------------------
# Per-unit adoptedSpecRef recording (display v3) — the PreparedRun seam
# ---------------------------------------------------------------------------

suite "PreparedRun.adoptedSpecRefs — per-unit first-wins recording":

  test "a default PreparedRun records nothing (ungoverned → none)":
    var prepared: PreparedRun
    check prepared.adoptedSpecRefs.len == 0
    check adoptedSpecRefFor(prepared, "mod::fn").isNone()

  test "recorded units project their specRelPath + specId":
    var prepared: PreparedRun
    prepared.adoptedSpecRefs.add((unitKey: "stew/base36.nim::encodedLength",
      specRelPath: "config/spec/nim_base36_cout.json",
      specId: "SPEC-B36-COUT"))
    let adopted = adoptedSpecRefFor(prepared, "stew/base36.nim::encodedLength")
    check adopted.isSome()
    check adopted.get().specRelPath == "config/spec/nim_base36_cout.json"
    check adopted.get().specId == "SPEC-B36-COUT"

  test "first record wins on a duplicate unit key (dispatch-winner lane)":
    var prepared: PreparedRun
    prepared.adoptedSpecRefs.add((unitKey: "m::f",
      specRelPath: "config/spec/a.json", specId: "SPEC-A"))
    prepared.adoptedSpecRefs.add((unitKey: "m::f",
      specRelPath: "config/spec/b.json", specId: "SPEC-B"))
    let adopted = adoptedSpecRefFor(prepared, "m::f")
    check adopted.get().specRelPath == "config/spec/a.json"
    check adopted.get().specId == "SPEC-A"

  test "an unrecorded key is none (no display block for the unit)":
    var prepared: PreparedRun
    prepared.adoptedSpecRefs.add((unitKey: "m::f",
      specRelPath: "config/spec/a.json", specId: "SPEC-A"))
    check adoptedSpecRefFor(prepared, "m::g").isNone()
