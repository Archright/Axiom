## Observer violation fixture — unregistered-runner class (Check 6). This
## runner carries the genuine standalone-gate contract (`when isMainModule`)
## but has NO manifest.d registration: the manifest-consistency gate must
## report "missing manifest entry for runner" → WOULD-BLOCK. Never compiled
## by the repository build; read as text only.

proc runOrphanProbe(): int =
  ## Deliberately unregistered — this file IS the violation.
  0

when isMainModule:
  quit(runOrphanProbe())
