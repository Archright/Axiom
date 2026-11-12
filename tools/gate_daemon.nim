import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

## Gate Daemon Entry Point
##
## Compiled to `bin/gate-daemon`. Started as a background process by the
## orchestrator via `startDaemon()`. Maintains in-memory MemoDb and
## responds to cache queries over Unix domain socket.
##
## Usage:
##   bin/gate-daemon              # Start daemon (default config)
##   bin/gate-daemon --shutdown   # Graceful shutdown via client
##   bin/gate-daemon --status     # Check if daemon is running
##
## Lifecycle:
##   - Orchestrator spawns daemon on first gate run
##   - Daemon auto-shuts down after 5 minutes of inactivity
##   - PID file at .axiom/cache/gate-daemon.pid for lifecycle management

import std/[os, strutils]
import shared_types/gate_bridge

proc main() {.raises: [CatchableError].} =
  let repoRoot = getCurrentDir()
  let config = defaultConfig(repoRoot)

  # Parse CLI arguments
  let params = commandLineParams()

  if "--shutdown" in params:
    if stopDaemon(repoRoot):
      stderr.writeLine("[GATE-DAEMON] Shutdown signal sent")
    else:
      stderr.writeLine("[GATE-DAEMON] Daemon not running")
    quit(0)

  if "--status" in params:
    if isDaemonRunning(repoRoot):
      stderr.writeLine("[GATE-DAEMON] Running")
      quit(0)
    else:
      stderr.writeLine("[GATE-DAEMON] Not running")
      quit(1)

  # Default: run daemon
  runDaemon(config)

main()
