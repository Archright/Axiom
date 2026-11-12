## debug_mode_state.nim — Debug Mode State Query (Gate Helper)
##
## Minimal helper module that gates import to check whether debug mode
## is active. Debug mode causes all gates to exit 0 with detailed
## diagnostics on stderr instead of hard-failing.
##
## SSOT for debug mode state: `.axiom/debug_mode_on` marker file.

import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import std/os
import infrastructure/logger
import core/trusted/axiom_pragmas
# axiomIoBoundary — read-only probe, no side effects at module level

const
  MARKER_NAME* = ".axiom/debug_mode_on"  ## Marker file relative to repo root

func debugMarkerPath*(repoRoot: string): string =
  ## Absolute path to the debug mode marker file.
  result = repoRoot / MARKER_NAME

proc isDebugModeActive*(repoRoot: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns true when `.axiom/debug_mode_on` exists in the repo root.
  ## Gates SHOULD call this at entry and downgrade hard-fails to warnings.
  result = fileExists(repoRoot / MARKER_NAME)

{.pop.}

when isMainModule:
  ## Excluded from aggregated nim check to avoid UnusedImport warnings.
  logger.info "debug-mode active: " & $isDebugModeActive(getCurrentDir())
