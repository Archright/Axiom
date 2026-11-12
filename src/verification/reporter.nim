import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import std/strutils
# axiomIoBoundary
import ../core/trusted/axiom_pragmas

## Parse Declaration Ident.
## axiom-smt: (assert (and (= i 0) (>= result 0)))
## axiom-lean: i = 0 ∧ (result ≥ 0)
func parseDeclarationIdent*(body: string): string {.axiomTryImpl.} =
  var i = 0
  while i < body.len and (isAlphaNumeric(body[i]) or body[i] == '_' or body[i] == '*'):
    inc i
  if i == 0:
    return ""
  result = body[0 ..< i]
  if result.endsWith("*"):
    result.setLen(result.len - 1)

## Parse Proc Binding Name.
## axiom-smt: (assert (and (>= (str.len strippedLine) 0) (<= procBindingIndex 0)))
## axiom-lean: strippedLine.length ≥ 0 ∧ procBindingIndex ≤ 0
func parseProcBindingName*(strippedLine: string): string {.axiomTryImpl.} =
  let procBindingIndex = strippedLine.find(" = proc ")
  if procBindingIndex <= 0:
    return ""
  if strippedLine.startsWith("let ") or strippedLine.startsWith("var "):
    let keywordLen = if strippedLine.startsWith("let "): "let ".len else: "var ".len
    return parseDeclarationIdent(strippedLine[keywordLen ..< procBindingIndex])
  parseDeclarationIdent(strippedLine[0 ..< procBindingIndex].strip())

import core/domain_types
export domain_types

import verification/certificate_manager
export certificate_manager

import verification/translation_validator
export translation_validator

import verification/analyzer
export analyzer
{.pop.}

