import core/trusted/layer_declaration
axiomLayer "domain"
import core/axiom_pragmas
import std/strutils
{.push raises: [].}
## Discriminated result for VerificationModel → CHC compilation.
##
## Replaces the silent `""` / `none(string)` contract (which conflated
## `Unsupported`, `NotApplicable`, `InvalidModel`, `InternalError` and could
## hide a vacuous query behind an unobservable legacy fallback).
##
## Contract: C12 (Unsupported ≠ Unknown · NotApplicable separate), C13.

type
  ChcBuildKind* = enum
    cbSuccess
    cbNotApplicable
    cbUnsupported
    cbInvalidModel
    cbObligationMismatch
    cbInternalError

  ChcNotApplicableReason* = enum
    cnaNoObligations  ## Vacuous — a query with no `error` rule proves nothing (§0.9). Not a capability issue.
    cnaNoProperty     ## Function carries no property to check on a well-formed model.

  ChcUnsupportedReason* = enum
    cusNotLoop           ## Expression is not a valid / supported loop form.
    cusComplexControl    ## Control flow (break/continue/return/nested) not representable by this compiler today.
    cusNonForLoop        ## lkWhile or other loop shapes declined by the conservative CHC scope.

  ChcInvalidModelReason* = enum
    cimDegenerateStateArity  ## states.len == 0 or init/state arity mismatch.
    cimNilStateType          ## A StateVar carries a nil irType — untyped IR, fail closed.

  ## DEBT#416: CHC routing fix applied — loopSimpleFor unary relaxation, CHC-First routing, BMC fallback split.
  ## DEBT#421: rkNoObligation coerce path — legacy skipReason 'no_obligation' mapping bypasses canonical obligation IR.
  ChcBuildResult* = object
    ## Discriminated VM→CHC build result (C13). See chcBuildResultPragma note.
    case kind*: ChcBuildKind
    of cbSuccess:
      program*: string                     ## The SMT-LIB2 HORN script.
    of cbNotApplicable:
      notApplicableReason*: ChcNotApplicableReason
    of cbUnsupported:
      unsupportedReason*: ChcUnsupportedReason
    of cbInvalidModel:
      diagnostics*: seq[string]
    of cbObligationMismatch:
      ## Count mismatch between input obligations and output properties.
    of cbInternalError:
      errorDiagnostics*: seq[string]

func chcBuildSuccess*(program: string): ChcBuildResult {.raises: [], axiomDebt: "DEBT#416".} =
  ChcBuildResult(kind: cbSuccess, program: program)

func chcBuildNotApplicable*(reason: ChcNotApplicableReason): ChcBuildResult {.raises: [], axiomDebt: "DEBT#421".} =
  ChcBuildResult(kind: cbNotApplicable, notApplicableReason: reason)

func chcBuildUnsupported*(reason: ChcUnsupportedReason): ChcBuildResult {.raises: [].} =
  ChcBuildResult(kind: cbUnsupported, unsupportedReason: reason)

func chcBuildInvalidModel*(diag: openArray[string]): ChcBuildResult {.raises: [].} =
  ChcBuildResult(kind: cbInvalidModel, diagnostics: @diag)

func chcBuildObligationMismatch*(): ChcBuildResult {.raises: [].} =
  ChcBuildResult(kind: cbObligationMismatch)

func chcBuildInternalError*(diag: string): ChcBuildResult {.raises: [].} =
  ChcBuildResult(kind: cbInternalError, errorDiagnostics: @[diag])

func chcBuildMessage*(r: ChcBuildResult): string {.raises: [].} =
  ## Human-readable description of a non-success result ("" for success).
  case r.kind
  of cbSuccess: ""
  of cbNotApplicable: "not-applicable:" & $r.notApplicableReason
  of cbUnsupported: "unsupported:" & $r.unsupportedReason
  of cbInvalidModel: "invalid-model:" & r.diagnostics.join(";")
  of cbObligationMismatch: "obligation-mismatch: input obligation count does not match output property count"
  of cbInternalError: "internal-error:" & r.errorDiagnostics.join(";")

{.pop.}