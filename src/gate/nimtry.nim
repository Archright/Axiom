## Forwarding stub for nimtry architecture gate.
## Actual implementation: src/gate/nimtry/nimtry_cli.nim
import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}
import gate/nimtry/nimtry_cli
export nimtry_cli

when isMainModule:
  ## Standalone CLI entry point. When this module is compiled as the
  ## `bin/nimtry` binary, delegate to the real CLI main(). When imported
  ## in-process (e.g. in_process_gates.nim), this block is skipped.
  nimtry_cli.main()
{.pop.}
