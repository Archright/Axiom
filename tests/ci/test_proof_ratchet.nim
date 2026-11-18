## test_proof_ratchet.nim — end-to-end fixtures for tools/ci/proof_ratchet.nim.
##
## Each fixture spawns the real binary so exit codes and the verdict document
## are exercised, not just the internal projection. The binary is built by the
## same workflow step that runs this test:
##   nim c -o:bin/proof_ratchet tools/ci/proof_ratchet.nim
##   nim c -r tests/ci/test_proof_ratchet.nim
##
## Override the binary path with PROOF_RATCHET_BIN for local runs.

import std/[json, os, osproc, strutils]

const
  Binary = "bin/proof_ratchet"

var failures = 0

proc binPath(): string =
  let fromEnv = getEnv("PROOF_RATCHET_BIN")
  if fromEnv.len > 0: fromEnv else: Binary

proc check(condition: bool; label, detail: string) =
  if condition:
    echo "PASS ", label
  else:
    echo "FAIL ", label, ": ", detail
    inc failures

proc writeJson(path: string; node: JsonNode) =
  writeFile(path, pretty(node, 2) & "\n")

proc runRatchet(args: openArray[string]): tuple[code: int, output: string] =
  var cmd = quoteShell(binPath())
  for arg in args:
    cmd.add(" ")
    cmd.add(quoteShell(arg))
  let res = execCmdEx(cmd)
  (res.exitCode, res.output)

proc scopeLock(kernelSymbols: openArray[string]): JsonNode =
  result = %*{"schema_version": 3, "kernel_total": kernelSymbols.len}
  var symbols = newJArray()
  for symbol in kernelSymbols:
    symbols.add(%symbol)
  result["kernel_symbols"] = symbols

proc unitRow(unitId, requirement, outcome: string): JsonNode =
  %*{
    "unitId": unitId,
    "requirementDecision": requirement,
    "verificationOutcome": outcome,
    "consistency": "CONSISTENT",
    "executionEvidence": "ATTEMPTED",
    "satisfactionSource": "FRESH"
  }

proc stateDoc(units: seq[JsonNode]; satisfied: int; unsatisfied: int): JsonNode =
  var unitArray = newJArray()
  for unit in units:
    unitArray.add(unit)
  result = %*{
    "runAccounting": {
      "requiredCount": units.len,
      "satisfiedCount": satisfied,
      "unsatisfiedCount": unsatisfied,
      "pendingCount": 0,
      "contestedCount": 0,
      "units": unitArray,
      "runOutcome": {
        "planComplete": true,
        "executionComplete": true,
        "verificationComplete": (unsatisfied == 0)
      }
    },
    "runOutcome": {"verdict": (if unsatisfied == 0: "PROVEN" else: "FAIL")}
  }

proc main(): int =
  let workdir = getTempDir() / ("proof_ratchet_test_" & $getCurrentProcessId())
  removeDir(workdir)
  createDir(workdir)

  let scopePath = workdir / "scope.json"
  writeJson(scopePath, scopeLock([
    "src/a.nim::alpha",
    "src/b.nim::beta",
    "src/c.nim::gamma",
  ]))

  let fullUnits = @[
    unitRow("src/a.nim::alpha", "REQUIRED", "SATISFIED"),
    unitRow("src/b.nim::beta", "REQUIRED", "SATISFIED"),
    unitRow("src/c.nim::gamma", "REQUIRED", "UNSATISFIED"),
  ]
  let fullState = workdir / "full.json"
  writeJson(fullState, stateDoc(fullUnits, satisfied = 2, unsatisfied = 1))

  let baselinePath = workdir / "baseline.json"
  let emit = runRatchet([
    "--emit-baseline", "--state", fullState, "--scope-lock", scopePath,
    "--subject-sha", "aaa", "--subject-tree", "ttt",
    "--run-id", "1", "--out", baselinePath,
  ])
  check(emit.code == 0, "fixture-1a emit-baseline exits 0", emit.output)
  check(fileExists(baselinePath), "fixture-1a baseline written", baselinePath)

  # 1 — exact match, under a DIFFERENT subject: the lock is over the
  # inventory, not over the tree that produced it.
  block:
    let verdictPath = workdir / "v1.json"
    let res = runRatchet([
      "--compare", "--baseline", baselinePath, "--state", fullState,
      "--scope-lock", scopePath, "--subject-sha", "bbb", "--out", verdictPath,
    ])
    let verdict = parseFile(verdictPath)
    check(res.code == 0 and verdict["verdict"].getStr() == "MATCH",
          "fixture-1 exact inventory MATCHes (exit 0)",
          res.output & " " & $verdict["verdict"])
    check(verdict["subjectChanged"].getBool(),
          "fixture-1 subject change is reported, not hashed",
          $verdict["subjectChanged"])
    check(verdict["digestMatches"].getBool(),
          "fixture-1 digest is subject-independent", $verdict["digestMatches"])

  # 2 — a unit disappears: scope regression, the direction that matters most.
  block:
    let verdictPath = workdir / "v2.json"
    let reduced = workdir / "reduced.json"
    writeJson(reduced, stateDoc(fullUnits[0 .. 1], satisfied = 2, unsatisfied = 0))
    let res = runRatchet([
      "--compare", "--baseline", baselinePath, "--state", reduced,
      "--scope-lock", scopePath, "--subject-sha", "ccc", "--out", verdictPath,
    ])
    let verdict = parseFile(verdictPath)
    let reasons = verdict["reasons"]
    check(res.code == 1 and verdict["verdict"].getStr() == "MISMATCH",
          "fixture-2 dropped unit MISMATCHes (exit 1)",
          res.output & " " & $verdict["verdict"])
    check(reasons.contains(%"units-removed"),
          "fixture-2 reason units-removed", $reasons)
    check(verdict["diff"]["unitsRemoved"][0].getStr() == "src/c.nim::gamma",
          "fixture-2 diff names the dropped unit",
          $verdict["diff"]["unitsRemoved"])

  # 3 — a unit is added.
  block:
    let verdictPath = workdir / "v3.json"
    let expanded = workdir / "expanded.json"
    var units = fullUnits
    units.add(unitRow("src/d.nim::delta", "REQUIRED", "SATISFIED"))
    writeJson(expanded, stateDoc(units, satisfied = 3, unsatisfied = 1))
    let res = runRatchet([
      "--compare", "--baseline", baselinePath, "--state", expanded,
      "--scope-lock", scopePath, "--subject-sha", "ccc", "--out", verdictPath,
    ])
    let verdict = parseFile(verdictPath)
    check(res.code == 1 and
          verdict["reasons"].contains(%"units-added"),
          "fixture-3 added unit MISMATCHes with units-added",
          $verdict["reasons"])

  # 4 — an outcome changes in the FAILING direction.
  block:
    let verdictPath = workdir / "v4.json"
    let regressed = workdir / "regressed.json"
    let units = @[
      unitRow("src/a.nim::alpha", "REQUIRED", "UNSATISFIED"),
      unitRow("src/b.nim::beta", "REQUIRED", "SATISFIED"),
      unitRow("src/c.nim::gamma", "REQUIRED", "UNSATISFIED"),
    ]
    writeJson(regressed, stateDoc(units, satisfied = 1, unsatisfied = 2))
    let res = runRatchet([
      "--compare", "--baseline", baselinePath, "--state", regressed,
      "--scope-lock", scopePath, "--subject-sha", "ccc", "--out", verdictPath,
    ])
    let verdict = parseFile(verdictPath)
    check(res.code == 1 and
          verdict["reasons"].contains(%"unit-outcome-changed"),
          "fixture-4 outcome regression MISMATCHes",
          $verdict["reasons"])
    let changed = verdict["diff"]["unitsChanged"][0]
    check(changed["unitId"].getStr() == "src/a.nim::alpha" and
          changed["fields"]["verificationOutcome"]["baseline"].getStr() ==
            "SATISFIED",
          "fixture-4 diff carries from/to values", $changed)

  # 5 — an IMPROVEMENT also MISMATCHes: exact lock, not a monotonic ratchet.
  block:
    let verdictPath = workdir / "v5.json"
    let improved = workdir / "improved.json"
    let units = @[
      unitRow("src/a.nim::alpha", "REQUIRED", "SATISFIED"),
      unitRow("src/b.nim::beta", "REQUIRED", "SATISFIED"),
      unitRow("src/c.nim::gamma", "REQUIRED", "SATISFIED"),
    ]
    writeJson(improved, stateDoc(units, satisfied = 3, unsatisfied = 0))
    let res = runRatchet([
      "--compare", "--baseline", baselinePath, "--state", improved,
      "--scope-lock", scopePath, "--subject-sha", "ccc", "--out", verdictPath,
    ])
    let verdict = parseFile(verdictPath)
    check(res.code == 1,
          "fixture-5 improvement is a MISMATCH (exact lock, not monotonic)",
          $verdict["verdict"])

  # 6 — counts disagree with rows: engine-internal inconsistency is a failure,
  # never a silent pass.
  block:
    let verdictPath = workdir / "v6.json"
    let skewed = workdir / "skewed.json"
    writeJson(skewed, stateDoc(fullUnits, satisfied = 3, unsatisfied = 0))
    let res = runRatchet([
      "--compare", "--baseline", baselinePath, "--state", skewed,
      "--scope-lock", scopePath, "--subject-sha", "ccc", "--out", verdictPath,
    ])
    let verdict = parseFile(verdictPath)
    check(res.code == 1 and verdict["reasons"].contains(%"counts-changed"),
          "fixture-6 count/row disagreement MISMATCHes",
          $verdict["reasons"])

  # 7 — a changed scope lock is a scope change, not a pass.
  block:
    let verdictPath = workdir / "v7.json"
    let widerScope = workdir / "scope_wide.json"
    writeJson(widerScope, scopeLock([
      "src/a.nim::alpha",
      "src/b.nim::beta",
      "src/c.nim::gamma",
      "src/d.nim::delta",
    ]))
    let res = runRatchet([
      "--compare", "--baseline", baselinePath, "--state", fullState,
      "--scope-lock", widerScope, "--subject-sha", "ccc", "--out", verdictPath,
    ])
    let verdict = parseFile(verdictPath)
    check(res.code == 1 and verdict["reasons"].contains(%"scope-changed"),
          "fixture-7 scope-lock change MISMATCHes", $verdict["reasons"])

  # 8 — no baseline: UNKNOWN, never a pass. A ratchet without a reference
  # cannot assert anything.
  block:
    let verdictPath = workdir / "v8.json"
    let res = runRatchet([
      "--compare", "--baseline", workdir / "absent.json", "--state", fullState,
      "--scope-lock", scopePath, "--subject-sha", "ccc", "--out", verdictPath,
    ])
    let verdict = parseFile(verdictPath)
    check(res.code == 3 and verdict["verdict"].getStr() == "UNKNOWN",
          "fixture-8 missing baseline is UNKNOWN (exit 3)",
          res.output & " " & $verdict["verdict"])
    check(verdict["reasons"].contains(%"baseline-missing"),
          "fixture-8 reason baseline-missing", $verdict["reasons"])

  # 9 — an unsupported baseline contract is UNKNOWN, not a coerced comparison.
  block:
    let verdictPath = workdir / "v9.json"
    let alienPath = workdir / "alien.json"
    var alien = parseFile(baselinePath)
    alien["contract"] = %"axiom.proof-ratchet-baseline.v0"
    writeJson(alienPath, alien)
    let res = runRatchet([
      "--compare", "--baseline", alienPath, "--state", fullState,
      "--scope-lock", scopePath, "--subject-sha", "ccc", "--out", verdictPath,
    ])
    let verdict = parseFile(verdictPath)
    check(res.code == 3 and
          verdict["reasons"].contains(%"baseline-contract-unsupported"),
          "fixture-9 unknown baseline contract is UNKNOWN (exit 3)",
          $verdict["reasons"])

  removeDir(workdir)
  if failures > 0:
    echo "proof_ratchet tests FAILED (", failures, ")"
    return 1
  echo "proof_ratchet tests passed (9 fixtures)"
  0

when isMainModule:
  quit(main())