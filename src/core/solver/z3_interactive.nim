import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/types/z3_solver_config
import infrastructure/logging_facade
import std/[os, osproc, streams, strutils, times]
const
  AxiomSyncMarker* = "AXIOM_SYNC_b7f3a2c1"
  AxiomSyncCmd* = "(echo \"" & AxiomSyncMarker & "\")"
  AxiomSyncTimeoutMs* = 30_000  ## 30s per sync round
type
  Z3Stream* = object
    ## Persistent Z3 interactive session.
    process*: Process
    stdin*: Stream
    stdout*: Stream
    alive*: bool

  Z3RoundResult* = object
    ## Result of one sync-delimited round.
    lines*: seq[string]       ## Lines between previous sync and current sync
    rawOutput*: string        ## Concatenated output
    syncReceived*: bool       ## Whether sync marker was found
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc startZ3Stream*(z3Path: string = resolveZ3Path();
    args: seq[string] = @["-smt2", "-in"]): Z3Stream {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Start a persistent Z3 process in interactive mode.
  try:
    let p = startProcess(z3Path, args = args,
      options = {poStdErrToStdOut, poDaemon})
    result = Z3Stream(
      process: p,
      stdin: p.inputStream(),
      stdout: p.outputStream(),
      alive: true
    )
  except CatchableError:
    result = Z3Stream(alive: false)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc sendCommand*(z3: var Z3Stream; cmd: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Send a command to Z3 without reading response.
  if not z3.alive: return
  z3.stdin.writeLine(cmd)
  z3.stdin.flush()
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc sendSyncMarker*(z3: var Z3Stream) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Send sync marker to flush Z3 output.
  z3.sendCommand(AxiomSyncCmd)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readUntilSync*(z3: var Z3Stream;
    timeoutMs: int = AxiomSyncTimeoutMs): Z3RoundResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Read all output lines until the sync marker appears.
  ## Returns lines collected before the marker.
  if not z3.alive:
    return Z3RoundResult(lines: @[], rawOutput: "", syncReceived: false)

  var collected: seq[string] = @[]
  var raw = ""
  let deadline = epochTime() + (timeoutMs.float / 1000.0)

  while epochTime() < deadline:
    var line = ""
    try:
      if not z3.stdout.atEnd():
        line = z3.stdout.readLine()
      else:
        # No data available, yield briefly
        sleep(1)
        continue
    except IOError:
      z3.alive = false
      return Z3RoundResult(lines: collected, rawOutput: raw, syncReceived: false)

    if AxiomSyncMarker in line:
      return Z3RoundResult(
        lines: collected,
        rawOutput: raw,
        syncReceived: true
      )

    collected.add(line)
    if raw.len > 0: raw.add("\n")
    raw.add(line)

  # Timeout — return what we have
  return Z3RoundResult(lines: collected, rawOutput: raw, syncReceived: false)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc executeRound*(z3: var Z3Stream; commands: string): Z3RoundResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Send commands + sync marker, then read until sync marker.
  ## This is the primary interaction pattern — one round = one atomic batch.
  z3.sendCommand(commands)
  z3.sendSyncMarker()
  result = z3.readUntilSync()
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc closeZ3Stream*(z3: var Z3Stream) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Gracefully close the Z3 session.
  if z3.alive:
    try:
      z3.stdin.writeLine("(exit)")
      z3.stdin.flush()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    z3.process.close()
    z3.alive = false
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc checkSat*(z3: var Z3Stream): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Send (check-sat) and return the result string ("sat", "unsat", "unknown").
  let round = z3.executeRound("(check-sat)")
  if round.syncReceived and round.lines.len > 0:
    return round.lines[0].strip()
  return "unknown"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc push*(z3: var Z3Stream; n: int = 1) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Push n scopes onto the Z3 assertion stack.
  let r = z3.executeRound("(push " & $n & ")")
  if not r.syncReceived and r.lines.len > 0:
    logError("z3_interactive", "push " & $n & " failed: " & r.lines[0])
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc pop*(z3: var Z3Stream; n: int = 1) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Pop n scopes from the Z3 assertion stack.
  let r = z3.executeRound("(pop " & $n & ")")
  if not r.syncReceived and r.lines.len > 0:
    logError("z3_interactive", "pop " & $n & " failed: " & r.lines[0])
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc assertFormula*(z3: var Z3Stream; smt2: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Assert a formula (raw S-expression).
  let r = z3.executeRound("(assert " & smt2 & ")")
  if not r.syncReceived and r.lines.len > 0:
    logError("z3_interactive", "assertFormula failed: " & r.lines[0])
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getModel*(z3: var Z3Stream): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Get model after sat result.
  let round = z3.executeRound("(get-model)")
  if round.syncReceived:
    return round.rawOutput
  return ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc applyTactic*(z3: var Z3Stream; smt2Formula: string;
    tactic: string = "(then simplify propagate-values ctx-solver-simplify)"): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Apply a Z3 tactic to a formula for canonical normalization.
  ## Returns the tactic output (goals s-expression).
  ##
  ## User refinement (Plan v5): "Z3 Canonical Tactic 위임 — 수동 AST 정규화 대신
  ## Z3 자체 tactic 엔진에 canonical form 위임"
  let cmd = "(apply " & tactic & ")"
  let round = z3.executeRound(cmd)
  if round.syncReceived:
    return round.rawOutput
  return ""

{.pop.}
