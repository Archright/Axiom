import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Contract SMT-LIB2 Emitter — Pure domain function for SMT-LIB2 emission.
## Extracted from former contract_extractor.nim to eliminate Domain->Infrastructure
## import violation (verification/ast_extractor).

import std/strutils
import std/sets
import std/tables
import core/types/results
import core/contract/contract_types as ct
import core/contract/contract_param_util as cparam
import core/encoding/smtlib2_util as su
import core/encoding/smtlib2_sanitizer
import ../../core/trusted/axiom_pragmas

## SMT-LIB2 emission with Type Purity Filter.
func contractToSmtlib2*(contract: ct.ExtractedContract; params: seq[(string, string)] = @[]): Result[string, string] {.raises: [], axiom: ["(assert (and (>= (seq.len contract.preconditions) 0) (>= (seq.len params) 0)))", "contract.preconditions.size ≥ 0 ∧ params.size ≥ 0"].} =
  var sb = ""
  var paramSet = initHashSet[string]()
  for (name, _) in params:
    paramSet.incl(name)
  var allIds = initHashSet[string]()
  let allPre = contract.preconditions.join(" ")
  for id in su.extractSmtIdentifiers(allPre):
    allIds.incl(id)
  for (name, typ) in params:
    if name in allIds:
      let smtType = if typ in ["string", "str"]: "String"
                      elif typ in ["int", "int64", "int32"]: "Int"
                      elif typ in ["nat", "uint", "uint64"]: "Nat"
                      elif typ in ["bool"]: "Bool"
                      elif typ in ["char"]: "Char"
                      elif typ in ["float", "float64", "float32"]: "Real"
                      else: "Int"
      sb.add("(declare-const " & name & " " & smtType & ")\n")
  for id in allIds:
    if id notin paramSet:
      let inferred = cparam.inferTypeFromSmtUsage(id, allPre)
      sb.add("(declare-const " & id & " " & inferred & ")\n")
  var declTypes = initTable[string, string]()
  for (name, typ) in params:
    let smtType = if typ in ["string", "str"]: "String"
                    elif typ in ["int", "int64", "int32"]: "Int"
                    elif typ in ["nat", "uint", "uint64"]: "Nat"
                    elif typ in ["bool"]: "Bool"
                    elif typ in ["char"]: "Char"
                    elif typ in ["float", "float64", "float32"]: "Real"
                    else: "Int"
    declTypes[name] = smtType
  for id in allIds:
    if id notin paramSet:
      let inferred = cparam.inferTypeFromSmtUsage(id, allPre)
      declTypes[id] = inferred
  for pre in contract.preconditions:
    let res = sanitizeSmtAssert(pre, declTypes)
    if res.isErr: return err(res.error)
    sb.add(res.get & "\n")
  for post in contract.postconditions:
    let res = sanitizeSmtAssert(post, declTypes)
    if res.isErr: return err(res.error)
    sb.add(res.get & "\n")
  return ok(sb)

{.pop.}
