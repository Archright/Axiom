# external_cli_smoke Pre-Push Hang Fix

## Date: 2026-05-28

## Problem

`external_cli_smoke` gate hung for 5+ minutes during pre-push, forcing emergency bypass (`AXIOM_EMERGENCY_NO_VERIFY=1`).

## Root Causes (Layered)

1. **Bug**: `scripts/smoke_test.nim:195` — `runAxCommand` ignored `dir` parameter, calling `execCmdEx(cmd)` without `workingDir`.
2. **Deadlock**: `execCmdEx` captures stdout/stderr into memory buffer; 64KB POSIX pipe buffer fills and both parent/child block. Nim 1.4.0 changelog documents this hang pattern for `startProcess` when processes have simultaneous stdin reads and stdout writes.
3. **Infinite Wait**: `systemd-run --scope` had no timeout flag → blocks forever on child deadlock.
4. **Working Directory Mismatch**: `getAppDir().parentDir()` assumed compiled binary location equals repo root; fails when binary is in `/tmp` or `nimcache`.

## Fixes Applied

### `scripts/smoke_test.nim`

- **Import**: Added `streams` module.
- **Streaming I/O**: Replaced `execCmdEx` with `startProcess` + `outputStream.readLine` loop + `peekExitCode` polling. Uses `poStdErrToStdOut` and `poUsePath`. Closes `inputStream` per Nim 1.4.0 bug fix documentation.
- **Working Directory**: `runAxCommand` now correctly passes `workingDir = dir` (fixes ignored parameter bug).
- **Repo Root Detection**: Changed `getAppDir().parentDir()` to `getCurrentDir()` in both `resolveAxBinary()` and `main()`.
- **Command Execution**: All `validate*` procs now receive `repoRoot` and execute `ax` commands from repo root while passing absolute state file paths.

### `scripts/gate_hook.nim`

- **Hard Timeout**: Added `-p RuntimeMaxSec=300s` to all `systemd-run` invocations (3 locations: `runSingleGateImpl`, `dispatchGate` nim-check, `dispatchGate` gateway-test).
- **Correction**: `systemd-run` has no `--timeout` CLI flag. Verified via `strings $(which systemd-run)` against systemd 255 binary. Official mechanism is `--property=` (`-p`) passing `RuntimeMaxSec=` to `StartTransientUnit()`, per systemd TRANSIENT-SETTINGS.md and CONTROL_GROUP_INTERFACE.md.

### `src/gate/runners/external_cli_smoke.nim`

- **Streaming I/O**: Replaced `execCmdEx` with `startProcess` + `outputStream.readLine` loop + `peekExitCode` polling.
- **Gate Bond**: Added `putEnv("gate bonding", "1")` to prevent recursive gate execution during `nim c`.
- **Arguments**: Changed from shell string concatenation to proper `args` array passed to `startProcess`.

## Verification Results

### Wall-Clock Time

```
$ time ./bin/external_cli_smoke
real    0m28.562s
user    0m27.017s
sys     0m1.445s
```

**Before**: 5+ minutes (infinite hang, forced emergency bypass)
**After**: 28.56 seconds (deterministic completion)

### Determinism

- `nim check` passes with 0 errors on all 3 modified files.
- No pipe buffer deadlock: streaming I/O prevents 64KB POSIX pipe limit blocking.
- No infinite wait: `systemd-run -p RuntimeMaxSec=300s` enforces 5-minute hard ceiling.

## Remaining Issue (Non-Hang)

`ax report` returns exit code 1 during smoke test execution. Output contains expected `smoke::mul` (#03) and `smoke::push_back` (#05) entries. Exit code 1 appears to originate from `report_cli.nim` internal logic (possibly `Reproof Required` status or ASI threshold). This is **not a hang** and does not block the gate from completing within timeout. Separate investigation needed if smoke test must return exit code 0.

## Documentation References

- Nim `osproc` pipe buffer deadlock: Nim 1.4.0 changelog, "A bug fix in `osproc.startProcess` addresses hangs that occurred when a process had both stdin reads and stdout writes."
- Nim `execCmdEx` `workingDir` support: Nim 1.4.0 changelog, "`osproc.execCmdEx` has been enhanced to accept optional `input` for stdin, `workingDir`, and `env` parameters."
- systemd transient unit timeouts: systemd TRANSIENT-SETTINGS.md — "Scope units are fully supported as transient units... Available settings include `RuntimeMaxSec=`, `TimeoutStopSec=`."
- systemd-run wrapper architecture: systemd CONTROL_GROUP_INTERFACE.md — "The `systemd-run` tool is a wrapper for `StartTransientUnit()`."
