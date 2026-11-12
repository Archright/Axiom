import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
when defined(axiomEffectGuard) or defined(axiomEffectGuardStrict):
  import std/macros
  import core/trusted/effect_inference_engine

macro enforceEffectContract*(body: untyped): untyped =
  ## When compiled with -d:axiomEffectGuard:
  ## - Scans proc/func definitions in `body` for I/O calls
  ## - If a proc has I/O calls but no {.axiomEffect: IOEffect.} pragma,
  ##   emits a warning (or error with -d:axiomEffectGuardStrict)
  ## Without -d:axiomEffectGuard: passthrough (backward compatible)
  when defined(axiomEffectGuard) or defined(axiomEffectGuardStrict):
    result = newStmtList()
    let targetFile = $body.lineInfoObj.filename
    for child in body:
      if child.kind in {nnkProcDef, nnkFuncDef, nnkMethodDef}:
        var detectedIO: seq[string] = @[]
        collectIoCalls(child[6], targetFile, detectedIO)
        if detectedIO.len > 0:
          let hasPragma = hasAxiomEffectPragma(child[4])
          if not hasPragma:
            let procName = $child[0]
            let msg = "EFFECT GUARD: proc '" & procName &
                      "' has " & $detectedIO.len &
                      " I/O call(s) but missing {.axiomEffect: IOEffect.}. " &
                      "Compile with -d:axiomEffectGuardStrict to make this an error."
            when defined(axiomEffectGuardStrict):
              error(msg, child)
            else:
              warning(msg, child)
      result.add(child)
  else:
    result = body
