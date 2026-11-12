import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/bmc/bmc_types
import core/proof/proof_budget
import core/results
import core/trusted/solver_invocation
import std/[strutils, times]
# axiomIoBoundary
export bmc_types.BmcTransition  # Domain-layer type; re-exported for Infrastructure backward compat

type
  SpacerChcResult* = object
    success*: bool
    invariantSource*: string  ## SMT-LIB2 style invariant expression
    leanHint*: string         ## Tier 1 deterministic Lean 4 hint
    solverTimeMs*: int
    status*: string           ## "sat", "unsat", "unknown", "timeout", etc.

# ─── Pure helpers (unchanged) ───────────────────────────────────────────────

func encodeInitialState(state: seq[tuple[name: string, sort: string]]): string =
  if state.len == 0:
    return "(assert (state))\n"
  var varDecls = ""
  var conj = ""
  for i, s in state:
    if i > 0:
      varDecls.add(" ")
      conj.add(" ")
    varDecls.add("(" & s.name & " " & s.sort & ")")
    conj.add("(= " & s.name & " 0)")
  if state.len > 1:
    conj = "(and " & conj & ")"
  result = "(assert (forall ("
  result.add(varDecls)
  result.add(") (=> ")
  result.add(conj)
  result.add(" (state")
  for s in state:
    result.add(" ")
    result.add(s.name)
  result.add("""))))""" & "\n")
func encodeTransitionRule(t: BmcTransition): string =
  if t.preState.len == 0 and t.postState.len == 0:
    return "(assert (=> " & t.guard & " (state)))\n"
  var allVars = ""
  for s in t.preState:
    allVars.add(" (" & s.name & " " & s.sort & ")")
  for s in t.postState:
    allVars.add(" (" & s.name & "_next Int)")
  var body = "(and (state"
  for s in t.preState:
    body.add(" ")
    body.add(s.name)
  body.add(") ")
  body.add(t.guard)
  var nextConj = ""
  for i, s in t.postState:
    if i > 0:
      nextConj.add(" ")
    nextConj.add("(= " & s.name & "_next " & s.expr & ")")
  if t.postState.len > 1:
    nextConj = "(and " & nextConj & ")"
  if t.postState.len > 0:
    body.add(" ")
    body.add(nextConj)
  body.add(")")
  var head = "(state"
  for s in t.postState:
    head.add(" ")
    head.add(s.name)
    head.add("_next")
  head.add(")")
  if allVars.len == 0:
    result = "(assert (=> "
    result.add(body)
    result.add(" ")
    result.add(head)
    result.add("))\n")
  else:
    result = "(assert (forall ("
    result.add(allVars.strip(leading = true))
    result.add(") (=> ")
    result.add(body)
    result.add(" ")
    result.add(head)
    result.add(")))\n")
func encodeQuery(violationCondition: string): string =
  "(assert (=> (and state " & violationCondition & ") false))\n"
func sexpToLean(sexp: string; start: int): tuple[expr: string, next: int] =
  var i = start
  while i < sexp.len and sexp[i] == ' ':
    i.inc
  if i >= sexp.len:
    return ("", i)
  if sexp[i] != '(':
    var atom = ""
    while i < sexp.len and sexp[i] != ' ' and sexp[i] != ')':
      atom.add(sexp[i])
      i.inc
    return (atom, i)
  i.inc
  var op = ""
  while i < sexp.len and sexp[i] != ' ' and sexp[i] != ')':
    op.add(sexp[i])
    i.inc
  var args: seq[string] = @[]
  while i < sexp.len and sexp[i] != ')':
    while i < sexp.len and sexp[i] == ' ':
      i.inc
    if i < sexp.len and sexp[i] == ')':
      break
    let (arg, next) = sexpToLean(sexp, i)
    args.add(arg)
    i = next
  i.inc
  case op
  of "and":
    var res = ""
    for j, a in args:
      if j > 0:
        res.add(" ∧ ")
      res.add(a)
    (res, i)
  of "or":
    var res = ""
    for j, a in args:
      if j > 0:
        res.add(" ∨ ")
      res.add(a)
    (res, i)
  of ">=":
    (args[0] & " ≥ " & args[1], i)
  of "<=":
    (args[0] & " ≤ " & args[1], i)
  of "=":
    (args[0] & " = " & args[1], i)
  of "not":
    ("¬(" & args[0] & ")", i)
  of ">":
    (args[0] & " > " & args[1], i)
  of "<":
    (args[0] & " < " & args[1], i)
  of "+":
    var res = ""
    for j, a in args:
      if j > 0:
        res.add(" + ")
      res.add(a)
    (res, i)
  else:
    var res = "(" & op
    for a in args:
      res.add(" ")
      res.add(a)
    res.add(")")
    (res, i)
func smtToLeanHint*(smtExpr: string): string =
  let (leanExpr, _) = sexpToLean(smtExpr.strip(), 0)
  "have hint : " & leanExpr & " := by omega"

# ─── Shared: Build complete SMT-LIB2 script ────────────────────────────────
# Extracted from trySpacerInvariantSynthesis to avoid duplication between
# legacy one-shot path and pool-backed path.

func buildSpacerScript*(
  transitions: seq[BmcTransition];
  initialState: seq[tuple[name: string, sort: string]];
  violationCondition: string;
  withGetModel: bool = false;
): string =
  ## Build the complete SMT-LIB2 CHC script for Spacer invariant synthesis.
  ## When withGetModel is true, appends (get-model) after (check-sat)
  ## so the pool path can retrieve the invariant in a single query
  ## (the pool adds (reset) per query, preventing multi-step sessions).
  var script = "(set-logic HORN)\n" & solverOptionsPayload(pinnedDeterminismOptions())
  if initialState.len > 0:
    script.add("(declare-fun state (")
    for i, s in initialState:
      if i > 0:
        script.add(" ")
      script.add(s.sort)
    script.add(") Bool)\n")
  else:
    script.add("(declare-fun state () Bool)\n")

  script.add(encodeInitialState(initialState))
  for t in transitions:
    script.add(encodeTransitionRule(t))

  var queryVars = ""
  var queryStateArgs = ""
  for s in initialState:
    queryVars.add(" (" & s.name & " " & s.sort & ")")
    queryStateArgs.add(" " & s.name)
  if queryVars.len > 0:
    script.add("(assert (forall (" & queryVars.strip(leading = true) & ") (=> (and (state" & queryStateArgs & ") " & violationCondition & ") false)))\n")
  else:
    script.add(encodeQuery(violationCondition))

  script.add("(check-sat)\n")
  if withGetModel:
    script.add("(get-model)\n")
  script

# ─── Shared: Parse combined Z3 output (status + optional model) ─────────────

func parseSpacerOutput(rawOutput: string): tuple[status: string, modelBody: string] =
  ## Parse combined Z3 output from a (check-sat) + (get-model) query.
  ## Returns the solver status and the model body (if sat).
  ## Handles stderr noise by searching for the first sat/unsat/unknown line.
  let stripped = rawOutput.strip()
  if stripped.len == 0:
    return ("unknown", "")

  let lines = stripped.splitLines()

  # Search for the check-sat result line (may not be first if stderr mixed in)
  var statusIdx = -1
  for i, line in lines:
    let l = line.strip().toLowerAscii()
    if l == "sat" or l == "unsat" or l == "unknown":
      statusIdx = i
      break

  if statusIdx < 0:
    return ("unknown", "")

  let status = lines[statusIdx].strip().toLowerAscii()
  if status != "sat":
    return (status, "")

  # Extract model from remaining lines after the status line
  var remainder = ""
  if statusIdx + 1 < lines.len:
    remainder = lines[(statusIdx + 1) .. ^1].join("\n").strip()

  var modelBody = ""
  # Parse (define-fun state ((x!0 Int)) Bool <body>)
  let defineFunIdx = remainder.find("define-fun state")
  if defineFunIdx >= 0:
    var i = defineFunIdx
    # Skip to Bool
    let boolIdx = remainder.find("Bool", i)
    if boolIdx > 0:
      i = boolIdx + 4
      # Extract body: last paren-balanced expression before final ))
      var bodyStart = -1
      var depth = 0
      while i < remainder.len:
        if remainder[i] == '(':
          if bodyStart < 0: bodyStart = i
          depth.inc
        elif remainder[i] == ')':
          depth.dec
          if depth == 0 and bodyStart >= 0:
            modelBody = remainder[bodyStart .. i]
            break
        i.inc
  (status, modelBody)

# ═══════════════════════════════════════════════════════════════════════════
# ─── Legacy one-shot path (-d:legacySpacer) ─────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════
# Preserves the original startSpacerWorker/sendSmtlibCommand implementation.
# Each invocation spawns a new Z3 process — no process reuse.

when defined(legacySpacer):
  import std/[osproc, streams]

  proc safeCloseProcess(process: Process): Result[bool, string] {.axiomEffect: IOEffect.} =
    try:
      kill(process)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    try:
      discard waitForExit(process, 2000)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    try:
      close(process)
      ok(true)
    except CatchableError:
      ok(true)
  proc startSpacerWorker(): Result[Process, string] {.axiomEffect: IOEffect.} =
    try:
      let p = startProcess(
        command = "z3",
        args = @["-smt2", "-in"],
        options = {poUsePath, poStdErrToStdOut}
      )
      if p.isNil:
        return err("startProcess returned nil")
      ok(p)
    except CatchableError as e:
      err("startSpacerWorker: " & e.msg)
  proc sendSmtlibCommand(p: Process; cmd: string; timeoutMs: int = z3SafetyNetMs): Result[string, string] {.axiomEffect: IOEffect.} =
    try:
      let input = inputStream(p)
      let output = outputStream(p)
      if input.isNil or output.isNil:
        return err("streams unavailable")
      input.write(cmd & "\n")
      input.flush()
      var buf = ""
      var parenDepth = 0
      var seenParen = false
      const maxExpectedTokens = 65536  ## Structural upper bound on response size
      var tokenCount = 0
      let deadline = epochTime() * 1000.0 + float(timeoutMs)
      while tokenCount < maxExpectedTokens:
        if epochTime() * 1000.0 > deadline:
          return err("sendSmtlibCommand: timeout after " & $timeoutMs & "ms")
        var c = '\0'
        try:
          c = output.readChar()
        except CatchableError:
          break
        if c == '\0':
          break
        inc tokenCount
        if c == '(': parenDepth.inc; seenParen = true
        elif c == ')': parenDepth.dec
        buf.add(c)
        # Stop when paren balanced after opening, or on newline if no parens
        if seenParen and parenDepth == 0:
          break
        if not seenParen and c == '\n':
          break
      if tokenCount >= maxExpectedTokens:
        return err("sendSmtlibCommand: structural token limit exceeded (" & $maxExpectedTokens & ")")
      ok(buf.strip())
    except CatchableError as e:
      err("sendSmtlibCommand: " & e.msg)

  proc trySpacerInvariantSynthesis*(
    transitions: seq[BmcTransition];
    initialState: seq[tuple[name: string, sort: string]];
    violationCondition: string;
    timeoutMs: int = z3SafetyNetMs
  ): SpacerChcResult =
    let t0 = epochTime() * 1000.0

    let workerRes = startSpacerWorker()
    if workerRes.isErr:
      return SpacerChcResult(
        success: false,
        status: "worker_failed",
        invariantSource: "",
        leanHint: "",
        solverTimeMs: 0
      )
    let p = workerRes.get

    let script = buildSpacerScript(transitions, initialState, violationCondition, withGetModel = false)

    let checkRes = sendSmtlibCommand(p, script)
    if checkRes.isErr:
      discard safeCloseProcess(p)
      return SpacerChcResult(
        success: false,
        status: "io_error",
        invariantSource: "",
        leanHint: "",
        solverTimeMs: int(epochTime() * 1000.0 - t0)
      )

    let checkOutput = checkRes.get.strip()
    let elapsed = int(epochTime() * 1000.0 - t0)

    if checkOutput == "sat":
      let modelRes = sendSmtlibCommand(p, "(get-model)")
      var invariant = ""
      if modelRes.isOk:
        let modelStr = modelRes.get()
        # Parse (define-fun state ((x!0 Int)) Bool <body>)
        let defineFunIdx = modelStr.find("define-fun state")
        if defineFunIdx >= 0:
          var i = defineFunIdx
          # Skip to Bool
          let boolIdx = modelStr.find("Bool", i)
          if boolIdx > 0:
            i = boolIdx + 4
            # Extract body: last paren-balanced expression before final ))
            var bodyStart = -1
            var depth = 0
            while i < modelStr.len:
              if modelStr[i] == '(':
                if bodyStart < 0: bodyStart = i
                depth.inc
              elif modelStr[i] == ')':
                depth.dec
                if depth == 0 and bodyStart >= 0:
                  invariant = modelStr[bodyStart .. i]
                  break
              i.inc
      discard safeCloseProcess(p)
      return SpacerChcResult(
        success: true,
        status: "sat",
        invariantSource: invariant,
        leanHint: smtToLeanHint(invariant),
        solverTimeMs: elapsed
      )
    elif checkOutput == "unsat":
      discard safeCloseProcess(p)
      return SpacerChcResult(
        success: false,
        status: "unsat",
        invariantSource: "",
        leanHint: "",
        solverTimeMs: elapsed
      )
    else:
      discard safeCloseProcess(p)
      return SpacerChcResult(
        success: false,
        status: checkOutput,
        invariantSource: "",
        leanHint: "",
        solverTimeMs: elapsed
      )

  proc trySpacerInvariantSynthesisWithBudget*(
    transitions: seq[BmcTransition];
    initialState: seq[tuple[name: string, sort: string]];
    violationCondition: string;
    budget: var ProofBudget;
    timeoutMs: int = 30000
  ): SpacerChcResult =
    ## Legacy path with proof budget integration.
    ## Short-circuits if gas already exhausted; decrements on success.
    if budget.gasRemaining <= 0:
      return SpacerChcResult(
        success: false,
        status: "gas_exhausted",
        invariantSource: "",
        leanHint: "",
        solverTimeMs: 0
      )
    let spacerRes = trySpacerInvariantSynthesis(
      transitions, initialState, violationCondition, timeoutMs
    )
    if spacerRes.success:
      discard consumeGas(budget)
    spacerRes

# ═══════════════════════════════════════════════════════════════════════════
# ─── Pool-backed path (default) ────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════
# Uses the persistent Z3 subprocess pool from z3_pool.nim.
# Process lifecycle is managed by the pool — no manual kill/close.
# Each query is wrapped in (reset) + timeout + rlimit by buildZ3QueryEnvelope.
# Large-payload file-based fallback is handled by the pool transparently.

else:
  import verification/solver/z3_pool

  proc trySpacerInvariantSynthesis*(
    transitions: seq[BmcTransition];
    initialState: seq[tuple[name: string, sort: string]];
    violationCondition: string;
    timeoutMs: int = 30000
  ): SpacerChcResult =
    ## Pool-backed Spacer CHC invariant synthesis.
    ## Sends a single combined (check-sat) + (get-model) query through
    ## z3ExecPersistent, which handles worker selection, sentinel framing,
    ## timeout, and large-payload fallback.
    let t0 = epochTime() * 1000.0

    # Build combined script: check-sat + get-model in one query
    # (pool adds (reset) per query, so multi-step sessions are impossible)
    let script = buildSpacerScript(
      transitions, initialState, violationCondition, withGetModel = true
    )

    var cd, td: string
    let queryRes = z3ExecPersistent(
      script, timeoutMs, desiredWorkers = 1,
      enableProofs = false, queryType = "spacer_chc",
      canonicalEnvelopeDigest = cd, transportPayloadDigest = td
    )

    let elapsed = int(epochTime() * 1000.0 - t0)

    if queryRes.isErr:
      return SpacerChcResult(
        success: false,
        status: "io_error",
        invariantSource: "",
        leanHint: "",
        solverTimeMs: elapsed
      )

    let (status, modelBody) = parseSpacerOutput(queryRes.get())

    case status
    of "sat":
      SpacerChcResult(
        success: true,
        status: "sat",
        invariantSource: modelBody,
        leanHint: smtToLeanHint(modelBody),
        solverTimeMs: elapsed
      )
    of "unsat":
      SpacerChcResult(
        success: false,
        status: "unsat",
        invariantSource: "",
        leanHint: "",
        solverTimeMs: elapsed
      )
    else:
      SpacerChcResult(
        success: false,
        status: status,
        invariantSource: "",
        leanHint: "",
        solverTimeMs: elapsed
      )

  proc trySpacerInvariantSynthesisWithBudget*(
    transitions: seq[BmcTransition];
    initialState: seq[tuple[name: string, sort: string]];
    violationCondition: string;
    budget: var ProofBudget;
    timeoutMs: int = 30000
  ): SpacerChcResult =
    ## Pool-backed Spacer with proof budget integration.
    ## Short-circuits if gas already exhausted; decrements on success.
    if budget.gasRemaining <= 0:
      return SpacerChcResult(
        success: false,
        status: "gas_exhausted",
        invariantSource: "",
        leanHint: "",
        solverTimeMs: 0
      )
    let spacerRes = trySpacerInvariantSynthesis(
      transitions, initialState, violationCondition, timeoutMs
    )
    if spacerRes.success:
      discard consumeGas(budget)
    spacerRes

{.pop.}

