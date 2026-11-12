import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Scoped Resource Management for Axiom Gate Operations
##
## Provides RAII-style templates that guarantee cleanup of:
## - ManagedProcess (stdout/stdin pipe FDs)
## - Selector (epoll/kqueue handle)
## - Environment variables (AXIOM_RECURSION_GUARD, AXIOM_GATE_CONTEXT_ID)
##
## Nim's `defer` inside a template extends its scope to the calling block,
## so cleanup runs on any exit path — exception, quit(), or early return.
##
## Usage:
##   withGateContext:
##     gateSelector = newSelector[int]()
##     gateProcess = spawnManaged(cmd, workingDir = dir)
##     registerWithSelector(gateSelector, gateProcess, 0)
##     closeStdin(gateProcess)
##     # ... work ...
##     # cleanup is automatic on block exit
##
## Before (gate_hook.nim runGateHook):
##   var mp = spawnManaged(...)
##   var sel = newSelector[int]()
##   registerWithSelector(sel, mp, 0)
##   closeStdin(mp)
##   # ... polling loop ...
##   sel.close()        # ← outside try/finally: leaks on exception
##   closeManaged(mp)   # ← same problem
##
## After:
##   withGateContext:
##     gateProcess = spawnManaged(...)
##     gateSelector = newSelector[int]()
##     registerWithSelector(gateSelector, gateProcess, 0)
##     closeStdin(gateProcess)
##     # ... polling loop ...
##     # sel.close() and closeManaged(mp) are automatic

import std/[os, selectors]
import ./process_selector

template withGateContext*(body: untyped) =
  ## RAII wrapper for gate operations that own a Selector and ManagedProcess.
  ##
  ## Injects the following variables into `body`:
  ##   - `gateSelector: Selector[int]` — the I/O event selector
  ##   - `gateProcess: ManagedProcess` — the managed subprocess
  ##   - `gateSelectorInited: bool` — tracks whether selector was assigned
  ##   - `gateProcessInited: bool` — tracks whether process was assigned
  ##
  ## Cleanup order (reverse of acquisition):
  ##   1. AXIOM_RECURSION_GUARD  env var
  ##   2. AXIOM_GATE_CONTEXT_ID  env var
  ##   3. Selector                (unregister + close)
  ##   4. ManagedProcess          (kill if alive, close pipe FDs)
  ##
  ## Set `gateSelectorInited = true` after assigning `gateSelector`.
  ## Set `gateProcessInited = true` after assigning `gateProcess`.
  block:
    var gateSelector {.inject.}: Selector[int]
    var gateProcess {.inject.}: ManagedProcess
    var gateSelectorInited {.inject.} = false
    var gateProcessInited {.inject.} = false

    defer:
      # ── Env var cleanup (always safe, idempotent) ──
      if existsEnv("AXIOM_RECURSION_GUARD"):
        delEnv("AXIOM_RECURSION_GUARD")
      if existsEnv("AXIOM_GATE_CONTEXT_ID"):
        delEnv("AXIOM_GATE_CONTEXT_ID")

      # ── Selector cleanup (unregister handles before close) ──
      if gateSelectorInited:
        try:
          if gateProcessInited and gateProcess.stdoutRead >= 0:
            unregisterFromSelector(gateSelector, gateProcess)
        except CatchableError:
          discard  # best-effort unregister  # axiom:best-effort(ioboundary catch)
        try:
          gateSelector.close()
        except CatchableError:
          discard  # selector already closed or invalid  # axiom:best-effort(ioboundary catch)

      # ── Process cleanup (kill if alive, close pipe FDs) ──
      if gateProcessInited:
        killManaged(gateProcess)
        closeManaged(gateProcess)

    body

template withTimeout*(timeoutMs: int; body: untyped) =
  ## Execute `body` with a wall-clock timeout hint.
  ##
  ## This template records the start time and provides `elapsedMs`
  ## and `deadlineExceeded` helpers inside `body`. Actual timeout
  ## enforcement (killing the subprocess) is done by the caller
  ## using these helpers in its polling loop.
  ##
  ## Usage:
  ##   withTimeout(600_000):  # 10 minutes
  ##     while not gateProcess.finished:
  ##       let events = gateSelector.select(100)
  ##       # ... drain stdout ...
  ##       if deadlineExceeded:
  ##         killManaged(gateProcess)
  ##         break
  block:
    let timeoutStart {.inject.} = epochTime()
    let timeoutSec {.inject.} = timeoutMs.float / 1000.0

    proc deadlineExceeded(): bool {.inline, raises: [].} =
      ## Returns true if wall-clock time has exceeded the timeout.
      epochTime() - timeoutStart > timeoutSec

    proc elapsedMs(): float {.inline, raises: [].} =
      ## Returns milliseconds elapsed since timeoutStart.
      (epochTime() - timeoutStart) * 1000.0

    body

{.pop.}
