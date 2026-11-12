import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import std/strutils
## Detect parameter (name, type) pairs from a Nim proc/func signature line.
func detectParams*(signatureLine: string): seq[(string, string)] {.raises: [].} =
  var params = ""
  let parenOpen = signatureLine.find('(')
  let parenClose = signatureLine.find(')')
  if parenOpen >= 0 and parenClose > parenOpen:
    params = signatureLine[parenOpen + 1 ..< parenClose]
  var parts: seq[string] = @[]
  var current = ""
  for ch in params:
    if ch in {',', ';'}:
      if current.len > 0:
        parts.add(current.strip())
        current = ""
    else:
      current.add(ch)
  if current.len > 0:
    parts.add(current.strip())
  for part in parts:
    let colonIdx = part.find(':', 1)
    if colonIdx < 0:
      continue
    let name = part[0 ..< colonIdx].strip()
    let typ = part[colonIdx + 1 .. ^1].strip().split({' ', '\t'})[0].toLowerAscii()
    if name.len > 0 and name[0].isAlphaAscii:
      result.add((name, typ))

## Detect parameter names only (backward compat).
func detectParamNames*(signatureLine: string): seq[string] {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  for p in detectParams(signatureLine):
    result.add(p[0])

## Generate deterministic type-driven invariants from parameter signatures.
## Covers nat/uint (>=0), string/seq/array/openarray (len>=0).
## Returns SMT-LIB2 assertion strings.
func generateTypeDrivenContracts*(params: seq[(string, string)]): seq[string] {.raises: [].} =
  for (name, typ) in params:
    let t = typ.toLowerAscii()
    if t in ["nat", "uint", "uint64", "uint32", "uint16", "uint8"]:
      result.add("(assert (>= " & name & " 0))")
    elif t in ["string", "str"]:
      result.add("(assert (>= (str.len " & name & ") 0))")
    elif t.startsWith("seq") or t.startsWith("array") or t.startsWith("openarray"):
      result.add("(assert (>= (seq.len " & name & ") 0))")

## Infer SMT type from how a variable is used in SMT assertions.
func inferTypeFromSmtUsage*(varName, smt: string): string {.raises: [].} =
  if smt.contains("(str.len " & varName & ")") or smt.contains("str.len " & varName):
    return "String"
  if smt.contains("(seq.len " & varName & ")") or smt.contains("seq.len " & varName):
    return "Seq"
  if smt.contains("(= " & varName & " true)") or smt.contains("(= " & varName & " false)"):
    return "Bool"
  ## Bare assertion like (assert ast_parse_failed_isolated) implies Bool.
  if smt.contains("(assert " & varName & ")"):
    return "Bool"
  ## Non-negative lower bound (>= x 0) implies Nat in Lean.
  if smt.contains("(>= " & varName & " 0)"):
    return "Nat"
  return "Int"

{.pop.}
