# NIMTRY TEST FIXTURE — intentionally violates SOLID/DIP (Dependency Inversion Principle)
#
# This fixture calls `z3ExecPersistent` and `z3Spawn`, which are concrete
# backend functions owned by `src/core/solver_bridge.nim`. According to the
# policy, these functions are restricted to callers in `src/core/`.
#
# NOTE: With the current production policy (`architecture_policy.lock`),
# the `solid-forbidden-calls` check cannot be verified via `bin/nimtry`
# because the policy's `forbidden_calls` uses function names as keys
# instead of path patterns (e.g., `"src/**" = ["z3ExecPersistent", ...]`).
# The V3 extractor also has `normalizedAstFingerprint: name` (stub),
# so function-call-level detection requires policy path patterns.
#
# To verify, the `architecture_policy.lock` would need:
#   [forbidden_calls]
#   "src/**" = ["z3ExecPersistent", "z3Spawn"]
#
# Then run: bin/nimtry tests/unit/nimtry_fixtures/solid_dip_violation.nim
# Expected: [SOLID] [solid-forbidden-calls] calls concrete backend z3ExecPersistent

import core/solver/solver_bridge

proc runVerification*(target: string): bool =
  ## Illegally calls a concrete backend function instead of using abstraction.
  let handle = z3ExecPersistent("smt2", 5000, 4)
  if handle.isNil:
    result = false
  else:
    result = true

proc spawnSolver*(constraints: seq[string]): int =
  ## Another DIP violation — calls forbidden concrete function.
  let procId = z3Spawn(constraints, 3000)
  result = procId
