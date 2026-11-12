## PROPOSITION_DISPROVED S4-S5 tests — counterexample payload capture + replay adapter.
##
## Contract under test (docs/spec/bug_verdict_glossary.md §2.2):
##   1. SAT model capture — `(get-model)` yields the concrete assignment.
##   2. UNSAT regression — the capture path must not disturb the proven
##      UNSAT lane (certificate extraction stays free of `(error ...)`).
##   3. Replay adapter — the harness reproduces the violation on the real
##      toolchain (agree), contradicts it (disagree → fail-closed), or is
##      unavailable (fail-closed). Promotion authority is NOT exercised here.
##   4. Payload projection — ProofCertificate.counterExample carries the
##      PROPOSITION_DISPROVED records only when they exist.

import std/[unittest, options, tables, strutils, os, osproc, sequtils]

import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/trusted/claim_authority  ## VerifiedClaim
import core/crypto/hash_kernel
import core/types/obligation_evidence
import core/types/proof_status  ## psFail / psPass
import verification/cross_validation  ## CrossValidationResult
import verification/obligation/obligation_ir  ## ObligationGenerationResultKind
import verification/obligation/verification_result_interpreter  ## ObligationExecutionRecord
import verification/solver_adapter
import verification/symbolic_test_synth
import verification/counterexample_replay
import verification/batch_uap/ir_pipeline_runner
import core/trusted/verification_result_types as vrt

let bv64 = irTypeBitVec64()

func bvHex(v: int64): string =
  "#x" & v.toHex(16).toLowerAscii()

proc paramNamed(name: string): IRFuncParam =
  IRFuncParam(name: name, ty: bv64, constraint: none(IRExpr))

func makePipelineResult(funcName, modulePath, irDigest: string;
                        verification: vrt.VerificationResult;
                        success: bool): IrPipelineResult =
  IrPipelineResult(
    funcName: funcName,
    modulePath: modulePath,
    irDigest: irDigest,
    smtScript: "",
    leanSource: "",
    crossValidation: CrossValidationResult(consistent: true),
    z3Sat: success,
    success: success,
    skipped: false,
    verification: verification,
    provenance: vpNone,
    backend: vbCanonicalChc,
    actualBackend: vbCanonicalChc,
    fallbackOccurred: false,
    fallbackReason: "",
    requestedBackend: vbCanonicalChc,
    selectedBackend: vbCanonicalChc,
    complexity: 1.0,
    verifiedClaim: none(VerifiedClaim),
    obligationVerdict: ObligationVerdictInfo(kind: ogrGenerated, reason: "", obligationCount: 1),
    obligationExecution: ObligationExecutionRecord())

# ─── Suite 1: SAT model capture through the real solver ────────────────────

suite "solver_adapter — S4 model capture":
  test "SAT answer carries the concrete (get-model) assignment":
    let adapter = newSolverAdapter(z3Path = "z3", timeoutMs = 10000, printCertificate = true)
    let script =
      "(set-logic QF_BV)\n" &
      "(declare-fun x () (_ BitVec 64))\n" &
      "(assert (= x " & bvHex(5) & "))\n" &
      "(check-sat)\n"
    let outcome = adapter.solve(script)
    check outcome.status == sosSat
    check outcome.modelBindings.len == 1
    check outcome.modelBindings[0].name == "x"
    # Z3 4.13 prints BitVec64 literals as #x… hex.
    check outcome.modelBindings[0].value == bvHex(5)
    # Exact input projection: binding → Nim literal.
    let inputs = modelToTestInputs(outcome.modelBindings, @[paramNamed("x")])
    check inputs == @["5"]
    check counterexampleBindingsPayload(outcome.modelBindings) == @["x=5"]

  test "UNSAT regression — get-model error reply never becomes a certificate":
    let adapter = newSolverAdapter(z3Path = "z3", timeoutMs = 10000, printCertificate = true)
    # x=5 forces (x mod 3 == 2); its negation is unsatisfiable.
    let script =
      "(set-logic QF_BV)\n" &
      "(declare-fun x () (_ BitVec 64))\n" &
      "(assert (= x " & bvHex(5) & "))\n" &
      "(assert (not (= (bvsrem x #x0000000000000003) #x0000000000000002)))\n" &
      "(check-sat)\n"
    let outcome = adapter.solve(script)
    check outcome.status == sosUnsat
    check outcome.modelBindings.len == 0
    # The `(get-model)` after unsat replies `(error …)`; the certificate slot
    # must stay empty — the inductive-invariant extraction is untouched.
    check outcome.certificate.predicateInvariants.len == 0

# ─── Suite 2: concrete property evaluation + agreement decision (pure) ─────

suite "counterexample_replay — concrete evaluation and agreement":
  let prop = irAnd(irLe(irLit(0), irVar("result", bv64)),
                   irLt(irVar("result", bv64), irLit(3)))

  test "property concretely holds / fails on observed results":
    var holds = initTable[string, ConcreteValue]()
    holds["result"] = ConcreteValue(kind: ckInt, i: 2)
    check evaluatePostconditions(@[prop], holds) == some(true)
    var fails = initTable[string, ConcreteValue]()
    fails["result"] = ConcreteValue(kind: ckInt, i: -1)
    check evaluatePostconditions(@[prop], fails) == some(false)

  test "outside the certified subset evaluates fail-closed (none)":
    var env = initTable[string, ConcreteValue]()
    env["result"] = ConcreteValue(kind: ckInt, i: 1)
    check evalConcreteIr(irCall("unknownFn", @[]), env).isNone
    check evaluatePostconditions(@[], env).isNone

  test "parseConcreteLiteral accepts Nim literals, rejects garbage":
    check parseConcreteLiteral("5").get.i == 5
    check parseConcreteLiteral("-7").get.i == -7
    check parseConcreteLiteral("true").get.b == true
    check parseConcreteLiteral("#x05").isNone
    check parseConcreteLiteral("").isNone
    # the FULL unsigned domain since v1.2: [2^63, 2^64−1] enters as its
    # exact bit pattern (int64 stores patterns, not meanings); ≥ 2^64 and
    # below int64.low are unrepresentable → none (fail-closed)
    check parseConcreteLiteral("18446744073709551615").get.i == -1
    check parseConcreteLiteral("9223372036854775808").get.i == int64.low
    check parseConcreteLiteral("99999999999999999999").isNone
    check parseConcreteLiteral("-9223372036854775809").isNone
    check parseConcreteLiteral("123456789012345678901").isNone

  test "agreement: violation reproduced = agree; contradiction = disagree":
    check decideReplayVerdict(true, some(false)) == rvAgree
    check decideReplayVerdict(true, some(true)) == rvDisagree
    check decideReplayVerdict(true, none(bool)) == rvUnavailable
    check decideReplayVerdict(false, some(false)) == rvUnavailable

  test "bv64 wrap semantics are bit-exact (bvadd/bvmul)":
    var env = initTable[string, ConcreteValue]()
    env["a"] = ConcreteValue(kind: ckInt, i: high(int64))
    env["b"] = ConcreteValue(kind: ckInt, i: 1)
    let addWrap = evalConcreteIr(irBinOp(boAdd, irVar("a", bv64), irVar("b", bv64)), env)
    check addWrap.get.i == low(int64)

# ─── Suite 3: replay harness end-to-end on a synthetic subject fixture ─────

proc gitCapture(root: string; args: string): string =
  let (outp, code) = execCmdEx("git -C \"" & root & "\" " & args,
                               options = {poStdErrToStdOut, poUsePath})
  if code == 0: outp.strip() else: ""

proc makeSubjectFixture(dirName: string; moduleSource: string): string =
  ## Synthetic subject: a temp git repo holding one real Nim module.
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root)
  writeFile(root / "subject_mod.nim", moduleSource)
  discard execCmdEx("git -C \"" & root & "\" init -q", options = {poStdErrToStdOut, poUsePath})
  discard execCmdEx("git -C \"" & root & "\" add -A", options = {poStdErrToStdOut, poUsePath})
  discard execCmdEx("git -C \"" & root & "\" -c user.name=ax -c user.email=ax@test commit -q -m init",
                    options = {poStdErrToStdOut, poUsePath})
  root

const ViolatedSubject = """func buggyDec*(x: int): int =
  ## Model says: for x=3 the property (result >= 0) is violated.
  x - 10
"""

const SoundSubject = """func soundAdd*(x: int): int =
  ## For x=3 the property (result >= 0) holds — a SAT model here is spurious.
  x + 10
"""

suite "counterexample_replay — harness end-to-end (real nim c -r)":
  let propNonNeg = irLe(irLit(0), irVar("result", bv64))

  test "violation reproduced on the pinned toolchain → rvAgree with full record":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_ce_replay_state")
    let root = makeSubjectFixture("ax_ce_replay_violated", ViolatedSubject)
    let cfg = ReplayConfig(
      subjectRepoRoot: root,
      subjectModulePath: root / "subject_mod.nim",
      funcName: "buggyDec",
      paramNames: @["x"],
      inputLiterals: @["3"],
      postconditions: @[propNonNeg])
    let record = runCounterexampleReplay(cfg)
    check record.verdict == rvAgree
    check record.exitCode == 0
    check record.subjectGitRef == gitCapture(root, "rev-parse HEAD")
    check record.subjectGitRef.len == 40
    check record.subjectTreeMerkle == gitCapture(root, "rev-parse HEAD^{tree}")
    check record.moduleSha256 == sha256Hex(ViolatedSubject)
    check record.moduleSha256AfterRun == record.moduleSha256
    check record.worktreeStable
    check record.nimVersion.len > 0
    check record.hostPlatform.len > 0
    # PROPOSITION_DISPROVED payload folds.
    let payload = replayRecordPayload(record)
    check payload.contains("replay.verdict=rvAgree")
    check payload.contains("replay.subjectGitRef=" & record.subjectGitRef)
    check payload.contains("replay.treeMerkle=" & record.subjectTreeMerkle)
    check payload.contains("replay.moduleSha256=" & record.moduleSha256)
    check payload.contains("replay.hostPlatform=" & record.hostPlatform)
    check inputLiteralsPayload(@["x"], @["3"]) == @["input.x=3"]

  test "property actually holds on observed result → rvDisagree (fail-closed input)":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_ce_replay_state")
    let root = makeSubjectFixture("ax_ce_replay_sound", SoundSubject)
    let cfg = ReplayConfig(
      subjectRepoRoot: root,
      subjectModulePath: root / "subject_mod.nim",
      funcName: "soundAdd",
      paramNames: @["x"],
      inputLiterals: @["3"],
      postconditions: @[propNonNeg])
    let record = runCounterexampleReplay(cfg)
    check record.verdict == rvDisagree
    check record.exitCode == 0
    check record.diagnostics.len > 0

  test "no subject repo (no exact-commit binding) → rvUnavailable fail-closed":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_ce_replay_state")
    let root = getTempDir() / "ax_ce_replay_nogit"
    removeDir(root)
    createDir(root)
    writeFile(root / "subject_mod.nim", ViolatedSubject)
    let cfg = ReplayConfig(
      subjectRepoRoot: root,
      subjectModulePath: root / "subject_mod.nim",
      funcName: "buggyDec",
      paramNames: @["x"],
      inputLiterals: @["3"],
      postconditions: @[propNonNeg])
    let record = runCounterexampleReplay(cfg)
    check record.verdict == rvUnavailable
    check record.diagnostics.len > 0

  test "missing subject module → rvUnavailable before anything executes":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_ce_replay_state")
    let cfg = ReplayConfig(
      subjectRepoRoot: "",
      subjectModulePath: getTempDir() / "ax_ce_replay_missing" / "nope.nim",
      funcName: "buggyDec",
      paramNames: @["x"],
      inputLiterals: @["3"],
      postconditions: @[propNonNeg])
    let record = runCounterexampleReplay(cfg)
    check record.verdict == rvUnavailable
    check record.exitCode == -1

# ─── Suite 4: certificate slot projection ──────────────────────────────────

suite "ProofCertificate — counterExample slot projection":
  test "vsDisproved result carries the PROPOSITION_DISPROVED payload into the certificate":
    var r = makePipelineResult("buggyDec", "subject_mod.nim", "a".repeat(64),
      vrt.makeDisproved(vrt.smBMC, vrt.pkZ3Bmc, vrt.psBounded), success = false)
    r.verification.model = "(define-fun x () (_ BitVec 64) #x0000000000000003)"
    r.counterExample = @["input.x=3", "propertyViolated=(bvsge result #x0000000000000000)",
                         "replay.verdict=rvAgree"]
    let cert = toProofCertificate(r)
    check cert.status == psFail
    check cert.counterExample == r.counterExample
    check cert.counterExample.len == 3

  test "no payload on the proven path — slot stays empty (zero-diff regression)":
    let r = makePipelineResult("remDomain", "rem_body.nim", "b".repeat(64),
      vrt.makeProved(vrt.smBMC, vrt.pkZ3Bmc, vrt.psBounded), success = true)
    let cert = toProofCertificate(r)
    check cert.status == psPass
    check cert.counterExample.len == 0

# ─── Suite 5: pipeline entry — replayConfirmedDisproof ─────────────────────

suite "counterexample_replay — replayConfirmedDisproof (pipeline entry)":
  let propNonNeg = irLe(irLit(0), irVar("result", bv64))

  proc entryFuncDef(name: string): IRFuncDef =
    IRFuncDef(
      name: name,
      params: @[paramNamed("x")],
      retType: bv64,
      body: irBinOp(boAdd, irVar("x", bv64), irLit(0)),
      postConditions: @[propNonNeg],
      symbolTable: SymbolTable(symbols: @[], nameIndex: initTable[string, int]()))

  test "agreement: exact input from the model reply, PROPOSITION_DISPROVED payload assembled":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_ce_replay_state")
    let root = makeSubjectFixture("ax_ce_replay_entry_agree", ViolatedSubject)
    let modelRaw = "sat\n(define-fun x () (_ BitVec 64) " & bvHex(3) & ")\n"
    let replay = replayConfirmedDisproof(root, "subject_mod.nim",
                                         entryFuncDef("buggyDec"), modelRaw)
    check replay.agreed
    check replay.diagnostics.len == 0
    # Exact input (PROPOSITION_DISPROVED element 2) + violation statement + replay record.
    check replay.payload.contains("input.x=3")
    check replay.payload.anyIt(it.startsWith("propertyViolated="))
    check replay.payload.anyIt(it == "replay.verdict=rvAgree")
    check replay.payload.anyIt(it.startsWith("replay.subjectGitRef="))

  test "disagreement: property holds → agreed=false, fail-closed diagnostics":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_ce_replay_state")
    let root = makeSubjectFixture("ax_ce_replay_entry_disagree", SoundSubject)
    let modelRaw = "sat\n(define-fun x () (_ BitVec 64) " & bvHex(3) & ")\n"
    let replay = replayConfirmedDisproof(root, "subject_mod.nim",
                                         entryFuncDef("soundAdd"), modelRaw)
    check not replay.agreed
    check replay.payload.len == 0
    check replay.diagnostics.startsWith("rvDisagree")

  test "no model bindings in raw output → replay unavailable → agreed=false":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_ce_replay_state")
    let root = makeSubjectFixture("ax_ce_replay_entry_nomodel", ViolatedSubject)
    let replay = replayConfirmedDisproof(root, "subject_mod.nim",
                                         entryFuncDef("buggyDec"), "sat\n")
    check not replay.agreed
    check replay.diagnostics.startsWith("rvUnavailable")

# ─── Suite 6: d2-agent subject dep resolution (quirks Q4) ──────────────────

suite "counterexample_replay — d2-agent dep resolution (Q4)":
  test "importStatementTokens scans multi-line import/export lists, cuts comments":
    # The real subject shape (toml_serialization/reader.nim): bare `import`,
    # comma-continued list, bracket forms; a bare `export` block.
    let real = "import\n" &
               "  std/[enumutils, tables],\n" &
               "  stew/[enums, objects],\n" &
               "  faststreams/inputs,\n" &
               "  serialization/[object_serialization, errors],\n" &
               "  ./types\n" &
               "export\n" &
               "  errors, format\n"
    check sourceNamesDepPackages(real)
    # Self-contained stamped subjects (unit fixtures, collateral harnesses)
    # must stay zero-diff: prose mentions, local imports, `results` as a
    # plain identifier — none of these name the dep stack.
    let fixture = "## stub prose mentioning stew/enums and nim-faststreams\n" &
                  "import ./types\n" &
                  "export format\n" &
                  "var results = 3\n"
    check not sourceNamesDepPackages(fixture)
    check not sourceNamesDepPackages("# import stew/enums\n")
    check not sourceNamesDepPackages("")

  test "parseNimblePkgDirName anchors the name (json_serialization never matches serialization)":
    let p = parseNimblePkgDirName(
      "stew-0.5.0-db22942939773ab7d5a0f2b2668c237240c67dd6")
    check p.isSome and p.get[0] == "stew" and p.get[1] == "0.5.0"
    check parseNimblePkgDirName(
      "json_serialization-0.2.9-4062dc791d26").get[0] == "json_serialization"
    check parseNimblePkgDirName(
      "serialization-0.5.4-6a75be38ab6c").get[0] == "serialization"
    check parseNimblePkgDirName(
      "results-0.5.1-a9c011f74bc9").get[0] == "results"
    check parseNimblePkgDirName("nonsense").isNone

  test "versionRank: dotted and pkgcache-flattened forms compare on one scale":
    check versionRank("0.5.4").get == 54
    check versionRank("054").get == 54
    check versionRank("0.5.0").get > versionRank("0.2.0").get
    check versionRank("020").get == versionRank("0.2.0").get
    check versionRank("").isNone

  test "newestPkgDir picks max (rank, dirName) deterministically":
    check newestPkgDir(@[]).isNone
    let picked = newestPkgDir(@[
      ("/s/stew-0.2.0-aaa", "stew-0.2.0-aaa", "0.2.0"),
      ("/s/stew-0.5.0-bbb", "stew-0.5.0-bbb", "0.5.0")])
    check picked.get == "/s/stew-0.5.0-bbb"
    # same version → lexicographic dirName tie-break (deterministic pick)
    let tied = newestPkgDir(@[
      ("/s/pkg-1.0-aaa", "pkg-1.0-aaa", "1.0"),
      ("/s/pkg-1.0-bbb", "pkg-1.0-bbb", "1.0")])
    check tied.get == "/s/pkg-1.0-bbb"

  test "pkgcache slug matching keeps the nim-prefix boundary":
    check pkgcacheDirNamesPackage("githubcom_statusimnimstew_020", "stew")
    check pkgcacheDirNamesPackage("githubcom_statusimnimstew", "stew")
    check pkgcacheDirNamesPackage("githubcom_arnetheducknimresults", "results")
    check pkgcacheDirNamesPackage(
      "githubcom_statusimnimfaststreams_052_059bc2f5", "faststreams")
    # json_serialization must never satisfy serialization
    check not pkgcacheDirNamesPackage(
      "githubcom_statusimnimjsonserialization_029", "serialization")
    check pkgcacheVersionAfter("githubcom_statusimnimstew_020_79e4fa5a",
                               "stew") == "020"
    check versionRank(pkgcacheVersionAfter(
      "githubcom_arnetheducknimresults_051_df8113dd", "results")).get ==
        versionRank("0.5.1").get

  test "resolver: newest wins from a synthetic store; missing package fails closed":
    let store = getTempDir() / "ax_ce_depstore"
    removeDir(store)
    createDir(store / "stew-0.2.0-26d477c7" / "stew")
    createDir(store / "stew-0.5.0-db229429" / "stew")
    createDir(store / "serialization-0.2.6-26deca68" / "serialization")
    createDir(store / "serialization-0.5.4-6a75be38" / "serialization")
    # a name-carrying dir WITHOUT the top module provides nothing
    createDir(store / "results-0.5.1-a9c011f7")
    let r = resolveNimblePackageRootsFrom(@["stew", "serialization"], @[store])
    check r.missing.len == 0
    check r.paths == @[
      store / "stew-0.5.0-db229429",
      store / "serialization-0.5.4-6a75be38"]
    # results names a dir but provides no module (and nothing else does)
    let rm = resolveNimblePackageRootsFrom(@["results"], @[store])
    check rm.missing == @["results"]
    check rm.paths.len == 0

  test "env override: AXIOM_REPLAY_DEP_PATHS wins wholesale; bad entry fails closed":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_ce_replay_state")
    let tree = getTempDir() / "ax_ce_deptree"
    removeDir(tree)
    createDir(tree / "toml_serialization")
    writeFile(tree / "toml_serialization" / "lexer.nim",
              "import stew/enums\nfunc f*(): int = 1\n")
    let depA = getTempDir() / "ax_ce_dep_a"
    let depB = getTempDir() / "ax_ce_dep_b"
    removeDir(depA); removeDir(depB)
    createDir(depA); createDir(depB)
    # override wins without any store discovery — duplicates collapse
    putEnv(ReplayDepPathsEnvVar, depA & "::" & depB & ":" & depA)
    let ov = resolveD2AgentDepSearchPaths(tree)
    check ov.error.len == 0
    check ov.paths == @[depA, depB]
    # non-directory entry → fail-closed diagnostic naming the entry
    putEnv(ReplayDepPathsEnvVar, depA & ":/nonexistent_ax_ce_dep_xyz")
    let bad = resolveD2AgentDepSearchPaths(tree)
    check bad.paths.len == 0
    check bad.error.contains("not a directory")
    check bad.error.contains("/nonexistent_ax_ce_dep_xyz")
    delEnv(ReplayDepPathsEnvVar)

  test "subject-tree gate: dep names in imports resolve; self-contained stays zero-diff":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_ce_replay_state")
    delEnv(ReplayDepPathsEnvVar)
    let tree = getTempDir() / "ax_ce_deptree_gate"
    removeDir(tree)
    createDir(tree / "toml_serialization")
    writeFile(tree / "toml_serialization" / "lexer.nim",
              "## prose only\nfunc f*(): int = 1\n")
    check not subjectTreeNeedsDepRoots(tree)
    let selfContained = resolveD2AgentDepSearchPaths(tree)
    check selfContained.error.len == 0
    check selfContained.paths.len == 0
    writeFile(tree / "toml_serialization" / "lexer.nim",
              "import stew/enums\nfunc f*(): int = 1\n")
    check subjectTreeNeedsDepRoots(tree)
    # with the override removed, resolution needs the real store — the gate
    # decision itself is the unit here; the store hit is covered above.

  test "buildHarnessCmd appends dep paths after the subject paths (zero-diff without)":
    let base = buildHarnessCmd("nim", "/s/toml_serialization", "/s", "/h",
                               "/h/replay_harness.nim", @[])
    # locks the pre-Q4 command shape exactly (collateral harnesses zero-diff)
    check base == "\"nim\" c -r --hints:off --warnings:off" &
      " --skipParentCfg --skipUserCfg --skipProjCfg" &
      " --path:\"/s/toml_serialization\" --path:\"/s\"" &
      " --path:\"/s/src\" --path:\"/s/tools\"" &
      " --nimcache:\"/h/nimcache\"" &
      " -o:\"/h/replay_harness_bin\" \"/h/replay_harness.nim\""
    let withDeps = buildHarnessCmd("nim", "/s/toml_serialization", "/s", "/h",
                                   "/h/replay_harness.nim",
                                   @["/n/pkgs2/stew-0.5.0-x",
                                     "/n/pkgs2/serialization-0.5.4-y"])
    check withDeps.contains("--path:\"/s/tools\" " &
      "--path:\"/n/pkgs2/stew-0.5.0-x\" " &
      "--path:\"/n/pkgs2/serialization-0.5.4-y\" --nimcache:")

# ─── Suite 7: depSearchPaths end-to-end (real nim c -r) ────────────────────

suite "counterexample_replay — depSearchPaths end-to-end":
  const DepEnumsSrc = "func enumTag*(b: byte): int = b.int\n"
  const DepSubjectSrc = "import stew/enums\n" &
                        "func classify*(x: int): int = enumTag(byte(x)) + 1\n"

  test "external dep resolves only through depSearchPaths (agree with, unavailable without)":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_ce_replay_state")
    delEnv(ReplayDepPathsEnvVar)
    let store = getTempDir() / "ax_ce_depstore_e2e" / "stew-1.0-deadbeef"
    removeDir(getTempDir() / "ax_ce_depstore_e2e")
    createDir(store / "stew")
    writeFile(store / "stew" / "enums.nim", DepEnumsSrc)
    let root = makeSubjectFixture("ax_ce_dep_subject", DepSubjectSrc)
    let propEq5 = irEq(irLit(5), irVar("result", bv64))
    # classify(3) = enumTag(3)+1 = 4 — the solver-model claim (== 5) is
    # violated by the REAL subject → the violation reproduces → rvAgree.
    let cfgAgree = ReplayConfig(
      subjectRepoRoot: root,
      subjectModulePath: root / "subject_mod.nim",
      funcName: "classify",
      paramNames: @["x"],
      inputLiterals: @["3"],
      postconditions: @[propEq5],
      depSearchPaths: @[store])
    let agree = runCounterexampleReplay(cfgAgree)
    check agree.verdict == rvAgree
    check agree.exitCode == 0
    check agree.observedOutput.contains("AXIOM_REPLAY_BEGIN")
    check agree.observedOutput.contains("4")
    # The same harness WITHOUT the dep root cannot resolve `stew/enums` —
    # fail-closed rvUnavailable (this is the pre-Q4 defect observation).
    let cfgNoDeps = ReplayConfig(
      subjectRepoRoot: root,
      subjectModulePath: root / "subject_mod.nim",
      funcName: "classify",
      paramNames: @["x"],
      inputLiterals: @["3"],
      postconditions: @[propEq5])
    let unavail = runCounterexampleReplay(cfgNoDeps)
    check unavail.verdict == rvUnavailable
    check unavail.exitCode != 0
    check unavail.diagnostics.contains("harness nonzero exit")

# ─── Suite 8: self-kernel collateral resolution (quirks Q5/Q6) ──────────────

suite "counterexample_replay — self-kernel collateral resolution (Q5/Q6)":
  test "renderReplayHarness splices the subject with include (private symbols reachable)":
    # calcDynamicTimeoutCore is a PRIVATE kernel symbol — an `import` harness
    # can never expose it (pre-Q6 defect: "undeclared identifier" compile).
    let h = renderReplayHarness("orchestrator_topology_worker",
                                "calcDynamicTimeoutCore",
                                @["0", "0", "0", "0"])
    check h.startsWith("include orchestrator_topology_worker\n")
    check h.contains("echo $calcDynamicTimeoutCore(0, 0, 0, 0)")
    check h.contains(ReplayBeginMarker) and h.contains(ReplayEndMarker)
    # The S6 composite call form rides the same splice.
    let hc = renderReplayHarness("subject_mod", "f", @["7"],
                                 "outer(Carrier, inner(Carrier, 7))")
    check hc.startsWith("include subject_mod\n")
    check hc.contains("echo $outer(Carrier, inner(Carrier, 7))")

  test "nimbleRequiresNames reads the declarative contract; skips nim, dedups":
    const NimbleSrc = "requires \"nim >= 2.2.10\"\n" &
                      "requires \"malebolgia >= 1.3.0\"\n" &
                      "# requires \"ghost >= 9.9\" (commented out)\n" &
                      "requires \"checksums >= 0.2.0\", \"fusion >= 1.2\"\n" &
                      "requires \"nimcrypto >= 0.6.0\"\n"
    check nimbleRequiresNames(NimbleSrc) ==
      @["malebolgia", "checksums", "fusion", "nimcrypto"]
    check nimbleRequiresNames("").len == 0
    check nimbleRequiresNames("version 1.0\n").len == 0

  test "subjectRepoDepSearchPaths: empty inputs stay empty (no guessing)":
    check subjectRepoDepSearchPaths("", "").len == 0
    # A repo without a nimble file contributes only the toolchain root when
    # the measured nim binary carries compiler sources — never a guess.
    let bare = getTempDir() / "ax_ce_q5_bare"
    removeDir(bare)
    createDir(bare)
    let paths = subjectRepoDepSearchPaths(bare, getCurrentCompilerExe())
    for p in paths:
      check dirExists(p)

  test "ceReplayModulePath: analysis-root miss resolves through the repo root":
    let analysis = getTempDir() / "ax_ce_q6_analysis"
    let subject = getTempDir() / "ax_ce_q6_subject"
    removeDir(analysis)
    removeDir(subject)
    createDir(analysis / "src" / "deep")
    createDir(subject / "src" / "deep")
    writeFile(analysis / "src" / "deep" / "private_mod.nim", "func a(): int = 1\n")
    writeFile(subject / "src" / "deep" / "private_mod.nim", "func b(): int = 2\n")
    # The subject-root hit keeps priority (external subject, zero-diff).
    putEnv("AXIOM_ROOT", subject)
    check ceReplayModulePath(analysis, "src/deep/private_mod.nim") ==
      analysis / "src" / "deep" / "private_mod.nim"
    # The analysis-root miss falls through to the repo-root candidate —
    # this is the self-kernel collateral shape (cwd-independent).
    removeDir(analysis)
    createDir(analysis)
    check ceReplayModulePath(analysis, "src/deep/private_mod.nim") ==
      subject / "src" / "deep" / "private_mod.nim"
    delEnv("AXIOM_ROOT")

  test "in-repo private kernel entry: nested moduleDir + private symbol + module-repo identity":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_ce_replay_state")
    # The subject module's OWN repo (where the bytes and the commit live) —
    # a nested module dir, a PRIVATE function, no config file anywhere.
    let root = getTempDir() / "ax_ce_selfkernel_subject"
    removeDir(root)
    createDir(root / "src" / "deep")
    writeFile(root / "src" / "deep" / "private_mod.nim",
              "func hiddenShift(x: int): int = x * 2 + 1\n")
    discard execCmdEx("git -C \"" & root & "\" init -q",
                      options = {poStdErrToStdOut, poUsePath})
    discard execCmdEx("git -C \"" & root & "\" add -A",
                      options = {poStdErrToStdOut, poUsePath})
    discard execCmdEx("git -C \"" & root & "\" -c user.name=ax -c user.email=ax@test commit -q -m init",
                      options = {poStdErrToStdOut, poUsePath})
    # An unrelated "analysis root" (the external --project subject) must NOT
    # win the identity binding — the module's git toplevel does.
    let analysis = getTempDir() / "ax_ce_selfkernel_analysis"
    removeDir(analysis)
    createDir(analysis)
    writeFile(analysis / "other.nim", "func other(): int = 0\n")
    discard execCmdEx("git -C \"" & analysis & "\" init -q",
                      options = {poStdErrToStdOut, poUsePath})
    discard execCmdEx("git -C \"" & analysis & "\" add -A",
                      options = {poStdErrToStdOut, poUsePath})
    discard execCmdEx("git -C \"" & analysis & "\" -c user.name=ax -c user.email=ax@test commit -q -m init",
                      options = {poStdErrToStdOut, poUsePath})
    let propNonNeg = irLe(irLit(0), irVar("result", bv64))
    let cfg = ReplayConfig(
      subjectRepoRoot: analysis,
      subjectModulePath: root / "src" / "deep" / "private_mod.nim",
      funcName: "hiddenShift",
      paramNames: @["x"],
      inputLiterals: @["3"],
      postconditions: @[propNonNeg])
    let record = runCounterexampleReplay(cfg)
    # hiddenShift(3) = 7 ≥ 0 holds — the spurious solver claim is REFUTED by
    # the real toolchain: include-splice reached the PRIVATE symbol, the
    # nested moduleDir resolved, and the module's own repo bound the identity.
    check record.verdict == rvDisagree
    check record.exitCode == 0
    check record.subjectGitRef == gitCapture(root, "rev-parse HEAD")
    check record.subjectGitRef.len == 40
    check record.subjectGitRef != gitCapture(analysis, "rev-parse HEAD")
    check record.moduleSha256 == sha256Hex("func hiddenShift(x: int): int = x * 2 + 1\n")
    check record.worktreeStable
    check record.diagnostics.contains("replay disagrees with solver model")
