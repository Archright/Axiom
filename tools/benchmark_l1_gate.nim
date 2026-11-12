import std/[osproc, times]

proc benchmark(currentHook: bool) =
  let startTime = cpuTime()

  if currentHook:
    discard execCmdEx("nim check src/core/ir/ir_to_lean.nim")
  else:
    discard execCmdEx("bin/pre_commit_gate")

  let endTime = cpuTime()
  echo "Time taken: ", (endTime - startTime) * 1000, " ms"

echo "Current L1 Gate (nim check):"
benchmark(true)
echo "Short-Circuit L1 Gate (Pure AST):"
benchmark(false)
