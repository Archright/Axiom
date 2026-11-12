# NIMTRY TEST FIXTURE — Temporal OCP violation
#
# This is the NEW version (second commit). The BASE version has only
# 2 case branches (below the OCP threshold of 3). This version adds a
# 3rd branch without any registry call, triggering an OCP violation
# when nimtry is run with --base-ref HEAD~1.
#
# Verification:
#   1. Commit base version (2 branches) → no OCP violation
#   2. Commit this version (3 branches) → OCP violation with --base-ref HEAD~1

proc dispatchAction*(action: string): string =
  case action
  of "start": result = "started"
  of "stop": result = "stopped"
  of "pause": result = "paused"
  of "resume": result = "resumed"
  else: result = "unknown"
