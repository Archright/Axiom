import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Regeneration Conformance (G1b) — SEPARATE from Replay (G1a).
##
## Regeneration = current encoder vs stored SMT; this is NOT Replay
## (which re-runs the STORED SMT verbatim). Encoder evolution →
## REGEN_MISMATCH is expected and is not a replay failure.

import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt

type
  RegenStatus* = enum
    rgMatch
    rgMismatch
    rgUnavailable

func regenerateSmt*(funcDef: IRFuncDef): string {.raises: [].} =
  irToSmtScript(funcDef)

func regenConformance*(storedSmt: string; regeneratedSmt: string): RegenStatus {.raises: [].} =
  if storedSmt.len == 0 or regeneratedSmt.len == 0:
    return rgUnavailable
  if storedSmt == regeneratedSmt:
    rgMatch
  else:
    rgMismatch

func regenConformanceFromIR*(storedSmt: string; funcDef: IRFuncDef): RegenStatus {.raises: [].} =
  let regenerated = regenerateSmt(funcDef)
  regenConformance(storedSmt, regenerated)

{.pop.}