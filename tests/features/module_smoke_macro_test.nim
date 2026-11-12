## Smoke test for autoGenerateModuleSmokeTest macro.
## Verifies compile-time introspection of env_access.nim's exported symbols.
import std/unittest
import core/trusted/axiom_pragmas
import core/trusted/env_access

# This macro call reads env_access.nim at compile time,
# extracts exported types (EnvVar), procs (envName, getAxiomEnv, etc.),
# and generates check() assertions for each.
autoGenerateModuleSmokeTest("src/core/trusted/env_access.nim")

suite "autoGenerateModuleSmokeTest":
  test "auto-generated boundary assertions pass":
    # The macro already generated check() calls above.
    # This test body is intentionally empty — all assertions are compile-time generated.
    discard
