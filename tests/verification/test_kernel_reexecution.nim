import std/[json, os, strutils]
import core/crypto/hash_kernel
import core/results
import verification/kernel_reexecution

## ═══════════════════════════════════════════════════════════════════════
## KernelReexecution — certification continuity Phase 3 tests
##
## Coverage:
##   P1  allowlist contents + isAxiomAllowed deny-first semantics
##   P2  #print axioms output parsing (empty / bracket / multiline)
##   P3  observed-axiom evaluation (INV-6 allowlist, sorry, deny markers)
##   P4  z3 verdict mapping (INV-10 fail-closed)
##   P5  composeKernelVerdict (all evidence classes must pass)
##   P6  missing leanSource/smtlib2 → krMissingInput (no tool needed)
##   P7  malformed cert JSON → fail-closed err, never crash
##   P8  real lean re-execution: trivial / sorry / native_decide /
##       forbidden axiom / timeout  (SKIP loudly if lean absent)
##   P9  real z3 re-execution: unsat pass / sat mismatch
##       (SKIP loudly if z3 absent — CI stays green without z3)
##   P10 leanchecker independent deep check (Phase 6): absent checker →
##       lcSkipped additive; fresh-compile re-validation pass/mismatch
##       (SKIP loudly if leanchecker absent)
##   P11 VS-188 observations: observed return, theorem binding, ambiguous
##       target, hazard rejection, observation self-consistency (real tools
##       gated for the execution legs)
##   P12 leanchecker probe recorded in skippedChecks (label, not a silent skip)
## ═══════════════════════════════════════════════════════════════════════

var passCount = 0
var skipCount = 0

proc checkEq(name: string; got, exp: string) =
  if got == exp:
    echo "  [PASS] ", name
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", got, "\n      exp: ", exp
    quit(1)

proc checkTrue(name: string; cond: bool) =
  if cond:
    echo "  [PASS] ", name
    inc passCount
  else:
    echo "  [FAIL] ", name
    quit(1)

proc checkVerdict[T](name: string; got, exp: T) =
  if got == exp:
    echo "  [PASS] ", name, " -> ", $got
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", $got, "\n      exp: ", $exp
    quit(1)

proc skip(name: string; reason: string) =
  echo "  [SKIP] ", name, " (", reason, ") — test skipped, exit 0"
  inc skipCount

proc leanAvailable(): bool =
  findExe("lake").len > 0 and findExe("lean").len > 0

proc z3Available(): bool =
  fileExists(getHomeDir() / ".local" / "bin" / "z3") or findExe("z3").len > 0

proc makeCert(leanSource: string; smtlib2: string = ""): JsonNode =
  var node = newJObject()
  node["status"] = %"passed"
  node["leanSource"] = %leanSource
  if smtlib2.len > 0:
    node["smtlib2"] = %smtlib2
  node

# ---------------------------------------------------------------------------
# P1 — allowlist + deny-first semantics (pure, always runs)
# ---------------------------------------------------------------------------
echo "=== P1: allowlist ==="
checkEq("allowlist = INV-6 set", axiomAllowlist().join(","), "propext,Classical.choice,Quot.sound")
checkEq("allowlist has 3 entries", $axiomAllowlist().len, "3")
checkTrue("propext allowed", isAxiomAllowed("propext"))
checkTrue("Classical.choice allowed", isAxiomAllowed("Classical.choice"))
checkTrue("Quot.sound allowed", isAxiomAllowed("Quot.sound"))
checkTrue("funext denied (theorem alias, not a primitive axiom)", not isAxiomAllowed("funext"))
checkTrue("empty name NEVER allowed", not isAxiomAllowed(""))
checkTrue("sorryAx denied", not isAxiomAllowed("sorryAx"))
checkTrue("Lean.sorryAx denied", not isAxiomAllowed("Lean.sorryAx"))
checkTrue("native_decide synthetic name denied", not isAxiomAllowed("tNative._native.native_decide.ax_1_1"))
checkTrue("Lean.trustCompiler denied", not isAxiomAllowed("Lean.trustCompiler"))
checkTrue("lowercase trustcompiler denied", not isAxiomAllowed("lean.trustcompiler"))
checkTrue("custom axiom denied", not isAxiomAllowed("badFalse"))
checkTrue("allowlist lookalike denied (not exact)", not isAxiomAllowed("propext.foo"))
checkTrue("whitespace name denied (not exact)", not isAxiomAllowed(" propext"))

# ---------------------------------------------------------------------------
# P2 — #print axioms output parsing (pure, always runs)
# ---------------------------------------------------------------------------
echo "=== P2: print-axioms parsing ==="
let emptyObs = parsePrintAxiomsObservations("")
checkTrue("no output → no observation (fail-closed)", not emptyObs.observedAny)
checkEq("no output → no names", $emptyObs.names.len, "0")
let pureObs = parsePrintAxiomsObservations("'t' does not depend on any axioms\n")
checkTrue("kernel-pure line → observed", pureObs.observedAny)
checkEq("kernel-pure line → empty set", $pureObs.names.len, "0")
let sorryObs = parsePrintAxiomsObservations(
  "warning: declaration uses `sorry`\n'bad' depends on axioms: [sorryAx]\n")
checkTrue("sorryAx observation parsed", sorryObs.observedAny)
checkEq("sorryAx name extracted", sorryObs.names.join(","), "sorryAx")
let multiObs = parsePrintAxiomsObservations(
  "'t' depends on axioms: [propext, Classical.choice, Quot.sound, funext]")
checkEq("multi-axiom bracket parsed", multiObs.names.join(","),
  "propext,Classical.choice,Quot.sound,funext")
let lineWrappedObs = parsePrintAxiomsObservations(
  "'t' depends on axioms: [propext,\n  Quot.sound,\n  funext]\n")
checkEq("multiline bracket parsed", lineWrappedObs.names.join(","), "propext,Quot.sound,funext")
let twoTheoremsObs = parsePrintAxiomsObservations(
  "'a' does not depend on any axioms\n'b' depends on axioms: [Classical.choice]\n")
checkTrue("two observation blocks", twoTheoremsObs.observedAny)
checkEq("two observation blocks: union", twoTheoremsObs.names.join(","), "Classical.choice")
let malformedObs = parsePrintAxiomsObservations("'t' depends on axioms: sorryAx\n")
checkTrue("bracketless marker → NOT an observation (fail-closed)", not malformedObs.observedAny)
checkTrue("warning-only output → no observation", not parsePrintAxiomsObservations("warning: x\n").observedAny)

# ---------------------------------------------------------------------------
# P3 — observed-axiom evaluation (pure, always runs)
# ---------------------------------------------------------------------------
echo "=== P3: axiom evaluation (INV-6) ==="
checkVerdict("kernel-pure empty set → PASS",
  evaluateObservedAxioms(AxiomPrintObservation(names: @[], observedAny: true)), krPassed)
checkVerdict("full primitive set → PASS",
  evaluateObservedAxioms(AxiomPrintObservation(
    names: @["propext", "Classical.choice", "Quot.sound"], observedAny: true)), krPassed)
checkVerdict("funext (theorem alias, not primitive) → krAxiomViolation",
  evaluateObservedAxioms(AxiomPrintObservation(
    names: @["propext", "Classical.choice", "Quot.sound", "funext"], observedAny: true)), krAxiomViolation)
checkVerdict("sorryAx → krSorry",
  evaluateObservedAxioms(AxiomPrintObservation(names: @["sorryAx"], observedAny: true)), krSorry)
checkVerdict("Lean.sorryAx → krSorry",
  evaluateObservedAxioms(AxiomPrintObservation(names: @["Lean.sorryAx"], observedAny: true)), krSorry)
checkVerdict("Lean.trustCompiler → krAxiomViolation",
  evaluateObservedAxioms(AxiomPrintObservation(names: @["Lean.trustCompiler"], observedAny: true)), krAxiomViolation)
checkVerdict("native_decide synthetic → krAxiomViolation",
  evaluateObservedAxioms(AxiomPrintObservation(names: @["tX._native.native_decide.ax_1_1"], observedAny: true)), krAxiomViolation)
checkVerdict("custom axiom → krAxiomViolation",
  evaluateObservedAxioms(AxiomPrintObservation(names: @["badFalse"], observedAny: true)), krAxiomViolation)
checkVerdict("mixed allowed+forbidden → violation wins",
  evaluateObservedAxioms(AxiomPrintObservation(names: @["propext", "badFalse"], observedAny: true)), krAxiomViolation)
checkVerdict("no observation → krMissingInput (cannot attest)",
  evaluateObservedAxioms(AxiomPrintObservation(names: @[], observedAny: false)), krMissingInput)

# ---------------------------------------------------------------------------
# P4 — z3 verdict mapping (pure, always runs)
# ---------------------------------------------------------------------------
echo "=== P4: z3 verdict mapping (INV-10) ==="
checkVerdict("fresh unsat → PASS", z3ResultVerdict(0, false, "unsat\n"), krPassed)
checkVerdict("unsat with model text → PASS", z3ResultVerdict(0, false, "sat-binding…\nunsat"), krPassed)
checkVerdict("sat → krZ3Mismatch", z3ResultVerdict(0, false, "sat\n(model ...)"), krZ3Mismatch)
checkVerdict("unknown → krZ3Mismatch", z3ResultVerdict(0, false, "unknown"), krZ3Mismatch)
checkVerdict("non-zero exit → krZ3Mismatch", z3ResultVerdict(1, false, ""), krZ3Mismatch)
checkVerdict("timeout → krTimeout", z3ResultVerdict(-1, true, ""), krTimeout)

# ---------------------------------------------------------------------------
# P5 — composeKernelVerdict (pure, always runs)
# ---------------------------------------------------------------------------
echo "=== P5: verdict composition ==="
checkVerdict("no evidence at all → krMissingInput (fail-closed)",
  composeKernelVerdict(krPassed, krPassed, false, false), krMissingInput)
checkVerdict("lean-only pass → PASS",
  composeKernelVerdict(krPassed, krPassed, true, false), krPassed)
checkVerdict("z3-only pass → PASS",
  composeKernelVerdict(krPassed, krPassed, false, true), krPassed)
checkVerdict("dual pass → PASS",
  composeKernelVerdict(krPassed, krPassed, true, true), krPassed)
checkVerdict("lean violation dominates",
  composeKernelVerdict(krSorry, krPassed, true, true), krSorry)
checkVerdict("z3 mismatch fails",
  composeKernelVerdict(krPassed, krZ3Mismatch, true, true), krZ3Mismatch)
checkVerdict("lean timeout fails",
  composeKernelVerdict(krTimeout, krPassed, true, false), krTimeout)

# ---------------------------------------------------------------------------
# P6 — missing inputs → krMissingInput (no tool required)
# ---------------------------------------------------------------------------
echo "=== P6: missing inputs ==="
let noLeanCert = makeCert("")
checkVerdict("missing leanSource → krMissingInput",
  reexecuteLean(noLeanCert, "", 5_000), krMissingInput)
let noSmtCert = makeCert("theorem t : True := trivial")
checkVerdict("missing smtlib2 → krMissingInput",
  reexecuteZ3(noSmtCert, "", 5_000), krMissingInput)
checkVerdict("nil cert → krMissingInput", reexecuteLean(nil, "", 5_000), krMissingInput)
checkVerdict("nil cert → krMissingInput (z3)", reexecuteZ3(nil, "", 5_000), krMissingInput)
let satSmtCert = makeCert("", "(declare-const x Int)\n(assert (= x 1))\n(check-sat)")
checkVerdict("missing z3 binary → krZ3Error (fail-closed)",
  reexecuteZ3(satSmtCert, "/nonexistent/z3-missing", 5_000), krZ3Error)
checkVerdict("unpinned binary → krZ3Error (checksum policy fails closed)",
  reexecuteZ3(satSmtCert, "/bin/true", 5_000), krZ3Error)

# ---------------------------------------------------------------------------
# P7 — malformed cert JSON → fail-closed err (no tool required)
# ---------------------------------------------------------------------------
echo "=== P7: malformed cert JSON ==="
let badJson = loadCertJsonForReexecution("/nonexistent/cert.json")
checkTrue("missing file → err", badJson.isErr)
checkTrue("missing file reason mentions unreadable", badJson.error.contains("unreadable"))
let malformedPath = getTempDir() / "axiom_kreexec_malformed_cert.json"
writeFile(malformedPath, "{not json")
let malformedLoad = loadCertJsonForReexecution(malformedPath)
checkTrue("malformed JSON → err (never crash)", malformedLoad.isErr)
checkTrue("malformed reason mentions JSON", malformedLoad.error.contains("malformed"))
writeFile(malformedPath, "[1, 2, 3]")
checkTrue("non-object JSON → err", loadCertJsonForReexecution(malformedPath).isErr)
writeFile(malformedPath, "{\"leanSource\":\"theorem t : True := trivial\"}")
let goodLoad = loadCertJsonForReexecution(malformedPath)
checkTrue("well-formed cert loads ok", goodLoad.isOk)
removeFile(malformedPath)

# ---------------------------------------------------------------------------
# P8 — real lean re-execution (SKIP loudly if lean absent)
# ---------------------------------------------------------------------------
echo "=== P8: real lean re-execution ==="
if leanAvailable():
  checkVerdict("trivial theorem → krPassed",
    reexecuteLean(makeCert("theorem t : True := trivial\n#print axioms t"), "", 120_000), krPassed)
  checkVerdict("auto-appended #print axioms → krPassed",
    reexecuteLean(makeCert("theorem t2 : True := trivial"), "", 120_000), krPassed)
  checkVerdict("sorry proof → krSorry",
    reexecuteLean(makeCert("theorem bad : False := by sorry\n#print axioms bad"), "", 120_000), krSorry)
  checkVerdict("native_decide proof → krAxiomViolation",
    reexecuteLean(makeCert("theorem tN : 1 + 1 = 2 := by native_decide\n#print axioms tN"), "", 120_000), krAxiomViolation)
  checkVerdict("custom axiom bad : False → krAxiomViolation",
    reexecuteLean(makeCert("axiom bad : False\n#print axioms bad"), "", 120_000), krAxiomViolation)
  checkVerdict("allowlisted axiom proof → krPassed",
    reexecuteLean(makeCert(
      "theorem tP : (True ∧ True) = True := by simp\n#print axioms tP"), "", 120_000), krPassed)
  checkVerdict("compile error → krCompileError",
    reexecuteLean(makeCert("theorem tBroken : False := by simp"), "", 120_000), krCompileError)
  checkVerdict("timeoutMs=1 → krTimeout",
    reexecuteLean(makeCert("theorem tSlow : True := trivial"), "", 1), krTimeout)
else:
  skip("real lean re-execution suite", "lean/lake not found")
  skip("lean timeout path", "lean/lake not found")

# ---------------------------------------------------------------------------
# P9 — real z3 re-execution (SKIP loudly if z3 absent)
# ---------------------------------------------------------------------------
echo "=== P9: real z3 re-execution ==="
if z3Available():
  checkVerdict("fresh unsat query → krPassed",
    reexecuteZ3(makeCert("", "(declare-const x Int)\n(assert (and (> x 0) (< x 0)))\n(check-sat)"), "", 60_000), krPassed)
  checkVerdict("sat query (mutated vs recorded unsat) → krZ3Mismatch",
    reexecuteZ3(makeCert("", "(declare-const x Int)\n(assert (= x 1))\n(check-sat)"), "", 60_000), krZ3Mismatch)
else:
  skip("real z3 re-execution suite", "z3 not found")

# ---------------------------------------------------------------------------
# P6b — z3 checksum pinning (INV-10, no tool required for the mismatch leg)
# ---------------------------------------------------------------------------
echo "=== P6b: checksum pinning ==="
checkTrue("unpinned binary /bin/true rejects", not z3BinaryChecksumAccepted("/bin/true"))
checkTrue("nonexistent binary rejects", not z3BinaryChecksumAccepted("/nonexistent/z3"))
if z3Available():
  let pinnedZ3 = if fileExists(getHomeDir() / ".local" / "bin" / "z3"):
    getHomeDir() / ".local" / "bin" / "z3" else: findExe("z3")
  checkTrue("local z3 binary is checksum-pinned", z3BinaryChecksumAccepted(pinnedZ3))
else:
  skip("local z3 pin check", "z3 not found")

# ---------------------------------------------------------------------------
# P10 — leanchecker independent deep check (Phase 6; SKIP loudly if absent)
# ---------------------------------------------------------------------------
echo "=== P10: leanchecker deep check ==="
checkVerdict("no leanSource → lcSkipped (nothing to validate)",
  checkLeanWithLeanChecker(newJObject()), lcSkipped)
checkVerdict("explicit nonexistent checker → lcSkipped (additive)",
  checkLeanWithLeanChecker(makeCert("theorem t : True := trivial"), "", "/nonexistent/leanchecker"),
  lcSkipped)
if leanAvailable() and findExe("leanchecker").len > 0:
  checkVerdict("trivial theorem → lcPassed (fresh compile + re-validation)",
    checkLeanWithLeanChecker(makeCert("theorem axiom_lcheck_prop : True := by trivial")),
    lcPassed)
  checkVerdict("uncompilable source → lcMismatch (fail-closed)",
    checkLeanWithLeanChecker(makeCert("theorem broken : False :=")),
    lcMismatch)
else:
  skip("real leanchecker deep-check suite", "lean/lake or leanchecker not found")

# ---------------------------------------------------------------------------
# P11 — VS-188 observations: target binding, hazards, observed runs
# ---------------------------------------------------------------------------
echo "=== P11: VS-188 observation target + hazards (pure) ==="
checkEq("single theorem binds", leanObservationTarget(
  "theorem obs_single : True := trivial").target, "obs_single")
checkEq("single theorem has no problem", leanObservationTarget(
  "theorem obs_single : True := trivial").problem, "")
checkEq("explicit #print axioms wins", leanObservationTarget(
  "theorem obs_a : True := trivial\n#print axioms obs_other").target, "obs_other")
checkTrue("zero theorems → problem", leanObservationTarget(
  "def obs_def := 1").problem.len > 0)
checkTrue("two theorems → ambiguous problem", leanObservationTarget(
  "theorem obs_a : True := trivial\ntheorem obs_b : True := trivial").problem.len > 0)
checkEq("private theorem binds", leanObservationTarget(
  "private theorem obs_private : True := trivial").target, "obs_private")
checkEq("attributed theorem binds", leanObservationTarget(
  "@[simp] theorem obs_attr : True := trivial").target, "obs_attr")
checkEq("namespace-qualified theorem binds", leanObservationTarget(
  "namespace ObsN\ntheorem obs_ns : True := trivial\nend ObsN").target, "ObsN.obs_ns")
checkTrue("hazard: debug.skipKernelTC", "debug.skipKernelTC" in leanSourceHazards(
  "set_option debug.skipKernelTC true\ntheorem obs_h : True := trivial"))
checkTrue("hazard: run_cmd", "run_cmd" in leanSourceHazards(
  "theorem obs_h : True := trivial\nrun_cmd pure ()"))
checkTrue("hazard: #eval", "#eval" in leanSourceHazards(
  "theorem obs_h : True := trivial\n#eval 1"))
checkTrue("comments do not trigger hazards", leanSourceHazards(
  "-- #eval run_cmd debug.skipKernelTC in a comment\ntheorem obs_ok : True := trivial").len == 0)

let missingLeanObs = reexecuteLeanObservedKernel(makeCert(""), "", 5_000)
checkTrue("missing leanSource → unobserved (observed variant)", not missingLeanObs.observed)
checkVerdict("missing leanSource → krMissingInput (observed variant)",
  missingLeanObs.verdict, krMissingInput)
let hazardObs = reexecuteLeanObservedKernel(makeCert(
  "set_option debug.skipKernelTC true\ntheorem obs_h : True := trivial"),
  "/nonexistent/lean", 1_000)
checkVerdict("hazard source → krMissingInput (no new verdict)", hazardObs.verdict, krMissingInput)
checkTrue("hazard is recorded in skippedChecks", hazardObs.skippedChecks.len == 1 and
  hazardObs.skippedChecks[0].startsWith("lean-hazard:"))
let ambiguousObs = reexecuteLeanObservedKernel(makeCert(
  "theorem obs_a : True := trivial\ntheorem obs_b : True := trivial"),
  "/nonexistent/lean", 1_000)
checkVerdict("ambiguous target → krMissingInput", ambiguousObs.verdict, krMissingInput)
checkTrue("ambiguous target recorded in skippedChecks", ambiguousObs.skippedChecks.len == 1 and
  ambiguousObs.skippedChecks[0].startsWith("lean-target:"))

const ObsLeanSource = "theorem obs_real : True := by trivial"
const ObsSmt = "(declare-const x Int)\n(assert (and (> x 0) (< x 0)))\n(check-sat)"
if leanAvailable() and z3Available():
  let leanObs = reexecuteLeanObservedKernel(makeCert(ObsLeanSource), "", 120_000)
  checkTrue("real lean observation is observed", leanObs.observed)
  checkVerdict("real lean observation passed", leanObs.verdict, krPassed)
  checkEq("observation binds the selected theorem", leanObs.theoremName, "obs_real")
  checkEq("kernel-pure theorem → empty observed axiom set", leanObs.axiomSet.join(","), "")
  checkEq("leanSourceDigest binds the exact source",
    leanObs.leanSourceDigest, sha256Hex(ObsLeanSource))
  checkTrue("lean outputDigest recorded (64 hex)", leanObs.outputDigest.len == 64)
  if findExe("leanchecker").len > 0:
    checkTrue("present leanchecker → no unavailable marker",
      leanCheckerUnavailableMarker notin leanObs.skippedChecks)
  else:
    checkTrue("absent leanchecker → loud skippedChecks marker",
      leanCheckerUnavailableMarker in leanObs.skippedChecks)
  let z3Obs = reexecuteZ3Observed(makeCert("", ObsSmt), "", 60_000)
  checkTrue("real z3 observation is observed", z3Obs.observed)
  checkVerdict("real z3 observation passed", z3Obs.verdict, krPassed)
  checkEq("z3 queryDigest binds the exact query", z3Obs.queryDigest, sha256Hex(ObsSmt))
  checkTrue("z3 outputDigest recorded", z3Obs.outputDigest.len == 64)
  checkTrue("z3 binaryDigest recorded", z3Obs.binaryDigest.len == 64)
  let dual = KernelObservation(lean: leanObs, z3: z3Obs,
    verificationMode: observationVerificationMode(leanObs.observed, z3Obs.observed))
  checkEq("dual observation mode", dual.verificationMode, "lean+z3")
  checkEq("dual observation validates clean",
    kernelObservationValidationError(dual, ObsLeanSource, ObsSmt), "")
  checkTrue("dual observation is a passing observation",
    isPassingKernelObservation(dual, ObsLeanSource, ObsSmt))
  let obsNode = kernelObservationJson(dual)
  let obsRoundTrip = parseKernelObservation(obsNode)
  checkTrue("observation JSON round-trips", obsRoundTrip.isOk)
  if obsRoundTrip.isOk:
    checkEq("observationDigest is stable across the round-trip",
      kernelObservationDigest(obsRoundTrip.get), kernelObservationDigest(dual))
  var tamperedAxioms = dual
  tamperedAxioms.lean.axiomSet = @["sorryAx"]
  checkTrue("tampered axiom set fails validation",
    kernelObservationValidationError(tamperedAxioms, ObsLeanSource, ObsSmt).len > 0)
  checkTrue("tampered axiom set is not a passing observation",
    not isPassingKernelObservation(tamperedAxioms, ObsLeanSource, ObsSmt))
  checkTrue("leanSource digest mismatch fails validation",
    kernelObservationValidationError(dual, ObsLeanSource & "\n", ObsSmt).len > 0)
  checkTrue("smtlib2 digest mismatch fails validation",
    kernelObservationValidationError(dual, ObsLeanSource, ObsSmt & "\n").len > 0)
  var flippedMode = dual
  flippedMode.verificationMode = "lean-only"
  checkTrue("mode inconsistent with observed flags fails validation",
    kernelObservationValidationError(flippedMode, ObsLeanSource, ObsSmt).len > 0)
else:
  skip("real observation suite", "lean/z3 not found")

# ---------------------------------------------------------------------------
# P12 — leanchecker probe label (VS-188 Phase 1)
# ---------------------------------------------------------------------------
echo "=== P12: leanchecker probe recorded in the observation ==="
if leanAvailable():
  let probeObs = reexecuteLeanObservedKernel(makeCert(ObsLeanSource), "", 120_000)
  checkTrue("leanchecker probe is an explicit skippedChecks contract",
    (findExe("leanchecker").len > 0 and probeObs.skippedChecks.len == 0) or
    (findExe("leanchecker").len == 0 and
      leanCheckerUnavailableMarker in probeObs.skippedChecks))
else:
  skip("leanchecker probe label", "lean/lake not found")

# ---------------------------------------------------------------------------
echo ""
echo "ALL KERNEL REEXECUTION TESTS PASSED (" & $passCount & " checks, " & $skipCount & " skipped)"
