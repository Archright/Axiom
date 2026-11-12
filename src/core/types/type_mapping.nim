import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Type Mapping
## Single Source of Truth (SSOT) for Nim → Lean 4 type translation.
## Replaces the dual-path divergence between nimTypeToLeanType (the_judge.nim)
## and translateNimTypeToLean (ast_to_lean_bridge.nim).

import std/strutils
import std/options
import core/types/domain_types
import core/integrity/refinement_types
import core/symbolic/symbolic_types_expr
import core/trusted/axiom_pragmas

# ---------------------------------------------------------------------------
# Core Type Mapping
# ---------------------------------------------------------------------------

## Nim Type To Lean Type.
func nimTypeToLeanType*(nimType: string; useNimPrefix: bool = false): string {.raises: [].} =
  ## Maps Nim type strings to Lean 4 types.
  ## When useNimPrefix=true, emits NimX wrapper types (NimInt, NimString, etc.)
  ## matching the axiom prelude definitions. When false, emits bare Lean types
  ## (Int, String, etc.) for theorem variable declarations.
  let t = nimType.strip()
  let lower = t.toLowerAscii()

  # --- Generic types (recursive) ---
  if t.startsWith("seq[") and t.endsWith("]"):
    let inner = t[4 .. ^2].strip()
    let innerLean = nimTypeToLeanType(inner, useNimPrefix)
    let prefix = if useNimPrefix: "NimSeq" else: "Seq"
    return prefix & " " & innerLean

  if t.startsWith("Option[") and t.endsWith("]"):
    let inner = t[7 .. ^2].strip()
    let innerLean = nimTypeToLeanType(inner, useNimPrefix)
    if useNimPrefix:
      return "NimOption (" & innerLean & ")"
    else:
      return "Option " & innerLean

  if t.startsWith("array[") and t.endsWith("]"):
    let inner = t[6 .. ^2].strip()
    let parts = inner.split(",", maxsplit = 1)
    if parts.len == 2:
      let elemLean = nimTypeToLeanType(parts[1].strip(), useNimPrefix)
      let sizeStr = parts[0].strip()
      if useNimPrefix:
        return "NimArray (" & elemLean & ") " & sizeStr
      else:
        return "Array " & sizeStr & " " & elemLean

  if t.startsWith("Result[") and t.endsWith("]"):
    let inner = t[7 .. ^2].strip()
    let parts = inner.split(",", maxsplit = 1)
    if parts.len == 2:
      let okLean = nimTypeToLeanType(parts[0].strip(), useNimPrefix)
      let errLean = nimTypeToLeanType(parts[1].strip(), useNimPrefix)
      if useNimPrefix:
        # NimExcept ε α  (error first, ok second per prelude)
        return "NimExcept (" & errLean & ") (" & okLean & ")"
      else:
        return "Result " & okLean & " " & errLean

  # --- Primitive types ---
  case lower
  of "int", "int8", "int16", "int32", "int64":
    return if useNimPrefix: "NimInt" else: "Int"
  of "uint", "uint8", "uint16", "uint32", "uint64", "natural":
    return if useNimPrefix: "NimNat" else: "Nat"
  of "string", "cstring":
    return if useNimPrefix: "NimString" else: "String"
  of "bool":
    return if useNimPrefix: "NimBool" else: "Bool"
  of "char":
    return if useNimPrefix: "NimChar" else: "Char"
  of "float", "float32", "float64":
    return if useNimPrefix: "NimFloat" else: "Float"
  of "void":
    return "Unit"
  else:
    if t.startsWith("range["):
      return if useNimPrefix: "NimInt" else: "Int"
    # Unknown / custom type
    if useNimPrefix:
      return "Nim" & t
    else:
      return "α"

# ---------------------------------------------------------------------------
# Refinement-Aware Type Mapping
# ---------------------------------------------------------------------------

## Nim Type To Lean Type With Refinement.
func nimTypeToLeanTypeWithRefinement*(nimType: string; refined: Option[RefinementType]; varName: string; useNimPrefix: bool = false): string {.raises: [], axiom: ["(assert (and (= (option.isSome refined) true) subtype (=> (= (option.isSome refined) true) (= result subtype)) (or (= useNimPrefix true) (= useNimPrefix false))))", "refined.isSome = true ∧ subtype ∧ refined.isSome = true → result = subtype ∧ useNimPrefix = true ∨ useNimPrefix = false"].} =
  ## Returns a Lean type string, preferring the refinement subtype when available.
  ## Falls back to base type mapping when no refinement exists or subtype
  ## generation fails.
  if refined.isSome:
    let rt = refined.get
    if not rt.predicate.isNil and rt.predicate.kind != symbolic_types_expr.seTrue:
      let subtype = refinementTypeToLeanSubtype(rt, varName)
      if subtype.len > 0 and not subtype.contains("// true"):
        # Strip Nim prefix from subtype base if useNimPrefix=false
        if not useNimPrefix:
          # Subtype already uses bare base (Int, Nat, etc.) via refinementTypeToLeanSubtype
          return subtype
        else:
          # For prefixed mode, we keep the base type bare in subtype notation
          # e.g. { x : NimInt // x >= 0 } is invalid Lean syntax.
          # Subtypes in Lean use the underlying type, not the abbreviation.
          return subtype
  # Fallback to base mapping
  result = nimTypeToLeanType(nimType, useNimPrefix)

# ---------------------------------------------------------------------------
# Contextual Bool / Prop Selection
# ---------------------------------------------------------------------------

## Infer Bool Or Prop From Usage.
func inferBoolOrPropFromUsage*(prop: string; varName: string): string {.raises: [].} =
  ## Scans the Lean proposition to decide whether a bool variable should be
  ## typed as Bool or Prop based on usage context.
  ##
  ## Prop context: varName appears only in logical connectives (∧, ∨, ¬, =>)
  ## Bool context: varName appears in = true, = false, or arithmetic contexts
  let safeName = varName.strip()
  if safeName.len == 0:
    return "Bool"

  # Heuristic scan: look for patterns around the variable name
  let lowerProp = prop.toLowerAscii()
  let lowerName = safeName.toLowerAscii()

  # Check for = true / = false patterns (Bool equality context)
  if lowerProp.contains(lowerName & " = true") or lowerProp.contains(lowerName & " = false"):
    return "Bool"
  if lowerProp.contains(lowerName & " ≠ true") or lowerProp.contains(lowerName & " ≠ false"):
    return "Bool"

  # Check for logical-only usage: surrounded by logical connectives
  # Use ASCII-safe string checks for Unicode operators
  let logicalAnd = "\u2227"  # ∧
  let logicalOr = "\u2228"   # ∨
  let logicalNot = "\u00AC"  # ¬
  let logicalImpl {.used.} = "\u21D2" # => (this is actually => in Lean, not Unicode)

  var hasLogicalOp = false
  var hasArithmeticOp = false

  if lowerProp.contains(logicalAnd) or lowerProp.contains(logicalOr) or lowerProp.contains(logicalNot):
    hasLogicalOp = true
  if lowerProp.contains(" => "):
    hasLogicalOp = true

  # Arithmetic / comparison operators indicate Bool (not Prop)
  if lowerProp.contains(" + ") or lowerProp.contains(" - ") or lowerProp.contains(" * ") or lowerProp.contains(" / "):
    hasArithmeticOp = true
  if lowerProp.contains(" < ") or lowerProp.contains(" > "):
    hasArithmeticOp = true

  if hasLogicalOp and not hasArithmeticOp:
    return "Prop"
  # Default: Bool is safer for variables declared as bool in Nim
  "Bool"

{.pop.}

{.pop.}
