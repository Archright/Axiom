import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import core/identity/axiom_identity
import core/integrity/integrity_refinement_types
import std/strutils

## Loop Verdict String.
func loopVerdictString*(verdict: LoopVerdict): string {.inline.} =
  case verdict
  of loopProven: "proven"
  of loopBudgetExceeded: "budget_exceeded"
  of loopIterationLimit: "iteration_limit"

## Replay Action String.
func replayActionString*(action: ReplayAction): string {.inline.} =
  case action
  of actionSolve: "solve"
  of actionRefine: "refine"
  of actionMarkSuspicious: "mark_suspicious"
  of actionRevalidate: "revalidate"
  of actionProve: "prove"

## Refinement Operator Kind String.
func refinementOperatorKindString*(kind: RefinementOperatorKind): string {.inline.} =
  case kind
  of opTightenLower: "opTightenLower"
  of opTightenUpper: "opTightenUpper"
  of opAddPredicate: "opAddPredicate"
  of opAddImplication: "opAddImplication"
  of opAddRelational: "opAddRelational"

## Compute Source Fingerprint.
func computeSourceFingerprint*(sourceCode: string): string {.inline.} =
  axiom_identity.computeAxiomFingerprint(sourceCode)

## Opcode Slug.
func opcodeSlug*(label: string): string {.inline.} =
  if label.len == 0: return "global"
  let normalized = label.strip().toLowerAscii()
  for ch in normalized:
    case ch
    of 'a'..'z', '0'..'9': result.add(ch)
    else: result.add('_')

## Trim Case Label.
func trimCaseLabel*(line: string): string {.inline.} =
  var normalized = line.strip()
  if normalized.startsWith("case "): normalized = normalized[5 .. ^1]
  elif normalized.startsWith("default"): normalized = "default"
  if normalized.endsWith(":"): normalized.setLen(normalized.len - 1)
  normalized.strip()

## Invariant Id.
func invariantId*(tag: InvariantTag): string {.inline.} =
  case tag
  of invariantStackDiscipline: "inv.stack_discipline"
  of invariantTopValidity: "inv.top_validity"
  of invariantBoundedGrowth: "inv.bounded_growth"

## Encode Bool.
func encodeBool*(value: bool): string {.inline.} =
  if value: "true" else: "false"

{.pop.}

{.pop.}
