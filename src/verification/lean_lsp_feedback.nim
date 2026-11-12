import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/asyncdispatch
import std/asyncfutures
import std/json
import std/os
import std/sequtils
import std/strformat
import std/times
import core/lean_lsp_types
import verification/lean_lsp_protocol
import verification/lean_lsp_client
import core/logic/lean_diagnostic
import core/runtime_context
import core/proof/proof_budget
import ../core/trusted/axiom_pragmas
# axiomIoBoundary

# Forward declaration (defined later in this file)
proc collectFeedback*(client: LeanLspClient; line: int): Future[LeanFeedback] {.async, warning[BareExcept]: off, raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}

proc collectFeedbackWithHardTimeout*(client: LeanLspClient; line: int; timeoutMs: int = leanLspHardTimeoutMs): Future[LeanFeedback] {.async, warning[BareExcept]: off, raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let feedbackFuture = client.collectFeedback(line)
  let deadline = epochTime() + (timeoutMs.float / 1000.0)
  while epochTime() < deadline:
    if feedbackFuture.finished:
      return feedbackFuture.read()
    await sleepAsync(100)
  raise newException(IOError, "timeout_exceeded")

proc waitForResponse(client: LeanLspClient; fut: Future[JsonNode]; timeoutMs: int = leanLspHardTimeoutMs): Future[JsonNode] {.async, warning[BareExcept]: off, raises: [CatchableError, Exception], axiom: ["(assert (and (and (>= client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false)) (and (>= timeoutMs -9223372036854775808) (<= timeoutMs 9223372036854775807)) ast_parse_failed_isolated))", "client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ timeoutMs ≥ -9223372036854775808 ∧ timeoutMs ≤ 9223372036854775807 ∧ ast_parse_failed_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let deadline = epochTime() + (timeoutMs.float / 1000.0)
  while epochTime() < deadline:
    client.pollMessages()
    if fut.finished:
      return fut.read()
    await sleepAsync(50)
    
  # Abort logic: transmit LSP_TIMEOUT_ERROR
  raise newException(IOError, "LSP_TIMEOUT_ERROR: Split into simpler tactics")

proc initialize*(client: LeanLspClient; rootPath: string): Future[bool] {.async, warning[BareExcept]: off, raises: [CatchableError, Exception], axiom: ["(assert (and (and (>= client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false)) (>= (str.len rootPath) 0) true false (or (= client_isShutdown true) (= client_isShutdown false))))", "client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ rootPath.length ≥ 0 ∧ true ∧ false ∧ client_isShutdown = true ∨ client_isShutdown = false"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let initFut = client.sendRequest("initialize", %*{
    "processId": getCurrentProcessId(),
    "rootUri": toFileUri(rootPath),
    "capabilities": %*{}
  })
  
  try:
    discard await client.waitForResponse(initFut)
    client.sendNotification("initialized", %*{})
    return true
  except CatchableError:
    return false

proc openDocument*(client: LeanLspClient; filePath: string; source: string) {.raises: [CatchableError, Exception], axiom: ["(assert (and (and (>= client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false)) (>= (str.len filePath) 0) (>= (str.len source) 0)))", "client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ filePath.length ≥ 0 ∧ source.length ≥ 0"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  client.version = 1
  client.uri = toFileUri(filePath)
  client.sendNotification("textDocument/didOpen", %*{
    "textDocument": {
      "uri": client.uri,
      "languageId": "lean",
      "version": client.version,
      "text": source
    }
  })

proc collectFeedback*(client: LeanLspClient; line: int): Future[LeanFeedback] {.async, warning[BareExcept]: off, raises: [CatchableError].} =
  var feedback = LeanFeedback(diagnostics: @[], goals: @[], events: @[])
  let hoverFut = client.sendRequest("textDocument/hover", %*{
    "textDocument": { "uri": client.uri },
    "position": { "line": line, "character": 2 }
  })
  
  let deadline = epochTime() + 5.0
  while epochTime() < deadline:
    client.pollMessages()
    
    # Process notifications (diagnostics)
    var i = 0
    while i < client.notifications.len:
      let msg = client.notifications[i]
      if msg.hasKey("method") and msg["method"].getStr() == "textDocument/publishDiagnostics":
        let parsed = parseDiagnostics(msg)
        feedback.diagnostics = parsed
        for d in parsed:
          feedback.events.add(fmt"diag line={d.line} col={d.character} msg={d.message}")
        client.notifications.delete(i)
      else:
        i.inc()

    if hoverFut.finished:
      let resp = hoverFut.read()
      if resp.hasKey("result") and resp["result"].kind != JNull:
        feedback.goals.add(extractLeanGoalsFromJson(resp["result"]))
      break
    
    await sleepAsync(100)
      
  feedback.goals = feedback.goals.deduplicate()
  feedback

## Get Live Diagnostic Feedback.
proc getLiveDiagnosticFeedback*(
  client: LeanLspClient;
  line: int;
 window: int = 2;
  timeoutMs: int = leanLspHardTimeoutMs
): Future[LeanLiveDiagnosticFeedback] {.async, warning[BareExcept]: off, raises: [CatchableError, Exception], axiom: ["(assert (and (and (>= client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false)) (and (>= line -9223372036854775808) (<= line 9223372036854775807)) (and (>= window -9223372036854775808) (<= window 9223372036854775807)) (and (>= timeoutMs -9223372036854775808) (<= timeoutMs 9223372036854775807)) (or (= client_isShutdown true) (= client_isShutdown false))))", "client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ line ≥ -9223372036854775808 ∧ line ≤ 9223372036854775807 ∧ window ≥ -9223372036854775808 ∧ window ≤ 9223372036854775807 ∧ timeoutMs ≥ -9223372036854775808 ∧ timeoutMs ≤ 9223372036854775807 ∧ client_isShutdown = true ∨ client_isShutdown = false"].} =
  let feedback = await collectFeedbackWithHardTimeout(client, line, timeoutMs)
  return getLiveDiagnosticFeedback(feedback, line, window)

## Get Live Diagnostic Feedback.
proc getLiveDiagnosticFeedback*(
  filePath: string;
  source: string;
  line: int;
  leanExe: string = "";
  window: int = 2;
  timeoutMs: int = leanLspHardTimeoutMs
): LeanLiveDiagnosticFeedback {.raises: [AxiomLspError].} =
  {.cast(raises: [AxiomLspError]).}:
    var ctx = newVerificationRuntimeContext()
    var client: LeanLspClient = nil
    try:
      client = ctx.startLeanLsp(leanExe)
      let currentDir = getCurrentDir()
      if not safeWaitFor(client.initialize(currentDir)):
        return LeanLiveDiagnosticFeedback(
          line: line,
          hasErrors: true,
          hasWarnings: false,
          dominantKind: "lsp_unavailable",
          summary: "Lean LSP initialization failed, could not collect real-time diagnostics.",
          diagnostics: @[LeanDiagnostic(
            line: line,
            character: 0,
            severity: 1,
            message: "lean lsp initialize failed"
          )],
          goals: @[],
          actionableHints: @["Check Lean executable path and --server support."]
        )
      client.openDocument(filePath, source)
      return safeWaitFor(client.getLiveDiagnosticFeedback(line, window, timeoutMs))
    except AxiomLspError as e:
      return LeanLiveDiagnosticFeedback(
        line: line,
        hasErrors: true,
        hasWarnings: false,
        dominantKind: "lsp_unavailable",
        summary: "Lean LSP feedback collection failed. " & e.msg,
        diagnostics: @[LeanDiagnostic(
          line: line,
          character: 0,
          severity: 1,
          message: e.msg
        )],
        goals: @[],
        actionableHints: @["When real-time feedback is unavailable, simplify tactic based on compiler diagnostics."]
      )
    except CatchableError as e:
      return LeanLiveDiagnosticFeedback(
        line: line,
        hasErrors: true,
        hasWarnings: false,
        dominantKind: "lsp_unavailable",
        summary: "Lean LSP feedback collection failed. " & e.msg,
        diagnostics: @[LeanDiagnostic(
          line: line,
          character: 0,
          severity: 1,
          message: e.msg
        )],
        goals: @[],
        actionableHints: @["When real-time feedback is unavailable, simplify tactic based on compiler diagnostics."]
      )
    finally:
      if not client.isNil:
        client.shutdown(ctx)

## Run Dynamic Proof Search.
# @axiom-hint: lean="specPath.length ≥ 0 ∧ workPath.length ≥ 0 ∧ corePath.length ≥ 0 ∧ theoremName.length ≥ 0 ∧ leanExe.length ≥ 0 ∧ maxAttempts ≥ -9223372036854775808 ∧ maxAttempts ≤ 9223372036854775807 ∧ external_io_isolated" smt="(assert (and (>= (str.len specPath) 0) (>= (str.len workPath) 0) (>= (str.len corePath) 0) (>= (str.len theoremName) 0) (>= (str.len leanExe) 0) (and (>= maxAttempts -9223372036854775808) (<= maxAttempts 9223372036854775807)) external_io_isolated))"
# @axiom-hint: lean="specPath.length > 0 ∧ workPath.length > 0 ∧ corePath.length > 0 ∧ tacticPlan.length = 0 ∧ tacticCursor < tacticPlan.length ∧ tactic = adaptiveTactic ∧ result ∧ (tactic ≥ 0) ∧ (hypothesisSuggestions ≥ 0) ∧ (tacticPlan ≥ 0) ∧ (result ≥ 0) ∧ external_io_isolated" smt="(assert (and (> (str.len specPath) 0) (> (str.len workPath) 0) (> (str.len corePath) 0) (= (str.len tacticPlan) 0) (< tacticCursor (str.len tacticPlan)) (= tactic adaptiveTactic) result (>= tactic 0) (>= hypothesisSuggestions 0) (>= tacticPlan 0) (>= result 0) external_io_isolated))"



