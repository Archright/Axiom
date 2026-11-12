import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Abstract Spec Lowering — 3-Tier strategy for converting Nim types to SMT-LIB2.
##
## Tier 1: ADT modeling (Option[T], Result[T,E]) via Z3 declare-datatypes
## Tier 2: Abstract spec (Table, JsonNode) via declare-sort + axioms
## Tier 3: Uninterpreted functions (complex I/O) via declare-fun
##
## Each tier produces SMT-LIB2 strings that can be fed to the Z3 solver.
## The registry module determines which tier applies; this module executes
## the lowering.

import std/strutils
import core/boundary/axiom_registry_loader
import core/types/results

type
  LoweringTier* = enum
    ltTier1  ## ADT: declare-datatypes with constructors
    ltTier2  ## Abstract sort + axioms from registry
    ltTier3  ## Uninterpreted function declarations

  LoweringResult* = object
    tier*: LoweringTier
    typeName*: string
    smtDecls*: seq[string]
    smtAxioms*: seq[string]

# ── Tier 1: ADT Lowering (declare-datatypes) ──

func lowerOptionAdt*(typeName: string; elemType: string): LoweringResult {.raises: [].} =
  ## Lower Option[T] to Z3 declare-datatypes.
  ## Models: (Some value) | None
  let smtDecls = @[
    "(declare-datatypes ((" & typeName & " 0)) (((some-" & typeName & " (" & typeName & "-val " & elemType & ")) (none-" & typeName & "))))",
    "(declare-fun " & typeName & ".isSome (" & typeName & ") Bool)",
    "(declare-fun " & typeName & ".isNone (" & typeName & ") Bool)",
    "(declare-fun " & typeName & ".get (" & typeName & ") " & elemType & ")"
  ]
  let smtAxioms = @[
    "(assert (forall ((v " & typeName & ")) (or (= (" & typeName & ".isSome v) true) (= (" & typeName & ".isNone v) true))))",
    "(assert (forall ((v " & typeName & ")) (= (" & typeName & ".isSome v) (not (" & typeName & ".isNone v)))))",
    "(assert (forall ((v " & typeName & ") (x " & elemType & ")) (=> (= v (some-" & typeName & " x)) (= (" & typeName & ".get v) x))))"
  ]
  LoweringResult(
    tier: ltTier1,
    typeName: typeName,
    smtDecls: smtDecls,
    smtAxioms: smtAxioms
  )

func lowerResultAdt*(typeName: string; valType: string;
                     errType: string): LoweringResult {.raises: [].} =
  ## Lower Result[T,E] to Z3 declare-datatypes.
  ## Models: (Ok value) | Err error
  let smtDecls = @[
    "(declare-datatypes ((" & typeName & " 0)) (((" & typeName & "-ok (" & typeName & "-val " & valType & ")) (" & typeName & "-err (" & typeName & "-err " & errType & ")))))",
    "(declare-fun " & typeName & ".isOk (" & typeName & ") Bool)",
    "(declare-fun " & typeName & ".isErr (" & typeName & ") Bool)",
    "(declare-fun " & typeName & ".get (" & typeName & ") " & valType & ")",
    "(declare-fun " & typeName & ".error (" & typeName & ") " & errType & ")"
  ]
  let smtAxioms = @[
    "(assert (forall ((v " & typeName & ")) (or (= (" & typeName & ".isOk v) true) (= (" & typeName & ".isErr v) true))))",
    "(assert (forall ((v " & typeName & ")) (= (" & typeName & ".isOk v) (not (" & typeName & ".isErr v)))))",
    "(assert (forall ((v " & typeName & ") (x " & valType & ")) (=> (= v (" & typeName & "-ok x)) (= (" & typeName & ".get v) x))))",
    "(assert (forall ((v " & typeName & ") (e " & errType & ")) (=> (= v (" & typeName & "-err e)) (= (" & typeName & ".error v) e))))"
  ]
  LoweringResult(
    tier: ltTier1,
    typeName: typeName,
    smtDecls: smtDecls,
    smtAxioms: smtAxioms
  )

# ── Tier 2: Abstract Sort + Axioms ──

func lowerAbstractSort*(typeName: string; sortDecl: string;
                        axioms: seq[AxiomDef]): LoweringResult {.raises: [].} =
  ## Lower an abstract type via declare-sort + axiom declarations.
  ## Used for Table, JsonNode, and other types with complex internal structure
  ## that cannot be finitely enumerated in Z3.
  var smtDecls: seq[string] = @[]
  var smtAxioms: seq[string] = @[]
  if sortDecl.len > 0:
    smtDecls.add(sortDecl)
  for axiom in axioms:
    if axiom.formula.len > 0:
      smtAxioms.add("(assert (:named " & axiom.name & " " & axiom.formula & "))")
  LoweringResult(
    tier: ltTier2,
    typeName: typeName,
    smtDecls: smtDecls,
    smtAxioms: smtAxioms
  )

# ── Tier 3: Uninterpreted Functions ──

func lowerUninterpreted*(typeName: string; operations: seq[tuple[name: string;
    params: seq[string]; retType: string]]): LoweringResult {.raises: [].} =
  ## Lower a complex I/O type as uninterpreted functions.
  ## Each operation becomes a declare-fun with no axioms — the solver
  ## treats them as opaque.
  var smtDecls: seq[string] = @[]
  for op in operations:
    let paramsStr = op.params.join(" ")
    smtDecls.add("(declare-fun " & typeName & "." & op.name & " (" & paramsStr & ") " & op.retType & ")")
  LoweringResult(
    tier: ltTier3,
    typeName: typeName,
    smtDecls: smtDecls,
    smtAxioms: @[]
  )

# ── Composite SMT-LIB2 Generation ──

func emitSmtLib2*(results: seq[LoweringResult]): string {.raises: [].} =
  ## Emit a complete SMT-LIB2 script from multiple lowering results.
  ## Header + all declarations + all axioms + check-sat.
  var parts: seq[string] = @[]
  parts.add("(set-logic QF_S)")
  parts.add("; === Axiom Registry Declarations ===")
  for lr in results:
    for decl in lr.smtDecls:
      parts.add(decl)
  parts.add("; === Axiom Assertions ===")
  for lr in results:
    for axiom in lr.smtAxioms:
      parts.add(axiom)
  parts.add("(check-sat)")
  parts.join("\n")

# ── Tier Classification ──

func classifyNimType*(nimType: string): LoweringTier {.raises: [].} =
  ## Determine the lowering tier for a given Nim type string.
  let t = nimType.strip().toLowerAscii()
  # Tier 1: ADT types with known constructors
  if t.startsWith("option[") or t == "option":
    return ltTier1
  if t.startsWith("result[") or t == "result":
    return ltTier1
  # Tier 2: Types with registry-defined axioms
  if t == "jsonnode" or t.startsWith("table[") or
     t.startsWith("orderedtable[") or t == "string" or t == "cstring":
    return ltTier2
  # Tier 3: Everything else (complex I/O, unknown objects)
  ltTier3

func lowerType*(nimType: string; registry: AxiomRegistry): Result[LoweringResult, string] {.raises: [].} =
  ## Route a Nim type to the appropriate lowering strategy.
  let tier = classifyNimType(nimType)
  case tier
  of ltTier1:
    let t = nimType.strip().toLowerAscii()
    if t.startsWith("option["):
      let innerStart = t.find('[')
      let innerEnd = t.rfind(']')
      if innerStart >= 0 and innerEnd > innerStart:
        let elemType = nimType[innerStart + 1 ..< innerEnd].strip()
        return ok(lowerOptionAdt(nimType, elemType))
      return ok(lowerOptionAdt(nimType, "Int"))
    elif t.startsWith("result["):
      return ok(lowerResultAdt(nimType, "Int", "String"))
    else:
      return ok(lowerOptionAdt(nimType, "Int"))
  of ltTier2:
    # Look up in registry
    for entry in registry.entries:
      if entry.typeName.toLowerAscii() == nimType.strip().toLowerAscii():
        return ok(lowerAbstractSort(entry.typeName, entry.sortDecl, entry.axioms))
    # Fallback: declare-sort with no axioms
    return ok(lowerAbstractSort(nimType, "(declare-sort " & nimType & " 0)", @[]))
  of ltTier3:
    return ok(lowerUninterpreted(nimType, @[]))

{.pop.}
