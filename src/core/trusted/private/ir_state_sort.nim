import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/sequtils
import std/strutils
import core/trusted/axiom_ir
import core/logic/smt_logic

type
  ResolvedSort* = object
    sortString*: string    ## e.g. "(_ BitVec 64)", "Bool", "(Array (_ BitVec 64) (_ BitVec 64))"
    logic*: SmtLogic       ## e.g. slQfBv, slQfAufbv
    isInt*: bool           ## True if using Int sort for Spacer compatibility

func resolveSort*(typ: IRType): ResolvedSort {.raises: [].} =
  ## Map an IRType to its SMT sort string and logic.
  case typ.kind
  of irtBitVec64, irtEnum, irtVariant:
    ResolvedSort(sortString: "(_ BitVec 64)", logic: slQfBv, isInt: false)
  of irtBool:
    ResolvedSort(sortString: "Bool", logic: slQfBv, isInt: false)
  of irtList:
    let elemSort = resolveSort(typ.elemType)
    ResolvedSort(sortString: "(Array " & elemSort.sortString & " " & elemSort.sortString & ")",
                 logic: slQfAufbv, isInt: false)
  of irtString:
    ResolvedSort(sortString: "(_ BitVec 64)", logic: slQfBv, isInt: false)

func toIntSort*(bvExpr: string): string {.raises: [].} =
  ## Convert a BV64 expression to Int by wrapping in bv2int.
  ## For non-negative values (kernel for-loop domain), BV64 and Int coincide.
  "(bv2int " & bvExpr & ")"

func toBvSort*(intExpr: string): string {.raises: [].} =
  ## Convert an Int expression back to BV64.
  "(int2bv " & intExpr & ")"

func buildStateRelation*(loopVars: seq[string]; resolvedSorts: seq[ResolvedSort]): string {.raises: [].} =
  ## Build (declare-rel state (sort0 sort1 ... sortn)).
  let sorts = resolvedSorts.mapIt(it.sortString).join(" ")
  "(declare-rel state (" & sorts & "))"

type
  ChcSortKind* = enum
    cskInt       ## Int (for Spacer induction)
    cskBv64      ## (_ BitVec 64)
    cskArrayInt  ## (Array Int Int) for seq[int]

func toChcSortStr*(kind: ChcSortKind): string {.raises: [].} =
  case kind
  of cskInt: "Int"
  of cskBv64: "(_ BitVec 64)"
  of cskArrayInt: "(Array Int Int)"

func mapIrTypeToChcSort*(ty: IRType; useIntSort: bool): ChcSortKind {.raises: [].} =
  case ty.kind
  of irtBitVec64, irtEnum, irtVariant, irtString:
    if useIntSort: cskInt else: cskBv64
  of irtBool:
    cskBv64
  of irtList:
    cskArrayInt

{.pop.}
