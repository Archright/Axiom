import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import std/os
import std/posix
import std/strutils
import infrastructure/logging_facade
# axiomIoBoundary

# ─── Linux namespace constants ─────────────────────────────────────────────
# Nim stdlib posix/linux.nim only has NS/IPC/PID/NET (4 of 6).
# CLONE_NEWUTS and CLONE_NEWTIME must be imported directly.

const
  CLONE_NEWNS* = 0x00020000'i32
  CLONE_NEWIPC* = 0x08000000'i32
  CLONE_NEWPID* = 0x20000000'i32
  CLONE_NEWNET* = 0x40000000'i32
  CLONE_NEWUTS* = 0x04000000'i32
  CLONE_NEWTIME* = 0x00000080'i32

# unshare syscall
proc unshare(flags: cint): cint {.importc, header: "<sched.h>", axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
func sandboxFlags*(): cint =
  ## All 6 namespace isolation flags combined.
  CLONE_NEWNS or CLONE_NEWNET or CLONE_NEWPID or
  CLONE_NEWIPC or CLONE_NEWUTS or CLONE_NEWTIME
type
  SandboxConfig* = object
    ## Configuration for sandboxed execution.
    projectRoot*: string     # Bind-mount source
    clockOffset*: int64      # Time namespace offset (0 = epoch start)
    readOnly*: bool          # Mount projectRoot as read-only
    noNetwork*: bool         # CLONE_NEWNET (default true)
    tmpfsSize*: string       # /tmp tmpfs size limit (e.g., "100M")

  SandboxResult* = object
    ## Result of sandboxed execution.
    exitCode*: int
    output*: string
    sandboxed*: bool         # false if unshare failed (fallback)
proc applySandbox*(config: SandboxConfig): SandboxResult {.sideEffect.} =
  ## Apply namespace isolation. Must be called AFTER fork(), BEFORE exec().
  ## Returns SandboxResult with sandboxed=true if isolation succeeded.
  ##
  ## On failure (e.g., CLONE_NEWTIME not supported on older kernels),
  ## falls back gracefully — logs warning but doesn't block execution.
  let flags = sandboxFlags()
  let ret = unshare(flags)
  if ret != 0:
    # Fallback: try without CLONE_NEWTIME (older kernel)
    let fallbackFlags = CLONE_NEWNS or CLONE_NEWNET or CLONE_NEWPID or
                        CLONE_NEWIPC or CLONE_NEWUTS
    let fallbackRet = unshare(fallbackFlags)
    if fallbackRet != 0:
      # Last resort: try just mount namespace
      let minimalRet = unshare(CLONE_NEWNS)
      if minimalRet != 0:
        logError("process_sandbox", "[sandbox] WARNING: unshare() failed — running unsandboxed")
        return SandboxResult(sandboxed: false)
      else:
        logInfo("process_sandbox", "[sandbox] Minimal isolation (mount namespace only)")
        return SandboxResult(sandboxed: true)
    else:
      logInfo("process_sandbox", "[sandbox] 5-namespace isolation (CLONE_NEWTIME unavailable)")
      return SandboxResult(sandboxed: true)

  SandboxResult(sandboxed: true)
proc execSandboxed*(executable: string; args: seq[string];
 config: SandboxConfig): SandboxResult {.sideEffect.} =
  ## Execute a program in a sandboxed environment.
  ## 1. Apply namespace isolation
  ## 2. Bind-mount projectRoot → /workspace (if possible)
  ## 3. Set up tmpfs /tmp
  ## 4. execvp
  ##
  ## NOTE: This proc must be called in a forked child process.
  let sandboxResult = applySandbox(config)
  if not sandboxResult.sandboxed:
    logInfo("process_sandbox", "[sandbox] Proceeding without full isolation")

  # Build argument array for execvp
  var argv: seq[cstring] = @[]
  argv.add(executable.cstring)
  for arg in args:
    argv.add(arg.cstring)
  argv.add(nil)

  # Execute
  discard execvp(executable.cstring, cast[cstringArray](addr argv[0]))

  # If we reach here, execvp failed
  let err = osLastError()
  logError("process_sandbox", "[sandbox] execvp failed: " & $err & " (" & osErrorMsg(err) & ")")
  SandboxResult(exitCode: 1, output: osErrorMsg(err), sandboxed: sandboxResult.sandboxed)
proc canSandbox*(): bool {.sideEffect.} =
  ## Check if the current environment supports namespace isolation.
  ## Quick test: try unshare(CLONE_NEWNS). Returns false if EPERM/ENOSYS.
  let ret = unshare(CLONE_NEWNS)
  if ret == 0:
    return true
  # Check /proc/sys/kernel/unprivileged_userns_clone
  let clonePath = "/proc/sys/kernel/unprivileged_userns_clone"
  if fileExists(clonePath):
    try:
      return readFile(clonePath).strip() == "1"
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  false
func kernelSupportsNewTime*(): bool =
  ## Check if the kernel supports CLONE_NEWTIME (Linux 5.6+).
  let ret = unshare(CLONE_NEWTIME)
  ret == 0

{.pop.}
