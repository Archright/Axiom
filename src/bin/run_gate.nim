## Package entry shim — nimble-declared surface `bin/run_gate`.
##
## Forwards to the gate runner in `src/cli/run_gate.nim` so the default
## `nimble build` behaves like `make`'s direct compile of that module.
import ../cli/run_gate

when isMainModule:
  main()