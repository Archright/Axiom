## Documentation-First Gate -- Self-Test
## Extracted from documentation_first_gate.nim for readability.

import core/trusted/layer_declaration
axiomLayer "gate"
import std/[os, json, strutils, times]
import core/axiom_pragmas
import documentation_first_gate

proc runSelfTest*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Validate config parsing and deterministic checks.
  stderrOut(GateTag & " --self-test")
  stderrOut("=".repeat(60))
  var passed = 0
  var failed = 0

  # Test 1: Config file exists and is parseable
  stderrOut("  [1] Load documentation_first.json ...")
  if not fileExists(CONFIG_PATH):
    stderrOut("    FAIL -- config not found: " & CONFIG_PATH)
    inc(failed)
  else:
    let content = readFile(CONFIG_PATH)
    let triggers = parseTriggerComponentsFromJson(content)
    if triggers.len > 0:
      stderrOut("    OK -- " & $triggers.len & " triggers loaded")
      inc(passed)
    else:
      stderrOut("    FAIL -- no triggers parsed")
      inc(failed)

  # Test 2: Trigger keyword matching works
  stderrOut("  [2] Trigger keyword matching ...")
  block:
    let testTriggers = @[
      TriggerConfig(keyword: "kernel", severity: "error",
                    description: "Linux kernel", docUrl: "https://kernel.org")
    ]
    let issues = scanFileForTriggers("/dev/null", testTriggers)
    # /dev/null should produce no issues
    if issues.len == 0:
      stderrOut("    OK -- clean file produces no issues")
      inc(passed)
    else:
      stderrOut("    FAIL -- false positive on /dev/null")
      inc(failed)

  # Test 3: hasDocsUrlInText works
  stderrOut("  [3] Official URL detection ...")
  block:
    let goodText = "See https://docs.kernel.org/admin-guide/kernel-parameters.html"
    let badText = "Just a random comment"
    if hasDocsUrlInText(goodText) and not hasDocsUrlInText(badText):
      stderrOut("    OK -- URL detection correct")
      inc(passed)
    else:
      stderrOut("    FAIL -- URL detection mismatch")
      inc(failed)

  # Test 4: Source file detection
  stderrOut("  [4] Source file detection ...")
  block:
    if isSourceFile("test.nim") and isSourceFile("config.py") and
       not isSourceFile("readme.md") and not isSourceFile("data.json"):
      stderrOut("    OK -- source file filter correct")
      inc(passed)
    else:
      stderrOut("    FAIL -- source file filter mismatch")
      inc(failed)

  # Test 5: Evidence check functions exist and don't crash
  stderrOut("  [5] Evidence check functions ...")
  block:
    let _ = hasEvidenceInDir()
    stderrOut("    OK -- evidence functions execute without crash")
    inc(passed)

  # Test 6: History write
  stderrOut("  [6] History write ...")
  block:
    let entry = %*{
      "timestamp": getTimestamp(),
      "gateId": GateId,
      "ruleId": "self-test",
      "severity": "info",
      "filePath": "",
      "line": 0,
      "message": "self-test entry",
      "bypassUsed": false
    }
    try:
      writeHistory(entry)
      stderrOut("    OK -- history write succeeded")
      inc(passed)
    except CatchableError as e:
      stderrOut("    FAIL -- " & e.msg)
      inc(failed)

  stderrOut("")
  stderrOut("Results: " & $passed & " passed, " & $failed & " failed")
  stderrOut("=".repeat(60))
  if failed > 0:
    quit(1)
  quit(0)

when isMainModule:
  runSelfTest()
