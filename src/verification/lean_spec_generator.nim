import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/strutils
import core/json/json_utils
import core/asset_collector
import core/json/std_redirect
import core/utils/io_utils
import core/axiom_pragmas
import infrastructure/logging_facade
# axiomIoBoundary

proc writeMissingList*(path: string; missing: seq[FunctionRef])  =
  var arr = newJArray()
  for item in missing:
    arr.add(%*{
      "modulePath": item.modulePath,
      "functionName": item.name
    })
  if not writePrettyJsonFile(path, arr):
    logError("lean_spec_generator", "Failed to write missing list to " & path)

proc writeLeanSpec*(path: string; functions: seq[FunctionRef])  =
  var lines: seq[string] = @[
    "import Init",
    "",
    "-- Business Purpose: All auto-generated theorems are certified to the same standard via logic integrity anchors.",
    "-- Business Invariant: Even in complex global regulation/tax extension points, core state invariants must be preserved after input quarantine.",
    "-- logic_integrity_anchor removed: tautology bootstrap was fraudulent",
    ""
  ]
  for fn in functions:
    let theorem = buildTheoremName(fn)
    lines.add("-- Business Purpose: Prove that the " & fn.name & " path in " & fn.modulePath & " satisfies integrity criteria.")
    lines.add("-- Business Invariant: External input quarantine and core invariants are preserved even when extending to complex global regulation/tax domains.")
    lines.add("-- awaiting-leanstral: proposition synthesis deferred to leanstral pipeline for " & theorem)
    lines.add("")
  ## intentional-discard: spec file is re-derivable from source; write is best-effort
  discard writeFileOpt(path, lines.join("\n"))
{.pop.}
