import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
## CLI Fuzzer Harness — Hermetic Environment Fuzzing
##
## Macro-based CLI entry point testing in sandboxed environment.
## Uses hermeticSandbox for side-effect isolation.

import std/macros
import core/test_support/sandbox_guard
import core/trusted/env_access

macro deriveCliFuzzer*(cliEntryPoint: untyped; args: static seq[string]): untyped =
  ## Generate a CLI fuzzer test for the given entry point
  ## Runs in hermeticSandbox to isolate filesystem/env side effects
  result = quote do:
    hermeticSandbox([evHome, evAxiomEnv]):
      for testArgs in `args`:
        let exitCode = `cliEntryPoint`(testArgs.split(" "))
        assert exitCode in {0, 1, 2}, "CLI integrity violated: unexpected exit code " & $exitCode

template cliContractTest*(name: string; entry: untyped; args: string; expectedCode: int) =
  ## Declarative CLI contract test
  test name:
    hermeticSandbox([evHome]):
      let exitCode = entry(args.split(" "))
      check exitCode == expectedCode

{.pop.}
