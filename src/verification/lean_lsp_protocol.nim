import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import ../core/trusted/axiom_pragmas
import core/json/json_utils
import core/lean_lsp_types
import core/logic/lean_diagnostic
import core/parsers/safe_parsers
import core/results
import core/utils/file_utils
import std/asyncfutures
import std/asyncdispatch
import std/osproc
import std/json
import std/options
import std/os
import std/sequtils
import std/streams
import std/strutils
import std/tables
import verification/state_manager
## Shutdown.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
# @axiom-hint: lean="client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false" smt="(assert (and (and (>= client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false))))"
# @axiom-hint: lean="client_isShutdown = true ∨ client_isShutdown = false" smt="(assert (and (or (= client_isShutdown true) (= client_isShutdown false))))"

# @axiom-hint: lean="path.length ≥ 0" smt="(assert (and (>= (str.len path) 0)))"
# axiomIoBoundary

proc hasKeyObject(node: JsonNode; key: string): bool =
  node.kind == JObject and node.hasKey(key) and node.getOrDefault(key).kind == JObject

## Shutdown.

# @axiom-hint: lean="path.length ≥ 0" smt="(assert (and (>= (str.len path) 0)))"
# axiomIoBoundary
proc toFileUri*(path: string): string {.raises: [Exception, CatchableError], axiom: ["(assert (and ast_parse_failed_isolated (and (>= client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false)) (or (= client_isShutdown true) (= client_isShutdown false))))", "ast_parse_failed_isolated ∧ client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ client_isShutdown = true ∨ client_isShutdown = false"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  "file:///" & normalizePathSeparators(absolutePath(path))
proc tryResolveLeanExe*(leanExe: string): string {.raises: [CatchableError], axiom: ["(assert (and (>= (str.len leanExe) 0) (> (str.len leanExe) 0) (> (str.len preferred) 0) (> (str.len fallback) 0) leanExe fallback elanCandidateWin elanCandidateUnix (=> (> (str.len leanExe) 0) (= result leanExe)) (=> (> (str.len preferred) 0) (= result leanExe)) (=> (> (str.len fallback) 0) (= result fallback))))", "leanExe.length ≥ 0 ∧ leanExe.length > 0 ∧ preferred.length > 0 ∧ fallback.length > 0 ∧ leanExe ∧ fallback ∧ elanCandidateWin ∧ elanCandidateUnix ∧ leanExe.length > 0 → result = leanExe ∧ preferred.length > 0 → result = leanExe ∧ fallback.length > 0 → result = fallback"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if leanExe.len > 0:
    let firstWord =
      if ' ' in leanExe:
        leanExe.split(' ')[0]
      else:
        leanExe
    let preferred = findExe(firstWord)
    if preferred.len > 0:
      return leanExe
    if fileExists(firstWord):
      return leanExe
    return ""
  let fallback = findExe("lean")
  if fallback.len > 0:
    return fallback
  let lakeExe = findExe("lake")
  if lakeExe.len > 0:
    return "lake env lean"
  let elanCandidateWin = getHomeDir() / ".elan" / "bin" / "lean.exe"
  if fileExists(elanCandidateWin):
    return elanCandidateWin
  let elanCandidateUnix = getHomeDir() / ".elan" / "bin" / "lean"
  if fileExists(elanCandidateUnix):
    return elanCandidateUnix
  ""
proc resolveLeanExe*(leanExe: string): string {.raises: [CatchableError], axiom: ["(assert (and (>= (str.len leanExe) 0) ast_parse_failed_isolated))", "leanExe.length ≥ 0 ∧ ast_parse_failed_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let resolved = tryResolveLeanExe(leanExe)
  if resolved.len > 0:
    return resolved
  raise newException(IOError, "lean executable not found. Install Lean 4 or pass --lean with a valid path.")
proc logRpc(client: LeanLspClient; direction: string; payload: JsonNode) {.raises: [Exception, ], axiom: ["(assert (and ast_parse_failed_isolated (and (>= client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false)) (>= (str.len direction) 0) (or (= client_isShutdown true) (= client_isShutdown false))))", "ast_parse_failed_isolated ∧ client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ direction.length ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let methodName = payload.getOrDefault("method").getStr("")
  if methodName notin ["textDocument/publishDiagnostics", "initialize", "shutdown"]:
    return
  let auditPath = joinPath("logs", "audit", "stream.jsonl")
  let extra = %*{
    "dir": direction,
    "method": methodName,
    "payload": payload
  }
  discard appendGenericAuditEvent(auditPath, "lean_lsp_rpc", "", extra)

## axiom-smt: (assert (and (and (>= client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false)) external_io_isolated (= (str.len line) 0) (<= contentLength 0) (= readBytes contentLength) (>= contentLength 0) (or (= client_isShutdown true) (= client_isShutdown false)) external_io_isolated))
## axiom-lean: client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ external_io_isolated ∧ line.length = 0 ∧ contentLength ≤ 0 ∧ readBytes = contentLength ∧ (contentLength ≥ 0) ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ external_io_isolated
proc readerThreadFunc*(client: LeanLspClient) {.axiom, axiomOpaque, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  while not client.isShutdown:
    try:
      var contentLength = -1
      var line = ""
      if not client.output.readLine(line):
        break
      if line.len == 0:
        continue
      let lowered = line.toLowerAscii()
      if lowered.startsWith("content-length:"):
        let parsed = safeParseInt(line.split(":", 1)[1].strip())
        if parsed.isOk:
          contentLength = parsed.get
        else:
          continue

      if contentLength <= 0:
        continue

      if not client.output.readLine(line):
        break

      var payload = newString(contentLength)
      let readBytes = client.output.readData(payload[0].addr, contentLength)
      if readBytes == contentLength:
        client.msgChannel.send(payload)
      else:
        break
    except CatchableError:
      break
proc pollMessages*(client: LeanLspClient) {.raises: [CatchableError, Exception], axiom: ["(assert (and ast_parse_failed_isolated (and (> = client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false)) (= (option.isSome nodeOpt) true) true (or (= client_isShutdown true) (= client_isShutdown false))))", "ast_parse_failed_isolated ∧ client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ nodeOpt.isSome = true ∧ true ∧ client_isShutdown = true ∨ client_isShutdown = false"].} =
  while true:
    let (hasMsg, msgText) = client.msgChannel.tryRecv()
    if not hasMsg: break
    let nodeOpt = parseJsonOpt(msgText)
    if nodeOpt.isSome:
      let node = nodeOpt.get()
      client.logRpc("recv", node)
      if node.hasKey("id"):
        let id = node.getOrDefault("id").getInt()
        if client.pendingRequests.hasKey(id):
          client.pendingRequests[id].complete(node)
          client.pendingRequests.del(id)
      elif node.hasKey("method"):
        client.notifications.add(node)
proc writeRpcMessage(client: LeanLspClient; payload: JsonNode) {.raises: [Exception, CatchableError], axiom: ["(assert (and (and (>= client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false)) (or (= client_isShutdown true) (= client_isShutdown false))))", "client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ client_isShutdown = true ∨ client_isShutdown = false"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  client.logRpc("send", payload)
  let body = $payload
  client.input.write("Content-Length: " & $body.len & "\c\L\c\L")
  client.input.write(body)
  client.input.flush()
proc sendNotification*(client: LeanLspClient; rpcMethod: string; params: JsonNode) {.raises: [CatchableError, Exception], axiom: ["(assert (and (and (>= client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false)) (>= (str.len rpcMethod) 0) (or (= client_isShutdown true) (= client_isShutdown false))))", "client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ rpcMethod.length ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  client.writeRpcMessage(%*{
    "jsonrpc": "2.0",
    "method": rpcMethod,
    "params": params
  })
proc sendRequest*(client: LeanLspClient; rpcMethod: string; params: JsonNode): Future[JsonNode] {.raises: [CatchableError, Exception], axiom: ["(assert (and ast_parse_failed_isolated (and (>= client_nextId -9223372036854775808) (<= client_nextId 9223372036854775807)) (>= (str.len client_uri) 0) (and (>= client_version -9223372036854775808) (<= client_version 9223372036854775807)) (>= (seq.len client_notifications) 0) (or (= client_isShutdown true) (= client_isShutdown false)) (>= (str.len rpcMethod) 0) (or (= client_isShutdown true) (= client_isShutdown false))))", "ast_parse_failed_isolated ∧ client_nextId ≥ -9223372036854775808 ∧ client_nextId ≤ 9223372036854775807 ∧ client_uri.length ≥ 0 ∧ client_version ≥ -9223372036854775808 ∧ client_version ≤ 9223372036854775807 ∧ client_notifications.size ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false ∧ rpcMethod.length ≥ 0 ∧ client_isShutdown = true ∨ client_isShutdown = false"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  client.nextId.inc()
  let id = client.nextId
  let fut = newFuture[JsonNode]("sendRequest:" & rpcMethod)
  client.pendingRequests[id] = fut
  client.writeRpcMessage(%*{
    "jsonrpc": "2.0",
    "id": id,
    "method": rpcMethod,
    "params": params
  })
  result = fut

proc sendInitialize*(client: LeanLspClient; rootUri: string): Future[JsonNode] {.raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## LSP 3.17 initialize handshake — sends 'initialize' request and waits for response.
  ## Returns the server's initialize response as JsonNode.
  let initParams = %*{
    "processId": getCurrentProcessId(),
    "clientInfo": {"name": "Axiom", "version": "v31"},
    "rootUri": rootUri,
    "capabilities": %*{}
  }
  result = client.sendRequest("initialize", initParams)

proc sendInitializedNotification*(client: LeanLspClient) {.raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## LSP 3.17 initialized notification — sent after successful initialize response.
  client.sendNotification("initialized", %*{})

proc extractGoalLines*(text: string): seq[string] {.axiom, axiomOpaque.} =
  ## Pure string processing — no side effects
  if text.len == 0: return @[]
  for line in text.splitLines():
    if line.startsWith("goal:") or line.startsWith("⊢"):
      result.add(line.strip())

## LSP Document Symbol type categories used by Lean 4.
type DocSymbolKind* = enum
  DskFile, DskModule, DskNamespace, DskDefinition,
  DskTheorem, DskLemma, DskSection, DskVariable,
  DskStructure, DskClass, DskMVar

proc extractDocSymbolKind*(node: JsonNode): DocSymbolKind =
  let k = node.getOrDefault("kind").getInt(0)
  case k
  of 1: DskFile
  of 2: DskModule
  of 3: DskNamespace
  of 12: DskDefinition
  of 13: DskTheorem
  of 14: DskLemma
  of 15: DskSection
  of 16: DskVariable
  of 23: DskStructure
  of 24: DskClass
  of 178: DskMVar  ## Lean 4 metavariable
  else: DskDefinition

type DocSymbolInfo* = object
  name*: string
  kind*: DocSymbolKind
  span*: (int, int)  ## (lineStart, lineEnd) 0-based

proc extractSymbolsFromNode*(node: JsonNode): seq[DocSymbolInfo] {.axiom, axiomOpaque.} =
  ## Recursively walk an LSP document-symbol JSON tree and collect flat info.
  if node.kind != JObject: return
  if not node.hasKey("name"): return
  let nameVal = node.getOrDefault("name")
  if nameVal.kind != JString: return
  let rangeNode = node.getOrDefault("range")
  if rangeNode.kind != JObject: return
  let startNode = rangeNode.getOrDefault("start")
  let endNode = rangeNode.getOrDefault("end")
  if startNode.kind != JObject or endNode.kind != JObject: return
  let sym = DocSymbolInfo(
    name: nameVal.getStr(""),
    kind: node.extractDocSymbolKind(),
    span: (
      startNode.getOrDefault("line").getInt(0),
      endNode.getOrDefault("line").getInt(0)
    )
  )
  result.add(sym)
  let childrenNode = node.getOrDefault("children")
  if childrenNode.isNil: return
  if childrenNode.kind == JArray:
    for child in childrenNode.elems:
      result.add(extractSymbolsFromNode(child))

## axiom-smt: (assert (and (>= depth 0) JString JArray JObject))
## axiom-lean: depth >= 0 ∧ JString ∧ JArray ∧ JObject
proc extractStrings(node: JsonNode): seq[string] {.axiom, axiomOpaque.} =
  if node.kind == JString:
    result.add(node.getStr())
  elif node.kind == JArray:
    for item in node.elems:
      result.add(extractStrings(item))
  elif node.kind == JObject:
    for _, value in node.pairs:
      result.add(extractStrings(value))

## Extract Lean Goals From Json.
## axiom-smt: (assert (and (>= depth 0) (>= texts 0) (>= result 0)))
## axiom-lean: depth >= 0 ∧ (texts ≥ 0) ∧ (result ≥ 0)
proc extractLeanGoalsFromJson*(node: JsonNode): seq[string] {.axiom, axiomOpaque.} =
  let texts = extractStrings(node)
  for text in texts:
    result.add(extractGoalLines(text))
  result = result.deduplicate()

## axiom-smt: (assert (and (>= depth 0) (>= diag 0)))
## axiom-lean: depth >= 0 ∧ (diag ≥ 0)
proc parseDiagnostics*(payload: JsonNode): seq[LeanDiagnostic] {.axiom, axiomOpaque.} =
  if not hasKeyObject(payload, "params"):
    return @[]
  let params = payload.getOrDefault("params")
  if not (params.kind == JObject and params.hasKey("diagnostics") and params.getOrDefault("diagnostics").kind == JArray):
    return @[]
  for item in params.getOrDefault("diagnostics").elems:
    if item.kind != JObject:
      continue
    var diag = LeanDiagnostic(line: 0, character: 0, severity: 1, message: "")
    if item.hasKey("message") and item.getOrDefault("message").kind == JString:
      diag.message = item.getOrDefault("message").getStr()
    if item.hasKey("code") and item.getOrDefault("code").kind == JString:
      diag.code = item.getOrDefault("code").getStr()
    elif item.hasKey("code") and item.getOrDefault("code").kind in {JInt, JFloat}:
      diag.code = $item.getOrDefault("code").getInt()
    if item.hasKey("severity") and item.getOrDefault("severity").kind in {JInt, JFloat}:
      diag.severity = item.getOrDefault("severity").getInt()
    if item.hasKey("range") and item.getOrDefault("range").kind == JObject:
      let range = item.getOrDefault("range")
      if range.hasKey("start") and range.getOrDefault("start").kind == JObject:
        let pos = range.getOrDefault("start")
        if pos.hasKey("line") and pos.getOrDefault("line").kind in {JInt, JFloat}:
          diag.line = pos.getOrDefault("line").getInt()
        if pos.hasKey("character") and pos.getOrDefault("character").kind in {JInt, JFloat}:
          diag.character = pos.getOrDefault("character").getInt()
    diag.kind = diagnosticKind(diag.message)
    result.add(diag)

proc getAccumulatedDiagnosticsFor*(client: LeanLspClient; uri: string): seq[JsonNode] {.raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Drain all pending channel messages; return diagnostics matching `uri`.
  ## Only Error(1) and Warning(2) severity included.
  ## Increments client.diagnosticNotificationCount when publishDiagnostics
  ## notifications are observed (proves LSP executed).
  ## Raises on poll failure — caller must handle.
  client.pollMessages()
  result = @[]
  var remaining: seq[JsonNode] = @[]
  for notif in client.notifications:
    if notif{"method"}.getStr("") == "textDocument/publishDiagnostics":
      if notif{"params"}{"uri"}.getStr("") == uri:
        inc client.diagnosticNotificationCount
        for d in notif{"params"}{"diagnostics"}:
          if d{"severity"}.getInt(1) <= 2:  # Error(1) + Warning(2)
            result.add(d)
    else:
      remaining.add(notif)
  client.notifications = remaining

proc checkLeanSource*(client: LeanLspClient; uri, source: string; maxWaitCycles: int = 500): Result[bool, string] {.raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## EOF-coordinate sync barrier: didOpen → hover (barrier) → diagnostics → didClose.
  ## Returns ok(true) if no diagnostics (verification passed),
  ## ok(false) if diagnostics found,
  ## err("lsp-hover-barrier-exception") if hover request fails,
  ## err("lsp-hover-timeout") if hover does not complete within maxWaitCycles*10ms,
  ## err("lsp-diagnostics-poll-failure") if diagnostics polling fails.
  ## maxWaitCycles: Testability hook — default 500 (~5s real-time with 10ms sleep).
  ##
  ## Pre-flight: if the `lean` executable is absent, short-circuit with ok(false)
  ## and a stderr warning instead of crashing the caller.  This provides defence-
  ## in-depth — callers that bypass startLeanLsp's own guardrail still get a safe
  ## fallback rather than an opaque OS error.

  # 0. Lean availability gate
  if findExe("lean").len == 0:
    writeLine(stderr, "[lean_lsp] warning: lean executable not found on PATH — skipping LSP verification")
    return ok(false)

  # 1. didOpen — inject source
  client.sendNotification("textDocument/didOpen", %*{
    "textDocument": {"uri": uri, "languageId": "lean4", "version": 1, "text": source}
  })

  # 2. Compute EOF coordinates
  let lines = source.splitLines()
  let lastLineIdx = lines.high
  let lastCharIdx = if lines.len > 0: lines[^1].len else: 0

  # 3. Sync barrier (EOF hover — guarantees full file elaboration)
  #    Spin-poll until the reader thread fulfills the future, with timeout.
  try:
    let hoverFut = client.sendRequest("textDocument/hover", %*{
      "textDocument": {"uri": uri},
      "position": {"line": lastLineIdx, "character": lastCharIdx}
    })
    var waitCycles = 0
    while not hoverFut.finished and waitCycles < maxWaitCycles:
      client.pollMessages()
      sleep(10)
      inc waitCycles
    if not hoverFut.finished:
      return err("lsp-hover-timeout")
  except CatchableError:
    return err("lsp-hover-barrier-exception")

  # 4. Grace period — allow pending diagnostics to drain after hover completes.
  ## A crashed/deadlocked LSP may have pushed diagnostics into the IPC buffer
  ## but not yet delivered them. Without this window we lose legitimate error
  ## reports and return ok(true) — degenerating into Theater Signature #4
  ## (empty / missing data interpreted as success). Full detail:
  ## AGENTS.md §0.9, DEBT#277.
  for _ in 0 ..< 20:
    client.pollMessages()
    sleep(10)

  # 5. Post-hover liveness check — verify LSP process is still alive.
  ## If the LSP exited between hover response and this point, we cannot trust
  ## that it processed our didOpen or generated complete diagnostics. Treating
  ## empty diagnostics from a dead LSP as success is Theater Signature #4
  ## (AGENTS.md §0.9). Fail-closed: exit code ≥ 0 → error.
  {.push warning[BareExcept]: off.}
  try:
    let procExitCode = peekExitCode(client.p)
    if procExitCode >= 0:
      return err("lsp-process-exited: LSP process terminated with code " &
        $procExitCode & " between hover and diagnostics collection")
  except CatchableError as e:
    return err("lsp-liveness-check-failed: " & e.msg)
  except:
    let errMsg = getCurrentExceptionMsg()
    writeLine(stderr, "[lean_lsp] liveness check exception: " & errMsg)
    return err("lsp-liveness-check-unexpected: " & errMsg)
  {.pop.}

  # 6. Collect diagnostics
  var diagnostics: seq[JsonNode]
  try:
    diagnostics = client.getAccumulatedDiagnosticsFor(uri)
  except CatchableError:
    return err("lsp-diagnostics-poll-failure")

  # 7. didClose
  client.sendNotification("textDocument/didClose", %*{
    "textDocument": {"uri": uri}
  })

  # 8. P1 diagnostic capture — persist the verification string submitted to
  #     the Lean LSP together with any diagnostics (range + message + the
  #     offending source line) so `<string>(line, col)` reports can be mapped
  #     to the exact text post-hoc from logs/lean_lsp_payloads.jsonl.
  #     Fail-open: capture failures are discarded (diagnostic aid only, never
  #     blocks validation).
  # axiom:best-effort(lean payload capture is diagnostic-only; failures never block LSP validation)
  try:
    let srcLines = source.splitLines()
    var diagCtx: seq[JsonNode] = @[]
    for d in diagnostics:
      let lineNo = d{"range"}{"start"}{"line"}.getInt(0)
      let ctxLine = if lineNo >= 0 and lineNo < srcLines.len: srcLines[lineNo] else: ""
      diagCtx.add(%*{
        "line": lineNo,
        "character": d{"range"}{"start"}{"character"}.getInt(0),
        "severity": d{"severity"}.getInt(0),
        "message": d{"message"}.getStr(""),
        "sourceLine": ctxLine
      })
    discard appendGenericAuditEvent("logs/lean_lsp_payloads.jsonl", "lean_lsp_check_source", "", %*{
      "uri": uri,
      "source": source,
      "diagnostics": diagCtx
    })
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  return ok(diagnostics.len == 0)

## ── Axiom-aware verification (Stage 1.5 defense-in-depth) ─────────────────
## After a definition type-checks, a `#print axioms <defName>` round-trip
## captures the exact axiom set the definition depends on. If that set
## contains `sorryAx` (or any axiom outside the allowlist), the definition is
## treated as NOT-verified so the Stage 1.5 type-level router falls back to
## Z3 BMC (fail-open by design).

const LeanAxiomAllowlist* = [
  "Classical.choice", "Quot.sound", "propext", "funext"
]

func isLeanAxiomAllowed*(axiom: string): bool {.raises: [].} =
  ## True when `axiom` is in `LeanAxiomAllowlist`.
  axiom in LeanAxiomAllowlist

func containsUnsafeAxiom*(axioms: seq[string]): bool {.raises: [].} =
  ## True if any captured axiom is a sorry axiom (`sorryAx` / `Lean.sorryAx`)
  ## or is not in the allowlist. The rejection predicate for the axiom gate.
  for axiom in axioms:
    if axiom.contains("sorryAx"):
      return true
    if not isLeanAxiomAllowed(axiom):
      return true
  false

func extractAxiomsFromDiagnosticMessage*(message: string): seq[string] {.raises: [].} =
  ## Parse `#print axioms` output delivered as an LSP Info(3) diagnostic of the
  ## form `'clamp' depends on axioms: [propext, Classical.choice]`.
  ## Returns an empty seq for `'clamp' does not depend on any axioms`.
  const marker = "depends on axioms: ["
  let idx = message.find(marker)
  if idx < 0:
    return @[]
  let startIdx = idx + marker.len
  let endIdx = message.find(']', startIdx)
  if endIdx < 0:
    return @[]
  let inner = message[startIdx ..< endIdx]
  if inner.strip().len == 0:
    return @[]
  for part in inner.split(','):
    let p = part.strip()
    if p.len > 0 and p notin result:
      result.add(p)

proc getAccumulatedAxiomDiagnosticsFor*(client: LeanLspClient; uri: string): seq[string]
  {.raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Drain pending channel messages; return `#print axioms` output strings
  ## (Info-severity publishDiagnostics messages carrying "axioms" / "depends on")
  ## matching `uri`. Unlike `getAccumulatedDiagnosticsFor`, severity-3 (Info)
  ## messages are NOT filtered out, because `#print axioms` reports as Info.
  ## Fail-open: any poll failure yields an empty seq (caller treats as NOT-verified).
  client.pollMessages()
  result = @[]
  var remaining: seq[JsonNode] = @[]
  for notif in client.notifications:
    if notif{"method"}.getStr("") == "textDocument/publishDiagnostics":
      if notif{"params"}{"uri"}.getStr("") == uri:
        for d in notif{"params"}{"diagnostics"}:
          let msg = d{"message"}.getStr("")
          if "axioms" in msg or "depends on" in msg:
            result.add(msg)
      else:
        remaining.add(notif)
    else:
      remaining.add(notif)
  client.notifications = remaining

type
  LeanAxiomCheckResult* = object
    compiled*: bool            ## true only if compiled AND axiom set is safe (+ confirmed)
    axiomsUsed*: seq[string]   ## axiom names captured from `#print axioms`

proc checkLeanSourceWithAxioms*(client: LeanLspClient; uri, defName, source: string;
                                 maxWaitCycles: int = 500): Result[LeanAxiomCheckResult, string]
  {.raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Axiom-aware variant of `checkLeanSource` used by the Stage 1.5 type-level
  ## router. First type-checks the source via the standard EOF barrier, then
  ## performs a `#print axioms <defName>` round-trip on a fresh doc URI, captures
  ## the reported axiom set, and rejects (`compiled = false`) if it contains
  ## `sorryAx` or any axiom outside `LeanAxiomAllowlist`.
  ##
  ## Fail-open by design: any uncertainty (axiom output not captured, hover
  ## timeout, exception) is treated as NOT-verified so the router falls through
  ## to Z3 BMC. Hard protocol failures return `err`; unsafe-or-unconfirmable
  ## axiom sets return `ok(false)`.

  # 1. Compile check through the standard EOF barrier.
  let compileResult = checkLeanSource(client, uri, source, maxWaitCycles)
  if compileResult.isErr:
    return err(compileResult.error)
  if not compileResult.get:
    return ok(LeanAxiomCheckResult(compiled: false, axiomsUsed: @[]))

  # 2. Axioms round-trip: append `#print axioms <defName>` to a fresh doc URI
  #    and re-poll with the same EOF hover barrier used by checkLeanSource.
  let axiomSource = source & "\n#print axioms " & defName & "\n"
  let axiomUri = "file:///trivial_router_axioms_" & defName & ".lean"
  try:
    client.sendNotification("textDocument/didOpen", %*{
      "textDocument": {"uri": axiomUri, "languageId": "lean4", "version": 1, "text": axiomSource}
    })
    let lines = axiomSource.splitLines()
    let lstIdx = lines.high
    let lstChar = if lines.len > 0: lines[^1].len else: 0
    let hoverFut = client.sendRequest("textDocument/hover", %*{
      "textDocument": {"uri": axiomUri},
      "position": {"line": lstIdx, "character": lstChar}
    })
    var waitCycles = 0
    while not hoverFut.finished and waitCycles < maxWaitCycles:
      client.pollMessages()
      sleep(10)
      inc waitCycles
    if not hoverFut.finished:
      client.sendNotification("textDocument/didClose", %*{"textDocument": {"uri": axiomUri}})
      return ok(LeanAxiomCheckResult(compiled: false, axiomsUsed: @[]))
    for _ in 0 ..< 20:
      client.pollMessages()
      sleep(10)
    let axiomMsgs = client.getAccumulatedAxiomDiagnosticsFor(axiomUri)
    client.sendNotification("textDocument/didClose", %*{"textDocument": {"uri": axiomUri}})

    # 3. Extract and validate the captured axiom set.
    var axioms: seq[string] = @[]
    for msg in axiomMsgs:
      for a in extractAxiomsFromDiagnosticMessage(msg):
        if a notin axioms:
          axioms.add(a)

    # 4. Fail-open: if no axiom report was captured we cannot confirm the
    #    definition is sorry-free → treat as NOT-verified (not false-pass).
    if axiomMsgs.len == 0:
      return ok(LeanAxiomCheckResult(compiled: false, axiomsUsed: @[]))
    if containsUnsafeAxiom(axioms):
      return ok(LeanAxiomCheckResult(compiled: false, axiomsUsed: axioms))
    return ok(LeanAxiomCheckResult(compiled: true, axiomsUsed: axioms))
  except CatchableError as e:
    try:
      client.sendNotification("textDocument/didClose", %*{"textDocument": {"uri": axiomUri}})
    except CatchableError:
      discard  # axiom:best-effort(lsp didClose cleanup)
    return err("lsp-axioms-roundtrip-exception: " & e.msg)

## Lean LSP Document Symbol types — cross-language symbol graph integration

type
  LeanDocumentSymbolKind* = enum
    lskFile, lskModule, lskNamespace, lskClass, lskMethod, lskProperty,
    lskField, lskConstructor, lskEnum, lskInterface, lskFunction,
    lskVariable, lskConstant, lskString, lskNumber, lskBoolean, lskArray,
    lskObject, lskKey, lskNull, lskEnumMember, lskStruct, lskEvent,
    lskOperator, lskTypeParameter

  LeanDocumentSymbol* = object
    name*: string
    detail*: string
    kind*: LeanDocumentSymbolKind
    rangeStartLine*: int
    rangeStartChar*: int
    rangeEndLine*: int
    rangeEndChar*: int
    children*: seq[LeanDocumentSymbol]

func `$`*(kind: LeanDocumentSymbolKind): string {.raises: [].} =
  case kind
  of lskFile:            "File"
  of lskModule:          "Module"
  of lskNamespace:       "Namespace"
  of lskClass:           "Class"
  of lskMethod:          "Method"
  of lskProperty:        "Property"
  of lskField:           "Field"
  of lskConstructor:     "Constructor"
  of lskEnum:            "Enum"
  of lskInterface:       "Interface"
  of lskFunction:        "Function"
  of lskVariable:        "Variable"
  of lskConstant:        "Constant"
  of lskString:          "String"
  of lskNumber:          "Number"
  of lskBoolean:         "Boolean"
  of lskArray:           "Array"
  of lskObject:          "Object"
  of lskKey:             "Key"
  of lskNull:            "Null"
  of lskEnumMember:      "EnumMember"
  of lskStruct:          "Struct"
  of lskEvent:           "Event"
  of lskOperator:        "Operator"
  of lskTypeParameter:   "TypeParameter"

## Parse a single Lean LSP DocumentSymbol JsonNode into LeanDocumentSymbol.
proc parseDocumentSymbol*(node: JsonNode): LeanDocumentSymbol {.raises: [Exception, CatchableError].} =
  if node.kind != JObject:
    raise newException(ValueError, "expected JObject for DocumentSymbol")
  result.name = node.getOrDefault("name").getStr("")
  result.detail = node.getOrDefault("detail").getStr("")
  result.rangeStartLine = node.getOrDefault("range"){"start"}{"line"}.getInt(0)
  result.rangeStartChar = node.getOrDefault("range"){"start"}{"character"}.getInt(0)
  result.rangeEndLine = node.getOrDefault("range"){"end"}{"line"}.getInt(0)
  result.rangeEndChar = node.getOrDefault("range"){"end"}{"character"}.getInt(0)
  let rawKind = node.getOrDefault("kind").getInt(7)  # default: Function (LSP value 12)
  case rawKind
  of 1:  result.kind = lskFile
  of 2:  result.kind = lskModule
  of 3:  result.kind = lskNamespace
  of 5:  result.kind = lskClass
  of 6:  result.kind = lskMethod
  of 7:  result.kind = lskProperty
  of 8:  result.kind = lskField
  of 9:  result.kind = lskConstructor
  of 10: result.kind = lskEnum
  of 11: result.kind = lskInterface
  of 12: result.kind = lskFunction
  of 13: result.kind = lskVariable
  of 14: result.kind = lskConstant
  of 15: result.kind = lskString
  of 16: result.kind = lskNumber
  of 17: result.kind = lskBoolean
  of 18: result.kind = lskArray
  of 19: result.kind = lskObject
  of 20: result.kind = lskKey
  of 21: result.kind = lskNull
  of 22: result.kind = lskEnumMember
  of 23: result.kind = lskStruct
  of 24: result.kind = lskEvent
  of 25: result.kind = lskOperator
  of 26: result.kind = lskTypeParameter
  else:  result.kind = lskFunction
  # Recursively parse children
  if node.hasKey("children") and node.getOrDefault("children").kind == JArray:
    for child in node.getOrDefault("children"):
      result.children.add(parseDocumentSymbol(child))

## Extract value from a Future[JsonNode].
## Defined in lean_lsp_future.nim to avoid the {raises:[]} pragma context
## which filters out Future.get during overload resolution.
import verification/lean_lsp_future
export lean_lsp_future.getFutureValue

## Request document symbols from a running Lean LSP server for the given file URI.
## Returns empty sequence if LSP is unavailable or request fails.
proc getDocumentSymbols*(client: LeanLspClient; uri: string): seq[LeanDocumentSymbol] {.raises: [Exception, CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let response = client.sendRequest("textDocument/documentSymbol", %*{
      "textDocument": {"uri": uri}
    })
    var waitCycles = 0
    while not response.finished and waitCycles < 500:
      client.pollMessages()
      sleep(10)
      inc waitCycles
    if not response.finished:
      return @[]
    let data = getFutureValue(response)
    if data.kind == JArray:
      for item in data.elems:
        try:
          result.add(parseDocumentSymbol(item))
        except ValueError:
          discard  # skip malformed symbols
  except CatchableError:
    discard  # axiom:best-effort(lsp request failure)

## Map LSP SymbolKind number to Lean-specific symbol kind.
func leanSymbolKindFromLsp*(num: int): LeanSymbolKind {.raises: [].} =
  case num
  of 12: lskDef       ## Function → def / theorem body
  of 5:  lskClass     ## Class → structure/class
  of 23: lskStructure ## Struct → structure
  of 13: lskTheorem   ## Variable → theorem name
  of 14: lskLemma     ## Constant → lemma
  of 10: lskInductive ## Enum → inductive type
  of 6:  lskOther     ## Method → other
  else: lskOther

## Parse a single DocumentSymbol JsonNode into a LeanSymbol.
func parseLeanSymbol(node: JsonNode): LeanSymbol {.raises: [].} =
  if node.kind != JObject: return default(LeanSymbol)

  var sym = LeanSymbol()

  if node.hasKey("name") and node.getOrDefault("name").kind == JString:
    sym.name = node.getOrDefault("name").getStr()
  else:
    return default(LeanSymbol)

  if node.hasKey("kind") and node.getOrDefault("kind").kind in {JInt, JFloat}:
    sym.kind = leanSymbolKindFromLsp(node.getOrDefault("kind").getInt())
  else:
    sym.kind = lskOther

  if node.hasKey("range") and node.getOrDefault("range").kind == JObject:
    let rangeNode = node.getOrDefault("range")
    if rangeNode.hasKey("start") and rangeNode.getOrDefault("start").kind == JObject:
      let start = rangeNode.getOrDefault("start")
      if start.hasKey("line") and start.getOrDefault("line").kind in {JInt, JFloat}:
        sym.range.startLine = start.getOrDefault("line").getInt()
      if start.hasKey("character") and start.getOrDefault("character").kind in {JInt, JFloat}:
        sym.range.startCol = start.getOrDefault("character").getInt()
    if rangeNode.hasKey("end") and rangeNode.getOrDefault("end").kind == JObject:
      let endPos = rangeNode.getOrDefault("end")
      if endPos.hasKey("line") and endPos.getOrDefault("line").kind in {JInt, JFloat}:
        sym.range.endLine = endPos.getOrDefault("line").getInt()
      if endPos.hasKey("character") and endPos.getOrDefault("character").kind in {JInt, JFloat}:
        sym.range.endCol = endPos.getOrDefault("character").getInt()

  if node.hasKey("children") and node.getOrDefault("children").kind == JArray:
    for child in node.getOrDefault("children").elems:
      let parsedChild = parseLeanSymbol(child)
      if parsedChild.name.len > 0:
        sym.children.add(parsedChild)

  result = sym

## Request document symbols and return simplified LeanSymbol sequence.
## Returns empty sequence on timeout or parse failure.
proc getDocumentSymbols*(client: LeanLspClient; uri: string; maxWaitCycles: int = 500): seq[LeanSymbol] {.raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let docSymFut = client.sendRequest("textDocument/documentSymbol", %*{
    "textDocument": {"uri": uri}
  })
  var waitCycles = 0
  while not docSymFut.finished and waitCycles < maxWaitCycles:
    client.pollMessages()
    sleep(10)
    inc waitCycles
  if not docSymFut.finished:
    return @[]
  try:
    let resp = getFutureValue(docSymFut)
    if resp.kind == JArray:
      for item in resp.elems:
        let sym = parseLeanSymbol(item)
        if sym.name.len > 0:
          result.add(sym)
    elif resp.kind == JObject and resp.hasKey("result") and resp.getOrDefault("result").kind == JArray:
      for item in resp.getOrDefault("result").elems:
        let sym = parseLeanSymbol(item)
        if sym.name.len > 0:
          result.add(sym)
  except CatchableError:
    return @[]

# Shutdown.
# @axiom-hint: lean="path.length ≥ 0" smt="(assert (and (>= (str.len path) 0)))"
# axiomIoBoundary

## Parse `$/lean/plainGoal` JSON response into goal components.
proc parsePlainGoalResponse*(node: JsonNode): seq[string] {.axiom, axiomOpaque.} =
  ## Extract structured goal text from plainGoal response.
  ## The Lean 4 LSP server returns either:
  ##   { "goal": "...", "localContext": [...] }
  ## or a simple string.
  if node.kind == JString:
    return @[node.getStr()]
  elif node.kind == JObject:
    if node.hasKey("goal"):
      result.add(node.getOrDefault("goal").getStr())
    if node.hasKey("localContext") and node.getOrDefault("localContext").kind == JArray:
      for entry in node.getOrDefault("localContext").elems:
        if entry.kind == JString:
          result.add(entry.getStr())
        elif entry.kind == JObject:
          # Some versions return objects with "name" + "type" fields
          if entry.hasKey("name") and entry.hasKey("type"):
            result.add(entry.getOrDefault("name").getStr() & ": " & entry.getOrDefault("type").getStr())
          else:
            # Fallback: serialize as string
            result.add($entry)
  # If unrecognized format, return empty (caller handles gracefully)

## Get proof goal at position via `$/lean/plainGoal` Lean-specific LSP method.
## Returns ok(goalText) with structured goal, or err(message) on failure.
## Uses positional query instead of parsing hover markdown output.
proc getPlainGoal*(client: LeanLspClient; uri: string; line, character: int): Result[string, string] {.raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let plainGoalMethod = "$" & "/lean/plainGoal"
    let fut = client.sendRequest(plainGoalMethod, %*{
      "textDocument": {"uri": uri},
      "position": {"line": line, "character": character}
    })
    var waitCycles = 0
    while not fut.finished and waitCycles < 500:
      client.pollMessages()
      sleep(10)
      inc waitCycles
    if not fut.finished:
      return err("lsp-plainGoal-timeout")
    let resp = fut.read()
    let parsed = parsePlainGoalResponse(resp)
    if parsed.len > 0:
      return ok(parsed.join("\n"))
    else:
      return err("lsp-plainGoal-empty-response")
  except CatchableError as e:
    return err("lsp-plainGoal-error: " & e.msg)
