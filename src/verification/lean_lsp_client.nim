import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/asyncdispatch
import std/asyncfutures
import std/exitprocs
import std/json
import std/locks
import std/osproc
import std/os
import std/sequtils
import std/tables
import std/times
import core/lean_lsp_types
import verification/lean_lsp_protocol
import core/utils/io_utils
import core/runtime_context
import core/trusted/axiom_pragmas
import core/utils/repo_root
# axiomIoBoundary

proc safeWaitFor*[T](fut: Future[T]): T {.raises: [AxiomLspError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  {.cast(raises: [AxiomLspError]).}:
    try:
      return waitFor(fut)
    except CatchableError as e:
      raise newException(AxiomLspError, "LSP operation failed: " & e.msg, e)

## Check whether the `lean` executable is available on PATH or via elan.
proc checkLeanAvailable*(): bool {.raises: [OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns true when `lean` (or `lake env lean`) can be found.
  let exe = findExe("lean")
  if exe.len > 0:
    return true
  # Also accept "lake env lean" path where lake resolves lean internally
  let lake = findExe("lake")
  if lake.len > 0:
    return true
  # Fall back to elan-managed install location
  let home = getHomeDir()
  let elanLean = home / ".elan" / "bin" / "lean"
  if fileExists(elanLean):
    return true
  let elanLeanExe = home / ".elan" / "bin" / "lean.exe"
  if fileExists(elanLeanExe):
    return true
  false

# Module-level context pointer for exit-hook cleanup.
# Set once in startLeanLsp; used by globalCleanup on process exit.
var gCtx: ptr VerificationRuntimeContext = nil

# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
# @axiom-hint: lean="pid > 0 ∧ external_io_isolated" smt="(assert (and (> pid 0) external_io_isolated))"
proc killProcessTree*(p: Process) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if p.isNil:
    return
  try:
    when defined(windows):
      let pid = processID(p)
      if pid > 0:
        discard execCmdEx("taskkill /PID " & $pid & " /T /F")
      else:
        terminate(p)
    else:
      terminate(p)
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)

# @axiom-hint: lean="leanExe.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len leanExe) 0) external_io_isolated))"
# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
proc startLeanLsp*(ctx: var VerificationRuntimeContext; leanExe: string): LeanLspClient {.raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Pre-flight check: if neither an explicit leanExe nor the system-wide `lean`
  ## binary is available, raise early with a helpful installation hint instead of
  ## letting startProcess fail with an opaque OS error.
  gCtx = addr ctx
  let leanCommand = resolveLeanExe(leanExe)
  if leanCommand.len == 0:
    discard writeStderrLine("Lean 4 not found. Install via: elan self update && elan toolchain install stable")
    raise newException(IOError, "Lean 4 executable not found — cannot start LSP client")
  let p = startProcess(
    command = leanCommand,
    args = @["--server"],
    options = {poUsePath}
  )

  let client = LeanLspClient(
    p: p,
    input: p.inputStream(),
    output: p.outputStream(),
    nextId: 0,
    uri: "",
    version: 0,
    pendingRequests: initTable[int, Future[JsonNode]](),
    notifications: @[],
    isShutdown: false
  )

  # IoC callback binding — decouples client from concrete process management
  # Use {.cursor.} on captured ref to break GC cycle: client → onShutdown closure → client
  block:
    let c {.cursor.}: LeanLspClient = client
    client.onShutdown = proc() {.closure, raises: [].} =
      if not c.p.isNil:
        try:
          c.onKillProcess(c.p)
        except CatchableError:
          discard  # best-effort  # axiom:best-effort(ioboundary catch)
  client.onKillProcess = proc(p: Process) {.closure, raises: [CatchableError].} =
    killProcessTree(p)

  client.msgChannel.open()
  createThread(client.readerThread, readerThreadFunc, client)

  # LSP 3.17 initialize handshake — required before any other communication
  let repoRoot = repo_root.findRepoRoot(getCurrentDir())
  let rootUri = toFileUri(repoRoot)
  let initFut = sendInitialize(client, rootUri)
  var waitCycles = 0
  while not initFut.finished and waitCycles < 500:
    client.pollMessages()
    sleep(10)
    inc waitCycles
  if not initFut.finished:
    discard writeStderrLine("[lean_lsp] initialize handshake timed out")
  sendInitializedNotification(client)
  client.pollMessages()

  withLock(ctx.lspPool.gate):
    ctx.lspPool.activeClients.add(client)

  client

proc shutdown*(client: LeanLspClient; ctx: var VerificationRuntimeContext)  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if client.isShutdown: return
  client.isShutdown = true

  try:
    if client.msgChannel.ready:
      client.msgChannel.close()
  except CatchableError as e:
    discard writeStderrLine("Lean LSP channel close error: " & e.msg)

  try:
    discard client.sendRequest("shutdown", %*{})
    # Wait briefly for shutdown response, but don't block forever
    client.sendNotification("exit", %*{})
  except CatchableError as e:
    discard writeStderrLine("Lean LSP shutdown error: " & e.msg)

  # IoC: delegate process termination to the bound callback
  try:
    if not client.onShutdown.isNil:
      client.onShutdown()
    elif not client.p.isNil:
      killProcessTree(client.p)
      close(client.p)
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)

  # Remove from pool
  withLock(ctx.lspPool.gate):
    ctx.lspPool.activeClients.keepItIf(it != client)

const IdleTimeoutDefaultSec* = 300.0 ## 5 minutes default idle timeout

proc isHealthy*(client: LeanLspClient): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], axiomDecision.} =
  ## Health check: verifies client process is alive and message channel is ready.
  ## Returns false if the LSP process has crashed or the client is shut down.
  if client.isShutdown:
    return false
  if client.p.isNil:
    return false
  try:
    let exitCode = peekExitCode(client.p)
    if exitCode >= 0:
      return false
  except CatchableError:
    return false
  if not client.msgChannel.ready:
    return false
  true

proc cleanupIdleClients*(ctx: var VerificationRuntimeContext) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Removes clients that have been idle longer than idleTimeoutSec.
  ## Called lazily on acquireClient to avoid blocking overhead.
  let now = getTime()
  let timeout = if ctx.lspPool.idleTimeoutSec > 0.0: ctx.lspPool.idleTimeoutSec else: IdleTimeoutDefaultSec
  var kept: seq[LeanLspClient] = @[]
  withLock(ctx.lspPool.gate):
    for client in ctx.lspPool.activeClients:
      let elapsed = (now - client.lastUsed).inSeconds().float
      if elapsed <= timeout:
        kept.add(client)
      else:
        try:
          if not client.isShutdown:
            client.isShutdown = true
            if not client.onShutdown.isNil:
              client.onShutdown()
            elif not client.p.isNil:
              killProcessTree(client.p)
        except CatchableError:
          discard
    ctx.lspPool.activeClients = kept

proc acquireClient*(ctx: var VerificationRuntimeContext; leanExe: string = ""): LeanLspClient {.raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Acquires a LeanLspClient from the pool or creates a new one.
  ## Reuses idle clients when available; creates new only if pool is empty.
  ## Performs lazy idle timeout cleanup and health checking.
  let now = getTime()
  var reused = false
  withLock(ctx.lspPool.gate):
    for i in 0 ..< ctx.lspPool.activeClients.len:
      let candidate = ctx.lspPool.activeClients[i]
      if not isHealthy(candidate):
        continue
      if candidate.isShutdown:
        continue
      candidate.lastUsed = now
      ctx.lspPool.activeClients.delete(i)
      reused = true
      result = candidate
      break

  if reused:
    return result

  # No healthy pooled client available — create a new one
  # Lazy pool initialization with defaults
  if ctx.lspPool.idleTimeoutSec <= 0.0:
    ctx.lspPool.idleTimeoutSec = IdleTimeoutDefaultSec

  let clientLeanExe = if leanExe.len > 0: leanExe else: ""
  result = startLeanLsp(ctx, clientLeanExe)
  result.lastUsed = now

proc releaseClient*(client: LeanLspClient; ctx: var VerificationRuntimeContext) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns an idle client to the pool for reuse instead of shutting it down.
  ## Resets state (pending requests, notification buffer) for clean next use.
  if client.isShutdown:
    return
  withLock(ctx.lspPool.gate):
    client.pendingRequests.clear()
    client.notifications.setLen(0)
    client.nextId = 0
    client.lastUsed = getTime()
    if ctx.lspPool.maxPoolSize > 0 and ctx.lspPool.activeClients.len >= ctx.lspPool.maxPoolSize:
      # Pool at capacity — discard oldest client
      if not client.onShutdown.isNil:
        client.onShutdown()
      elif not client.p.isNil:
        killProcessTree(client.p)
    else:
      ctx.lspPool.activeClients.add(client)

## Request document symbols via LSP textDocument/documentSymbol and parse into
## a flat sequence of DocSymbolInfo entries (theorems, defs, namespaces, etc.).
proc getDocumentSymbols*(client: LeanLspClient; uri: string): seq[DocSymbolInfo] {.raises: [CatchableError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Calls the LSP ``textDocument/documentSymbol`` request, blocks until the
  ## response arrives, and returns a parsed list of symbol info records.
  ## Returns an empty sequence when the LSP is unavailable or the request fails.
  if not checkLeanAvailable():
    writeLine(stderr, "[lean_lsp] getDocumentSymbols skipped — lean executable not found")
    return @[]

  client.pollMessages()
  try:
    let respFut = client.sendRequest("textDocument/documentSymbol", %*{
      "textDocument": {"uri": uri}
    })
    var cycles = 0
    while not respFut.finished and cycles < 500:
      client.pollMessages()
      sleep(10)
      inc cycles
    if not respFut.finished:
      writeLine(stderr, "[lean_lsp] getDocumentSymbols timeout waiting for response")
      return @[]
    let resp = safeWaitFor(respFut)
    # Unwrap the JSON-RPC envelope: LSP returns {"jsonrpc","id","result":...},
    # not a bare array. Mirror the working overload in lean_lsp_protocol.nim.
    let data = if resp.kind == JObject and resp.hasKey("result"):
                 resp["result"]
               else:
                 resp
    case data.kind
    of JArray:
      for item in data.elems:
        result.add(extractSymbolsFromNode(item))
    else:
      discard
  except CatchableError as e:
    writeLine(stderr, "[lean_lsp] getDocumentSymbols error: " & e.msg)
    return @[]

# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
proc globalCleanup() {.noconv, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if gCtx.isNil: return
  withLock(gCtx[].lspPool.gate):
    for client in gCtx[].lspPool.activeClients:
      if not client.isNil and not client.isShutdown:
        client.shutdown(gCtx[])

addExitProc(globalCleanup)
