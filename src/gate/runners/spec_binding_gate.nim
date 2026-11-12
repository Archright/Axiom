## Forwarding Stub — spec_binding_gate

import core/trusted/layer_declaration
axiomLayer "gate"
import core/axiom_pragmas
import gate/runners/spec_binding/private/utils
import gate/runners/spec_binding/private/types
import gate/runners/spec_binding/private/source_extract
import gate/runners/spec_binding/private/checks


# axiomIoBoundary

export utils
export types
export source_extract
export checks

proc main() {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let allViolations = runBindingCheck() & runCoherenceCheck()

    if allViolations.len == 0:
      echo "[SPEC-BINDING] PASS"
      quit(0)

    var errorCount = 0
    var warningCount = 0
    for v in allViolations:
      if v.severity == "error":
        errorCount.inc
        echo "[SPEC-BINDING] error: " & v.message
      elif v.severity == "warning":
        warningCount.inc
        echo "[SPEC-BINDING] warning: " & v.message
      else:
        echo "[SPEC-BINDING] warning: " & v.message

    echo "[SPEC-BINDING] Summary: " & $errorCount & " error(s), " & $warningCount & " warning(s)"

    if errorCount > 0:
      quit(1)
    quit(0)
  except CatchableError as e:
    echo "[SPEC-BINDING] error: gate failed with exception: " & e.msg
    quit(1)

when isMainModule:
  main()
