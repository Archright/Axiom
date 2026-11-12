import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/strutils

type
  VerifierKind* = enum
    z3Target
    leanTarget

  Verifier* = object
    kind*: VerifierKind
    reason*: string

  FuncSignature* = object
    name*: string
    params*: seq[tuple[name: string, typ: string]]
    retType*: string
    usesResult*: bool

func hasRecursion*(body: string; funcName: string): bool {.raises: [].} =
  if funcName.len == 0 or body.len == 0:
    return false
  var pos = 0
  while pos < body.len:
    let idx = body.find(funcName, pos)
    if idx < 0:
      break
    let beforeOk = idx == 0 or not body[idx - 1].isAlphaNumeric()
    let afterIdx = idx + funcName.len
    let afterOk = afterIdx >= body.len or not body[afterIdx].isAlphaNumeric()
    if beforeOk and afterOk:
      return true
    pos = idx + 1
  false

func hasLoop*(body: string): bool {.raises: [].} =
  if body.len == 0:
    return false
  let stripped = body.toLowerAscii()
  if "while " in stripped or "for " in stripped:
    return true
  false

func routeVerification*(body: string; funcName: string): Verifier {.raises: [].} =
  let rec = hasRecursion(body, funcName)
  let loop = hasLoop(body)
  if rec:
    result = Verifier(kind: leanTarget, reason: "recursive: inductive proof required")
  elif loop:
    result = Verifier(kind: z3Target, reason: "looping: bounded model check via Z3")
  else:
    result = Verifier(kind: leanTarget, reason: "pure expression: invariant on Lean kernel")

func nimTypeToLean*(nimType: string): string {.raises: [].} =
  let t = nimType.strip()
  let lower = t.toLowerAscii()

  # --- Generic types (recursive) ---
  if lower.startsWith("seq[") and lower.endsWith("]"):
    let inner = t[4..^2].strip()
    return "Seq " & nimTypeToLean(inner)

  if lower.startsWith("option[") and lower.endsWith("]"):
    let inner = t[7..^2].strip()
    return "Option " & nimTypeToLean(inner)

  if lower.startsWith("array[") and lower.endsWith("]"):
    let inner = t[6..^2].strip()
    let comma = inner.find(',')
    if comma > 0:
      let elemLean = nimTypeToLean(inner[comma + 1..^1].strip())
      return "Array " & elemLean

  if lower.startsWith("result[") and lower.endsWith("]"):
    let inner = t[7..^2].strip()
    let comma = inner.find(',')
    if comma > 0:
      let okType = nimTypeToLean(inner[0..<comma].strip())
      let errType = nimTypeToLean(inner[comma + 1..^1].strip())
      return "Result " & okType & " " & errType
    else:
      return "Result " & nimTypeToLean(inner) & " String"

  if lower.startsWith("set[") and lower.endsWith("]"):
    let inner = t[4..^2].strip()
    return "Set " & nimTypeToLean(inner)

  # --- Primitive types ---
  case lower
  of "int", "int8", "int16", "int32", "int64":
    "Int"
  of "uint", "uint8", "uint16", "uint32", "uint64", "natural":
    "Nat"
  of "string", "cstring":
    "String"
  of "bool":
    "Bool"
  of "char":
    "Char"
  of "float", "float32", "float64":
    "Float"
  of "void":
    "Unit"
  else:
    if lower.startsWith("range["):
      "Int"
    else:
      nimType.strip()

{.pop.}
