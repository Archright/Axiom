# Z3 Pool Zombie Process Fix

## Problem

`stopZ3WorkerProcess` and `safeKillAndClose` in `z3_pool.nim` called `killManagedProcess()` followed by `close()` without `waitForExit()`. On POSIX, unreap terminated children become zombie processes.

## Fix

Insert `waitForExit(500)` between `kill` and `close` in all process cleanup paths:

- `safeKillAndClose` (z3_pool.nim)
- `stopZ3WorkerProcess` (z3_pool.nim)
- `runProcessWithTimeout` timeout and catch paths (sync_utils_process.nim)

## Pattern

```nim
killManagedProcess(process)
try:
  discard process.waitForExit(500)  # 500ms grace for reaping
except CatchableError:
  discard
process.close()  # Free pipe FDs
```

## Reference patterns
- `lean_daemon.nim:44-49`: kill → waitForExit → close
- `solver_runner.nim:108-110`: kill → waitForExit
- `orchestrator_hook_part2.nim:348-358`: SIGTERM → grace → SIGKILL → close → process group kill
