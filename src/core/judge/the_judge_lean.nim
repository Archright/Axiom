import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import core/utils/constants
import core/judge/smart_search
import core/trusted/smt_sort
import core/types/hubs/judge_hub
import std/strutils
export judge_hub

## Build Smt2Query.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="conditions.length > 0 ∧ conditions.length = 1" smt="(assert (and (> (str.len conditions) 0) (= (str.len conditions) 1)))"
func buildSmt2Query*(hint: SemanticHint): string {.noSideEffect.} =
  var conditions: seq[string] = @[]
  var namedAsserts: seq[string] = @[]
  var assertIdx = 0
  for line in hint.smtConstraint.splitLines():
    let s = line.strip()
    if s.startsWith("(assert ") and s.endsWith(")"):
      let body = s[8 .. ^2]
      conditions.add(body)
      namedAsserts.add("(assert (! " & body & " :named h" & $assertIdx & "))")
      inc assertIdx
    else:
      namedAsserts.add(s)

  let negatedAssert =
    if conditions.len > 0:
      let conj = smtAndRaw(conditions)
      "(assert (not " & conj & "))\n"
    else:
      ""

  "(set-logic QF_LIA)\n" &
  "(declare-const expected Int)\n" &
  "(declare-const typ Int)\n" &
  namedAsserts.join("\n") & "\n" &
  negatedAssert &
  "(check-sat)\n" &
  "(get-unsat-core)\n"
export judge_hub
type
  LeanVariableUsage* = object
    name*: string
    fields*: seq[string]
    elementFields*: seq[string]
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func isLeanIdentStart*(c: char): bool {.raises: [].} =
  c.isAlphaAscii() or c == '_'

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func isLeanIdentPart(c: char): bool {.raises: [].} =
  c.isAlphaAscii() or c.isDigit() or c == '_'

# @axiom-hint: lean="prop.length ≥ 0 ∧ start ≥ -9223372036854775808 ∧ start ≤ 9223372036854775807 ∧ ident.length ≥ 0 ∧ nextPos ≥ -9223372036854775808 ∧ nextPos ≤ 9223372036854775807" smt="(assert (and (>= (str.len prop) 0) (and (>= start -9223372036854775808) (<= start 9223372036854775807)) (>= (str.len ident) 0) (and (>= nextPos -9223372036854775808) (<= nextPos 9223372036854775807))))"
# @axiom-hint: lean="nextPos = i ∧ false ∧ (ident ≥ 0) ∧ (nextPos ≥ 0)" smt="(assert (and (= nextPos i) false (>= ident 0) (>= nextPos 0)))"
func readLeanIdent*(prop: string; start: int; ident: var string; nextPos: var int): bool {.raises: [].} =
  if start >= prop.len or not isLeanIdentStart(prop[start]):
    return false
  var i = start
  ident = ""
  while i < prop.len and isLeanIdentPart(prop[i]):
    ident.add(prop[i])
    inc i
  nextPos = i
  ident.len > 0

# @axiom-hint: lean="prop.length ≥ 0 ∧ pos ≥ -9223372036854775808 ∧ pos ≤ 9223372036854775807" smt="(assert (and (>= (str.len prop) 0) (and (>= pos -9223372036854775808) (<= pos 9223372036854775807))))"
func skipLeanSpaces(prop: string; pos: var int) {.raises: [].} =
  while pos < prop.len and prop[pos] in {' ', '\t', '\r', '\n'}:
    inc pos

# @axiom-hint: lean="prop.length ≥ 0 ∧ pos ≥ -9223372036854775808 ∧ pos ≤ 9223372036854775807" smt="(assert (and (>= (str.len prop) 0) (and (>= pos -9223372036854775808) (<= pos 9223372036854775807))))"
# @axiom-hint: lean="i ≥ 0" smt="(assert (and (>= i 0)))"
func previousNonSpace*(prop: string; pos: int): char {.raises: [].} =
  var i = pos - 1
  while i >= 0:
    if prop[i] notin {' ', '\t', '\r', '\n'}:
      return prop[i]
    dec i
  '\0'

# @axiom-hint: lean="ident.length ≥ 0" smt="(assert (and (>= (str.len ident) 0)))"
func isLeanReservedIdent(ident: string): bool {.raises: [].} =
  let lower = ident.toLowerAscii()
  lower in [
    "and", "or", "not", "true", "false", "expected", "typ", "fun",
    "theorem", "lemma", "axiom", "def", "inductive", "structure",
    "namespace", "end", "macro", "variable", "instance", "where",
    "match", "with", "let", "have", "exact", "prefix", "infix",
    "postfix", "notation", "syntax", "by", "if", "then", "else",
    "universe", "import", "open", "private", "protected", "mutual",
    "opaque", "class", "abbrev", "return", "do", "deriving",
    "calc", "forall", "exists", "try", "catch", "finally",
    "set_option", "section", "example", "elab", "from", "for",
    "in", "inferInstanceAs", "mut", "partial", "pure",
    "init", "field", "prop", "proof"
  ] or ident in [
    "Int", "Nat", "Real", "Bool", "Unit", "List", "Prod", "Subtype",
    "Option", "String", "Char", "Type", "Prop", "Fin", "NimInt",
    "NimNat", "NimString", "NimBool", "NimChar", "NimSeq", "NimArray",
    "NimOption", "NimExcept", "ZMod", "external_io_isolated",
    "ast_parse_failed_isolated", "Nim", "Std", "Bridge", "Array",
    "Eliminates", "Leanstral"
  ]

# @axiom-hint: lean="ident.length ≥ 0" smt="(assert (and (>= (str.len ident) 0)))"
func hasLeanKeywordPrefix*(ident: string): bool {.raises: [].} =
  let lower = ident.toLowerAscii()
  for prefix in ["universe_"]:
    if lower.startsWith(prefix):
      return true
  false

# @axiom-hint: lean="ident.length ≥ 0" smt="(assert (and (>= (str.len ident) 0)))"
func sanitizeLeanIdentifierName*(ident: string): string {.raises: [].} =
  if isLeanReservedIdent(ident) or hasLeanKeywordPrefix(ident):
    return "v_" & ident
  ident

# @axiom-hint: lean="prop.length ≥ 0" smt="(assert (and (>= (str.len prop) 0)))"
# @axiom-hint: lean="i < prop.length ∧ i = nextPos ∧ ((i ≥ 0) ∧ (i < prop))" smt="(assert (and (< i (str.len prop)) (= i nextPos) (and (>= i 0) (< i prop))))"
func collectBoundVariables(prop: string): seq[string] {.raises: [].} =
  var i = 0
  while i < prop.len:
    if i + 2 < prop.len and (prop[i..i+2] == "∀" or prop[i..i+2] == "∃"):
      i += 3
      skipLeanSpaces(prop, i)
      if i < prop.len and prop[i] == '(':
        inc i
        skipLeanSpaces(prop, i)
        var ident = ""
        var nextPos = i
        if readLeanIdent(prop, i, ident, nextPos) and ident notin result:
          result.add(ident)
        i = nextPos
      else:
        while i < prop.len and prop[i] != ',':
          skipLeanSpaces(prop, i)
          var ident = ""
          var nextPos = i
          if readLeanIdent(prop, i, ident, nextPos):
            if ident notin result:
              result.add(ident)
            i = nextPos
          else:
            inc i
    else:
      inc i

# @axiom-hint: lean="prop.length ≥ 0 ∧ start ≥ -9223372036854775808 ∧ start ≤ 9223372036854775807" smt="(assert (and (>= (str.len prop) 0) (and (>= start -9223372036854775808) (<= start 9223372036854775807))))"
# @axiom-hint: lean="i < limit ∧ i = nextPos ∧ ((i ≥ 0) ∧ (i < limit))" smt="(assert (and (< i limit) (= i nextPos) (and (>= i 0) (< i limit))))"
func fieldsAfterGet(prop: string; start: int): seq[string] {.raises: [].} =
  var i = start
  let limit = min(prop.len, start + leanFieldParseWindow)
  while i < limit:
    if prop[i] == ',' or prop[i] == '\n':
      break
    if i + 2 < prop.len and (prop[i..i+2] == "∧" or prop[i..i+2] == "∨"):
      break
    if prop[i] == '.':
      var field = ""
      var nextPos = i + 1
      if readLeanIdent(prop, i + 1, field, nextPos):
        if field notin result:
          result.add(field)
        i = nextPos
        continue
    inc i

# @axiom-hint: lean="usages.size ≥ 0 ∧ usage_name.length ≥ 0 ∧ usage_fields.size ≥ 0 ∧ usage_elementFields.size ≥ 0" smt="(assert (and (>= (seq.len usages) 0) (>= (str.len usage_name) 0) (>= (seq.len usage_fields) 0) (>= (seq.len usage_elementFields) 0)))"
func addVariableUsage(usages: var seq[LeanVariableUsage]; usage: LeanVariableUsage) {.raises: [].} =
  for idx in 0 ..< usages.len:
    if usages[idx].name == usage.name:
      for field in usage.fields:
        if field notin usages[idx].fields:
          usages[idx].fields.add(field)
      for field in usage.elementFields:
        if field notin usages[idx].elementFields:
          usages[idx].elementFields.add(field)
      return
  usages.add(usage)

# @axiom-hint: lean="prop.length ≥ 0" smt="(assert (and (>= (str.len prop) 0)))"
# @axiom-hint: lean="i < prop.length ∧ i = nextPos ∧ j = fieldNext ∧ (j ≥ 0) ∧ ((i ≥ 0) ∧ (i < prop))" smt="(assert (and (< i (str.len prop)) (= i nextPos) (= j fieldNext) (>= j 0) (and (>= i 0) (< i prop))))"
func extractVariableUsages*(prop: string): seq[LeanVariableUsage] {.noSideEffect.} =
  let boundVars = collectBoundVariables(prop)
  var i = 0
  while i < prop.len:
    if isLeanIdentStart(prop[i]):
      let start = i
      var ident = ""
      var nextPos = i
      discard readLeanIdent(prop, i, ident, nextPos)
      i = nextPos
      if previousNonSpace(prop, start) == '.' or ident in boundVars or isLeanReservedIdent(ident):
        continue

      var fields: seq[string] = @[]
      var elementFields: seq[string] = @[]
      var j = nextPos
      while j < prop.len and prop[j] == '.':
        var field = ""
        var fieldNext = j + 1
        if not readLeanIdent(prop, j + 1, field, fieldNext):
          break
        if field notin fields:
          fields.add(field)
        if field == "get" or field == "get_nat":
          for elementField in fieldsAfterGet(prop, fieldNext):
            if elementField notin elementFields:
              elementFields.add(elementField)
        j = fieldNext
      addVariableUsage(result, LeanVariableUsage(
        name: ident,
        fields: fields,
        elementFields: elementFields
      ))
    else:
      inc i
# @axiom-hint: lean="prop.length ≥ 0" smt="(assert (and (>= (str.len prop) 0)))"

{.pop.}
