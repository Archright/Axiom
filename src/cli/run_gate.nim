import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

## Axiom Run Gate — Single Control Plane Entry Point
##
## Replaces the Shell/Python `bin/run-gate` implementation.
## Reads gate parameters as JSON from stdin and dispatches to native Nim gate
## runners via startProcess (no shell interpolation).

import std/[os, json]
import core/axiom_pragmas
import gate/lib/runner_common
import infrastructure/logging_facade

axiomIoBoundary()

const
  MaxOutputBytes = 2 * 1024 * 1024

proc readStdinJson(): JsonNode {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read JSON object from stdin. Supports both piped input and empty stdin.
  var input = ""
  var line: string
  while stdin.readLine(line):
    input.add(line)
    input.add("\n")
  if input.len == 0:
    return newJObject()
  result = parseJson(input)

func extractFiles(node: JsonNode): seq[string] {.raises: [].} =
  ## Extract the "files" array from the JSON payload.
  if node.kind != JObject:
    return @[]
  let filesNode = node{"files"}
  if filesNode == nil or filesNode.kind != JArray:
    return @[]
  for f in filesNode.getElems():
    if f.kind == JString:
      result.add(f.getStr())

proc runNimCheck(files: seq[string]): GateResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run `nim check` on the provided files.
  if files.len == 0:
    return pass("[nim check] No files provided; skipping.\n")
  runCommand("nim", @["check"] & files, maxOutputLen = MaxOutputBytes)

proc runNimtry(files: seq[string]): GateResult {.raises: [CatchableError].} =
  ## Run the nimtry gate on the provided files.
  if files.len == 0:
    return pass("[nimtry] No files provided; skipping.\n")

  # Prefer pre-built binary.
  if fileExists("bin/nimtry"):
    return runCommand("bin/nimtry", files, maxOutputLen = MaxOutputBytes)

  return fail("[nimtry] ERROR: bin/nimtry not found — architecture check REQUIRED.\n")

proc main*() {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let payload = readStdinJson()
  let files = extractFiles(payload)

  if files.len == 0:
    logInfo("run_gate", "Usage: parameters must include 'files' array")
    quit(1)

  logInfo("run_gate", "=== nim check ===")
  let nimCheckRes = runNimCheck(files)
  if nimCheckRes.stdout.len > 0:
    logInfo("run_gate", nimCheckRes.stdout)
  if nimCheckRes.stderr.len > 0:
    logInfo("run_gate", nimCheckRes.stderr)

  logInfo("run_gate", "")
  logInfo("run_gate", "=== nimtry ===")
  let nimtryRes = runNimtry(files)
  if nimtryRes.stdout.len > 0:
    logInfo("run_gate", nimtryRes.stdout)
  if nimtryRes.stderr.len > 0:
    logInfo("run_gate", nimtryRes.stderr)

  logInfo("run_gate", "")
  logInfo("run_gate", "=== Gate completed ===")

  if not nimCheckRes.ok or not nimtryRes.ok:
    quit(1)

when isMainModule:
  main()

{.pop.}
