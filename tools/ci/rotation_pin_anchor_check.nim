import core/trusted/layer_declaration
axiomLayer "tools"

## rotation_pin_anchor_check.nim — rotation preflight: judge the PR-head
## pin-anchor condition (ADR-0025 §7/§13 ④ new anchor, Pass 2.75 / H2) with
## the SAME compiled implementation as the landing predicate.
##
## The judgment itself lives in the shared leaf module
## core/policy/rotation_closure_facts (newAnchorVerdict + the parsing
## primitives) — the exact funcs `src/cli/merge_cli.nim` consumes, so the
## preflight verdict and the landing verdict cannot drift. This tool owns
## only the CLI surface + file I/O (seconds-class build: no cli/merge_cli
## import — see derive_checker_closure.nim for the same venue split).
##
## Usage:
##   rotation_pin_anchor_check --derived-H <file> --pin-H <file> [--pin-B <path>]
##
##     --derived-H <file>  deriver-format closure linetext of H (required)
##     --pin-H <file>      trusted_writer_set.json @ H (required)
##     --pin-B <path>      trusted_writer_set.json @ B
##                         (default: config/trusted_writer_set.json in cwd)
##
## stdout: exactly one line —
##   H2 PASS code=OK
##   H2 FAIL code=<ROT_NEW_PIN|ROT_GENESIS_INVALID> reason=<shared reason>
##     | missing-from-pin=<paths> | pin-only=<paths>
## (the reason is the VERBATIM string the landing predicate consumes; the
## differing paths are sorted, ","-joined, "-" when empty).
## stderr: input contract diagnostics.
## exit: 0 = H2 holds; 1 = H2 fails; 2 = input contract violation
## (missing/unreadable file, malformed JSON(C), malformed derived line,
## malformed pin entry — fail-closed, never a verdict).

import std/[algorithm, json, options, os, parseopt, sets, strutils]
import core/results
import core/policy/rotation_closure_facts

const
  ToolName* = "rotation_pin_anchor_check"
  ExitPass* = 0            ## H2 holds
  ExitH2Fail* = 1          ## H2 fails (ROT_NEW_PIN / ROT_GENESIS_INVALID)
  ExitInputViolation* = 2  ## input contract violation — fail-closed

type
  CheckOutcome* = object
    exitCode*: int
    ## stdout verdict line (exit 0/1) or stderr diagnostic (exit 2).
    line*: string

# ---------------------------------------------------------------------------
# Parsing (pure text → facts; all via the shared leaf module)
# ---------------------------------------------------------------------------

proc parseJsoncNode(text: string): Result[JsonNode, string] {.raises: [].} =
  ## trusted_writer_set documents carry JSONC comments — strip, then parse.
  try:
    ok(parseJson(stripJsoncComments(text)))
  except CatchableError as e:
    err("malformed JSON(C): " & e.msg)

proc parsePinDocument(text: string): Result[Option[HashSet[string]], string] {.raises: [].} =
  let parsed = parseJsoncNode(text)
  if parsed.isErr:
    return err(parsed.err)
  pinClosureLineSet(parsed.get)

proc differingPaths(derivedH: HashSet[string]; pinH: Option[HashSet[string]]):
    tuple[missingFromPin, pinOnly: string] {.raises: [].} =
  ## FAIL diagnostics: paths in derived(H) that pin@H does not carry, and
  ## pin@H paths absent from derived(H) — sorted (byte order), ","-joined,
  ## "-" when empty. pin@H key absent → every derived path is missing.
  let ph: HashSet[string] = if pinH.isSome: pinH.get else: initHashSet[string]()
  var missing, only: seq[string]
  for ln in derivedH:
    if ln notin ph:
      missing.add(closurePathFromLine(ln))
  for ln in ph:
    if ln notin derivedH:
      only.add(closurePathFromLine(ln))
  missing.sort()
  only.sort()
  result.missingFromPin = if missing.len == 0: "-" else: missing.join(",")
  result.pinOnly = if only.len == 0: "-" else: only.join(",")

proc evaluatePinAnchorTexts*(derivedHText, pinHText, pinBText: string): CheckOutcome {.
    raises: [].} =
  ## Text-level core: the three file CONTENTS → verdict line + exit code.
  ## Input contract violations fail closed (exit 2) BEFORE any judgment —
  ## a malformed input is a run-level failure, never an H2 verdict.
  let derived = parseDerivedSet(derivedHText)
  if derived.isErr:
    return CheckOutcome(exitCode: ExitInputViolation,
                        line: "input contract violation: derived-H: " & derived.err)
  let pinH = parsePinDocument(pinHText)
  if pinH.isErr:
    return CheckOutcome(exitCode: ExitInputViolation,
                        line: "input contract violation: pin-H: " & pinH.err)
  let pinB = parsePinDocument(pinBText)
  if pinB.isErr:
    return CheckOutcome(exitCode: ExitInputViolation,
                        line: "input contract violation: pin-B: " & pinB.err)
  let v = newAnchorVerdict(derived.get, pinH.get, pinB.get)
  if v.ok:
    return CheckOutcome(exitCode: ExitPass, line: "H2 PASS code=OK")
  let (missingFromPin, pinOnly) = differingPaths(derived.get, pinH.get)
  CheckOutcome(exitCode: ExitH2Fail,
               line: "H2 FAIL code=" & v.code & " reason=" & v.reason &
                 " | missing-from-pin=" & missingFromPin &
                 " | pin-only=" & pinOnly)

proc readCheckFile(path: string): Result[string, string] {.raises: [].} =
  try:
    ok(readFile(path))
  except CatchableError as e:
    err("cannot read '" & path & "' (fail-closed): " & e.msg)

proc evaluatePinAnchorFiles*(derivedHPath, pinHPath, pinBPath: string): CheckOutcome {.
    raises: [].} =
  ## File-level core: read the three inputs, then judge. A missing or
  ## unreadable input is an input contract violation (exit 2) — in the
  ## preflight venue the gate supplies these files; absence is never read
  ## as a clean or failing verdict.
  let d = readCheckFile(derivedHPath)
  if d.isErr:
    return CheckOutcome(exitCode: ExitInputViolation,
                        line: "input contract violation: " & d.err)
  let h = readCheckFile(pinHPath)
  if h.isErr:
    return CheckOutcome(exitCode: ExitInputViolation,
                        line: "input contract violation: " & h.err)
  let b = readCheckFile(pinBPath)
  if b.isErr:
    return CheckOutcome(exitCode: ExitInputViolation,
                        line: "input contract violation: " & b.err)
  evaluatePinAnchorTexts(d.get, h.get, b.get)

# ---------------------------------------------------------------------------
# CLI surface
# ---------------------------------------------------------------------------

proc parseCheckArgs*(args: seq[string]):
    Result[tuple[derivedHPath, pinHPath, pinBPath: string], string] {.raises: [].} =
  ## `--derived-H <file>` (required), `--pin-H <file>` (required),
  ## `--pin-B <path>` (optional — default RotationPinBPath in the cwd).
  ## Anything else is an input contract violation.
  var
    derivedH, pinH, pinB: string
    seenDerived, seenPinH = false
  var p = initOptParser(args)
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      let key = p.key
      var val = p.val
      if val.len == 0:
        p.next()
        if p.kind != cmdArgument:
          return err("option '--" & key & "' requires a value")
        val = p.key
      case key
      of "derived-H":
        derivedH = val
        seenDerived = true
      of "pin-H":
        pinH = val
        seenPinH = true
      of "pin-B":
        pinB = val
      else:
        return err("unknown option '--" & key & "'")
    of cmdArgument:
      return err("unexpected argument '" & p.key & "'")
  if not seenDerived:
    return err("missing required --derived-H <file>")
  if not seenPinH:
    return err("missing required --pin-H <file>")
  if pinB.len == 0:
    pinB = RotationPinBPath
  ok((derivedH, pinH, pinB))

proc runCheck*(args: seq[string]): int {.raises: [].} =
  ## CLI entry: arg parse → files → verdict. stdout carries exactly one H2
  ## verdict line for exit 0/1; input contract violations diagnose on stderr
  ## and exit 2.
  let parsed = parseCheckArgs(args)
  if parsed.isErr:
    try:
      stderr.writeLine(ToolName & ": " & parsed.err)
    except CatchableError: # bestEffort("""diagnostic stream unavailable — the exit code is the contract, the message is advisory""")
      discard
    return ExitInputViolation
  let outcome = evaluatePinAnchorFiles(parsed.get.derivedHPath,
                                       parsed.get.pinHPath,
                                       parsed.get.pinBPath)
  try:
    if outcome.exitCode == ExitInputViolation:
      stderr.writeLine(ToolName & ": " & outcome.line)
    else:
      stdout.writeLine(outcome.line)
  except CatchableError: # bestEffort("""output stream unavailable — the exit code is the contract, the line is advisory""")
    discard
  outcome.exitCode

when isMainModule:
  quit(runCheck(commandLineParams()))
