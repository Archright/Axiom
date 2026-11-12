## setup_hooks — Configure git to use version-controlled hooks from .githooks/
## Pure Nim port of bin/setup-hooks (bash). Ensures hooks are tracked in the
## repository and cannot drift across environments.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc]
{.push raises: [CatchableError].}

proc main() {.raises: [CatchableError].} =
  if not dirExists(".githooks"):
    echo "[ERROR] .githooks/ directory not found"
    quit(QuitFailure)

  let (output, exitCode) = execCmdEx("git config core.hooksPath .githooks")
  if exitCode != 0:
    echo "[ERROR] Failed to configure git hooks path (exit " & $exitCode & ")"
    quit(QuitFailure)

  echo "[OK] Git hooks path configured to .githooks"

when isMainModule:
  try:
    main()
  except CatchableError as e:
    echo "[ERROR] ", e.msg
    quit(1)
