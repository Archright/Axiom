import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## OS-level resource limit utilities for Domain layer.
## Moved from gate/gate_utils to eliminate Domain→Gate layer dependency.
## See: docs/history/2026-05-28-layered-gate-concurrency-cap.md

when defined(posix):
  import std/posix
import core/interfaces/logging_hub
import ../types/results

proc raiseRlimitNoFile*(): Result[bool, string] {.raises: [].} =
  ## Raise the per-process open-file-descriptor limit to 65536.
  ## Returns Ok(true) on success, Err(message) on failure (logs warning to stderr).
  ## Malebolgia spawn creates many threads + pipes; the default ulimit
  ## (1024) exhausts before the thread pool can initialise.
  ## This is the fundamental (OS-level) fix — no hardcoded workarounds.
  ##
  ## v30 capacity check: 65536 FDs supports up to 16,384 concurrent gates
  ## (at 4 FDs/gate = stdin/stdout/stderr/handle).  Dynamic concurrency in
  ## orchestrator_hook caps MaxConcurrentL2 at 16, using ~64 FDs — well
  ## within this limit.
  when defined(posix):
    var rlim: RLimit
    rlim.rlim_cur = 65536
    rlim.rlim_max = 65536
    if setrlimit(RLIMIT_NOFILE, rlim) == 0:
      return ok(true)
    else:
      try:
        logError("[WARN] setrlimit(RLIMIT_NOFILE, 65536) failed — " &
          "startProcess batch may fail with 'Bad file descriptor'")
      except IOError:
        discard
      return err("setrlimit failed")
  else:
    return ok(true)

{.pop.}
