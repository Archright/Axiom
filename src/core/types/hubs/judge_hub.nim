import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Canonical judge types — SSOT for verdicts and judge results.

type
  JudgeVerdict* = enum
    verdictApproved
    verdictRejected
    verdictUnverifiable

  JudgeResult* = object
    verdict*: JudgeVerdict
    reason*: string
    smt2*: string
    lean*: string
    z3TimeMs*: int
    leanTimeMs*: int
    hypothesesCount*: int

{.pop.}
