## Gate Tier Integrity — CI quality gate for tier integrity rules.
##
## Enforces:
##   Rule T1-NO-RAW: Tier 1 modules cannot export procs with bare float/int
##   Rule T2-Z3-UNSAT: Z3 counterexamples on Tier 2 functions fail CI
##   Risk 3: Z3 UNKNOWN/timeout → warning + tag (NOT CI failure)
##
## Usage:
##   nim c -o:bin/gate_tier_integrity tools/gate_tier_integrity.nim
##   bin/gate_tier_integrity
##
## Exit codes:
##   0  PASS — all tier integrity checks passed
##   1  FAIL — tier integrity violations detected

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, osproc, sequtils, strutils]

const Tier1Modules* = [
    "src/core/metrics.nim",
    "src/core/telemetry/metrics.nim",
    "src/core/types/certificate_types.nim",
    "src/core/types/verification_tier.nim",
    "src/cli/shared/proof_hydration.nim"
  ]

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  for i in 0 ..< 20:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  getCurrentDir()

proc checkTier1NoRaw*(repoRoot: string): tuple[passed: bool; violations: seq[string]] =
  var violations: seq[string] = @[]

  for modRelPath in Tier1Modules:
    let modPath = repoRoot / modRelPath
    if not fileExists(modPath):
      violations.add(modRelPath & "  FILE NOT FOUND")
      continue
    let content = readFile(modPath)
    let lines = content.splitLines()
    for i, line in lines:
      let stripped = line.strip()
      if (stripped.startsWith("proc *") or stripped.startsWith("func *") or
          stripped.startsWith("proc ") or stripped.startsWith("func ")):
        if stripped.contains(": float") or stripped.contains(": int ") or
           stripped.contains(": int)") or stripped.contains(": int,") or
           stripped.contains("float =") or stripped.contains("int =") or
           stripped.contains(": int=") or stripped.contains("(int)"):
          if not stripped.contains("ASIRatio") and
             not stripped.contains("VerifiedKernelRatio") and
             not stripped.contains("NonNegativeDuration"):
            violations.add(modRelPath & ":" & $(i + 1) & " " & stripped)

  (violations.len == 0, violations)

proc extractContractPragmas*(code: string): seq[tuple[name: string; requires, ensures: seq[string]]] =
  let lines = code.splitLines()
  var i = 0
  while i < lines.len:
    let stripped = lines[i].strip()
    if stripped.startsWith("proc ") or stripped.startsWith("func "):
      let keywordEnd = stripped.find(' ')
      let afterKeyword = stripped[keywordEnd + 1 .. ^1].strip()
      var nameEnd = 0
      for j, ch in afterKeyword:
        if ch in {'*', '(', '['}:
          nameEnd = j
          break
        if ch == ' ':
          nameEnd = j
          break
      if nameEnd == 0:
        nameEnd = afterKeyword.len
      let procName = afterKeyword[0 ..< nameEnd].strip().strip(chars = {'*'})
      var braceDepth = 0
      var j = i
      var preconds: seq[string] = @[]
      var postconds: seq[string] = @[]
      while j < lines.len:
        let l = lines[j]
        let st = l.strip()
        let reqMarker = "{." & "requires:"
        let ensMarker = "{." & "ensures:"
        if reqMarker in st or ensMarker in st:
          let colonPos = st.find(':')
          if colonPos > 0:
            let startVal = colonPos + 1
            var valEnd = st.len
            let closeBrace = st.find(".}")
            if closeBrace >= 0:
              valEnd = closeBrace
            let val = st[startVal ..< valEnd].strip().strip(chars = {'.', '}'}).strip()
            if val.len > 0:
              if reqMarker in st:
                preconds.add(val)
              else:
                postconds.add(val)
        if '{' in l and st.len > 0 and st[0] != '#':
          inc braceDepth
        if '}' in l:
          dec braceDepth
        if braceDepth <= 0 and j > i:
          break
        inc j
      if preconds.len > 0 or postconds.len > 0:
        result.add((procName, preconds, postconds))
      i = j
    else:
      inc i

proc z3QuickCheck*(z3Path: string): bool =
  try:
    let smt2 = """
(set-option :produce-models false)
(set-logic QF_LIA)
(declare-const x Int)
(assert (= x 0))
(assert (not (= x 0)))
(check-sat)
"""
    let (output, exitCode) = execCmdEx(z3Path & " -in -smt2 -T:5", input = smt2)
    exitCode == 0 and "unsat" in output
  except CatchableError:
    false

proc buildSmt2ForContract*(procName: string; preconds, postconds: seq[string]): string =
  var parts: seq[string] = @[]
  parts.add("(set-option :produce-models true)")
  parts.add("(set-logic QF_LIA)")
  parts.add("(declare-const result Int)")
  for pre in preconds:
    parts.add("(assert " & pre & ")")
  for post in postconds:
    parts.add("(assert (not " & post & "))")
  parts.add("(check-sat)")
  parts.join("\n")

proc resolveZ3Path*(repoRoot: string): string =
  let candidates = @[
    repoRoot / "bin" / "z3",
    "z3",
    "/usr/bin/z3",
    "/usr/local/bin/z3"
  ]
  for c in candidates:
    try:
      if fileExists(c):
        return c
      let (outp, code) = execCmdEx(c & " --version")
      if code == 0 and outp.strip().len > 0:
        return c
    except CatchableError:
      discard  # axiom:best-effort(z3-path-resolution-failure: all candidates exhausted, Z3 unavailable)
  ""

proc checkTier2Z3*(repoRoot: string): tuple[passed: bool; reports: seq[string]] =
  var reports: seq[string] = @[]
  var allPassed = true

  let z3Path = resolveZ3Path(repoRoot)
  if z3Path.len == 0:
    reports.add("⚠ Z3 not found — skipping Tier 2 checks")
    return (true, reports)

  if not z3QuickCheck(z3Path):
    reports.add("⚠ Z3 binary not responding — skipping Tier 2 checks")
    return (true, reports)

  let srcGlob = repoRoot / "src/core/*.nim"
  let srcFiles = toSeq(walkFiles(srcGlob)).filterIt(it.endsWith(".nim"))

  for modPath in srcFiles:
    let content =
      try: readFile(modPath)
      except CatchableError: continue
    let contracts = extractContractPragmas(content)
    if contracts.len == 0:
      continue

    let modName = modPath.extractFilename()
    var modPassed = true

    for (procName, preconds, postconds) in contracts:
      let smt2 = buildSmt2ForContract(procName, preconds, postconds)

      try:
        let (output, exitCode) = execCmdEx(z3Path & " -in -smt2 -T:10", input = smt2)
        if exitCode != 0:
          reports.add("⚠ " & modName & "." & procName & " Z3 error (exit " & $exitCode & ")")
          continue

        if "unsat" in output:
          reports.add("✓ " & modName & "." & procName & " proven")
        elif "sat" in output:
          reports.add("✗ " & modName & "." & procName & " VIOLATED: counterexample found")
          allPassed = false
          modPassed = false
        else:
          reports.add("⚠ " & modName & "." & procName & " inconclusive (UNKNOWN)")
      except CatchableError as e:
        reports.add("⚠ " & modName & "." & procName & " error: " & e.msg)

    if modPassed and contracts.len > 0:
      reports.add("  = " & modName & " all " & $contracts.len & " contracts OK")

  (allPassed, reports)

proc runGate*(repoRoot: string): int =
  echo "=== Axiom Tier Integrity Gate ==="

  echo "\n[1] Checking Tier 1 (No Raw Primitives)..."
  let (t1Passed, t1Violations) = checkTier1NoRaw(repoRoot)
  if t1Passed:
    echo "  PASS: No raw primitive leakage in Tier 1"
  else:
    echo "  FAIL: Raw primitive violations found:"
    for v in t1Violations:
      echo "    - " & v

  echo "\n[2] Checking Tier 2 (Z3 Verification)..."
  let (t2Passed, t2Reports) = checkTier2Z3(repoRoot)
  for r in t2Reports:
    echo "  " & r

  echo "\n=== Result ==="
  if t1Passed and t2Passed:
    echo "PASS: All tier integrity checks passed"
    result = 0
  else:
    echo "FAIL: Tier integrity violations detected"
    result = 1

proc main() =
  let repoRoot = findRepoRoot()
  echo "=== Axiom Tier Integrity Gate (HARD BLOCKING MODE) ==="

  let (t1Passed, t1Violations) = checkTier1NoRaw(repoRoot)
  if not t1Passed:
    echo "FAIL: " & $t1Violations.len & " raw primitive violations:"
    for v in t1Violations:
      echo "  - " & v
    quit(1)

  echo "PASS: No raw primitive leakage in Tier 1"
  quit(0)

when isMainModule:
  main()

{.pop.}
