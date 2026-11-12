## Package entry shim — nimble-declared surface `bin/ax`.
##
## `axiom.nimble` declares `bin = @["bin/ax", "bin/run_gate"]`, so the
## default nimble build resolves the entry module at `src/bin/ax.nim` and
## compiles THIS file as the main module. The CLI logic lives in
## `src/cli/main.nim` (presentation layer); this shim imports it and
## delegates main dispatch so the resulting binary behaves exactly like
## `make build`'s `nim c -o:bin/ax src/cli/main.nim`.
import ../cli/main
import std/os

when isMainModule:
  runMain(commandLineParams())