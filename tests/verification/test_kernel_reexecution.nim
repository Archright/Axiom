import std/[json, os, strutils]
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
checkEq("allowlist = INV-6 set", axiomAllowlist().join(","), "propext,Classical.choice,Quot.sound,funext")
checkEq("allowlist has 4 entries", $axiomAllowlist().len, "4")
checkTrue("propext allowed", isAxiomAllowed("propext"))
checkTrue("Classical.choice allowed", isAxiomAllowed("Classical.choice"))
checkTrue("Quot.sound allowed", isAxiomAllowed("Quot.sound"))
checkTrue("funext allowed", isAxiomAllowed("funext"))
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
checkVerdict("allowlisted set → PASS",
  evaluateObservedAxioms(AxiomPrintObservation(
    names: @["propext", "Classical.choice", "Quot.sound", "funext"], observedAny: true)), krPassed)
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
echo ""
echo "ALL KERNEL REEXECUTION TESTS PASSED (" & $passCount & " checks, " & $skipCount & " skipped)"
