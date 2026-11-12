import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/utils/ident_utils
import core/solver/expr_serialize  # canonical coerceToBool, needsBvCoercion
import std/algorithm
import std/sequtils
import std/sets
import std/strutils
import ../trusted/axiom_pragmas_lite
import ../trusted/smt_sort

func isSmtKeywordImpl(token: string): bool {.raises: [].} =
  token in [
    "assert", "and", "or", "not", "ite", "let",
    "Int", "Bool",
    "check-sat", "set-logic", "set-option", "push", "pop",
    "declare-const", "declare-fun", "define-fun",
    "declare-datatype", "declare-datatypes", "declare-sort",
    "true", "false"
  ]
func collectSmtIntSymbolsImpl*(raw: string): seq[string] {.raises: [], axiom: ["(assert (and (< i (str.len raw)) (= i j) (>= result 0) (and (>= i 0) (< i raw))))", "i < raw.length ∧ i = j ∧ (result ≥ 0) ∧ ((i ≥ 0) ∧ (i < raw))"].} =
  var seen = initHashSet[string]()
  var i = 0
  while i < raw.len:
    let ch = raw[i]
    if not isIdentStart(ch):
      inc i
      continue
    var j = i + 1
    while j < raw.len and isIdentPart(raw[j]):
      inc j
    let token = raw[i ..< j]
    if not isSmtKeywordImpl(token):
      seen.incl(token)
    i = j
  result = seen.toSeq()
  result.sort()
func isSmtDeclOrDefLineImpl*(t: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len t) 0)))", "t.length ≥ 0"].} =
  t.startsWith("(declare-") or
    t.startsWith("(define-")
func scanSmtDeclaredSymbolFromLineImpl*(t: string): string {.raises: [], axiom: ["(assert (and (>= (str.len t) 0) (>= start 0)))", "t.length ≥ 0 ∧ (start ≥ 0)"].} =
  var start = 0
  if t.startsWith("(declare-const "):
    start = "(declare-const ".len
  elif t.startsWith("(declare-fun "):
    start = "(declare-fun ".len
  elif t.startsWith("(define-fun "):
    start = "(define-fun ".len
  else:
    return ""
  var i = start
  while i < t.len and t[i].isSpaceAscii():
    inc i
  if i >= t.len:
    return ""
  if not isIdentStart(t[i]):
    return ""
  var j = i + 1
  while j < t.len and isIdentPart(t[j]):
    inc j
  t[i ..< j]
func collectSmtDeclaredSymbolsImpl*(raw: string): HashSet[string] {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (> (str.len sym) 0) (>= result 0)))", "raw.length ≥ 0 ∧ sym.length > 0 ∧ (result ≥ 0)"].} =
  result = initHashSet[string]()
  for line in raw.splitLines():
    let t = line.strip()
    if not isSmtDeclOrDefLineImpl(t):
      continue
    let sym = scanSmtDeclaredSymbolFromLineImpl(t)
    if sym.len > 0:
      result.incl(sym)
func stripSmtDeclarationLinesImpl*(raw: string): string {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (>= result 0)))", "raw.length ≥ 0 ∧ (result ≥ 0)"].} =
  var kept: seq[string] = @[]
  for line in raw.splitLines():
    let t = line.strip()
    if isSmtDeclOrDefLineImpl(t):
      continue
    kept.add(line)
  result = kept.join("\n")
func isSmtControlLineImpl*(t: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0)))", "raw.length ≥ 0"].} =
  t.startsWith("(set-option ") or
    t.startsWith("(set-logic ") or
    t.startsWith("(check-sat") or
    t.startsWith("(get-") or
    t.startsWith("(push") or
    t.startsWith("(pop") or
    t == "(exit)"
func stripSmtProofControlLinesImpl*(raw: string): string {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0)))", "raw.length ≥ 0"].} =
  var kept: seq[string] = @[]
  for line in raw.splitLines():
    let t = line.strip()
    if t.len == 0 or isSmtControlLineImpl(t):
      continue
    kept.add(line)
  kept.join("\n")
func collectSmtAssertBodiesImpl*(raw: string; skipProofNegations: bool = false): seq[string] {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (or (= skipProofNegations true) (= skipProofNegations false))))", "raw.length ≥ 0 ∧ skipProofNegations = true ∨ skipProofNegations = false"].} =
  for line in raw.splitLines():
    let s = line.strip()
    if s.startsWith("(assert ") and s.endsWith(")"):
      let body = s[8 .. ^2].strip()
      if skipProofNegations and body.startsWith("(not "):
        continue
      result.add(body)
func buildSmtConjunctionImpl*(conditions: seq[string]): string {.raises: [], axiom: ["(assert (and (>= (seq.len conditions) 0) (= (str.len conditions) 0) (= (str.len conditions) 1) (forall ((conditionsIdx Int)) (=> (and (>= conditionsIdx 0) (< conditionsIdx (seq.len conditions))) (>= (str.len (seq.nth conditions conditionsIdx)) 0)))))", "conditions.size ≥ 0 ∧ conditions.length = 0 ∧ conditions.length = 1 ∧ (∀ (conditionsIdx : Fin conditions.size), (conditions.get conditionsIdx).length ≥ 0)"].} =
  if conditions.len == 0:
    return ""
  if conditions.len == 1:
    return conditions[0]
  var coerced: seq[string]
  for c in conditions:
    coerced.add(coerceToBool(c))
  smtAndRaw(coerced)
func isSmtSelfEqualityImpl*(body: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len body) 0) false))", "body.length ≥ 0 ∧ false"].} =
  let t = body.strip()
  if not (t.startsWith("(= ") and t.endsWith(")")):
    return false
  let inner = t[3 .. ^2].strip()
  let parts = inner.splitWhitespace()
  parts.len == 2 and parts[0] == parts[1]
func hasVacuousSmtAssertionImpl*(raw: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) true))", "raw.length ≥ 0 ∧ true"].} =
  for body in collectSmtAssertBodiesImpl(raw):
    let t = body.strip()
    if t == "true" or isSmtSelfEqualityImpl(t):
      return true
  false
func isIntegerTokenImpl*(raw: string): bool {.raises: [], axiom: ["(assert (and (= (str.len t) 0) false (=> (= (str.len t) 0) (= result false)) (=> (>= startIdx (str.len t)) (= result false))))", "t.length = 0 ∧ false ∧ t.length = 0 → result = false ∧ startIdx ≥ t.length → result = false"].} =
  let t = raw.strip()
  if t.len == 0:
    return false
  let startIdx = if t[0] == '-': 1 else: 0
  if startIdx >= t.len:
    return false
  for idx in startIdx ..< t.len:
    if not t[idx].isDigit:
      return false
  true
func isSmtOperatorTokenImpl*(raw: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0)))", "raw.length ≥ 0"].} =
  let t = raw.strip().toLowerAscii()
  t in [
    "and", "or", "not", "=>", "=", "<", "<=", ">", ">=", "+", "-", "*",
    "div", "mod", "true", "false", "int", "bool", "str.len", "seq.len"
  ]
func isMetadataOnlySmtSymbolImpl*(raw: string): bool {.raises: [], axiom: ["(assert (and (= (str.len t) 0) false true (=> (= (str.len t) 0) (= result false))))", "t.length = 0 ∧ false ∧ true ∧ t.length = 0 → result = false"].} =
  let t = raw.strip(chars = {'(', ')', '"', '\''}).toLowerAscii()
  if t.len == 0:
    return false
  if t in [
    "depth", "impact", "impactindex", "dependencydepth", "impactednodecount",
    "nodeid", "label", "functionname", "modulepath", "retrycount",
    "premisecount", "dependencycount", "dependentnodecount",
    "transitivedependentcount", "ast_parse_failed_isolated"
  ]:
    return true
  for suffix in [
    "_depth", "_impact", "_impactindex", "_dependencydepth",
    "_impactednodecount", "_retrycount", "_premisecount", "_dependencycount",
    "_dependentnodecount", "_transitivedependentcount",
    "_ast_parse_failed_isolated"
  ]:
    if t.endsWith(suffix):
      return true
  false
func isSmtKeyword*(token: string): bool {.raises: [].} =
  token in [
    "assert", "and", "or", "not", "ite", "let",
    "Int", "Bool",
    "check-sat", "set-logic", "set-option", "push", "pop",
    "declare-const", "declare-fun", "define-fun",
    "declare-datatype", "declare-datatypes", "declare-sort",
    "true", "false"
  ]
func collectSmtIntSymbols*(raw: string): seq[string] {.raises: [], axiom: ["(assert (and (< i (str.len raw)) (= i j) (>= result 0) (and (>= i 0) (< i raw))))", "i < raw.length ∧ i = j ∧ (result ≥ 0) ∧ ((i ≥ 0) ∧ (i < raw))"].} =
  var seen = initHashSet[string]()
  var i = 0
  while i < raw.len:
    let ch = raw[i]
    if not isIdentStart(ch):
      inc i
      continue
    var j = i + 1
    while j < raw.len and isIdentPart(raw[j]):
      inc j
    let token = raw[i ..< j]
    if not isSmtKeyword(token):
      seen.incl(token)
    i = j
  result = seen.toSeq()
  result.sort()
func isSmtDeclOrDefLine*(t: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len t) 0)))", "t.length ≥ 0"].} =
  t.startsWith("(declare-") or
    t.startsWith("(define-")
func scanSmtDeclaredSymbolFromLine*(t: string): string {.raises: [], axiom: ["(assert (and (>= (str.len t) 0) (>= start 0)))", "t.length ≥ 0 ∧ (start ≥ 0)"].} =
  var start = 0
  if t.startsWith("(declare-const "):
    start = "(declare-const ".len
  elif t.startsWith("(declare-fun "):
    start = "(declare-fun ".len
  elif t.startsWith("(define-fun "):
    start = "(define-fun ".len
  else:
    return ""
  var i = start
  while i < t.len and t[i].isSpaceAscii():
    inc i
  if i >= t.len:
    return ""
  if not isIdentStart(t[i]):
    return ""
  var j = i + 1
  while j < t.len and isIdentPart(t[j]):
    inc j
  t[i ..< j]
func collectSmtDeclaredSymbols*(raw: string): HashSet[string] {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (> (str.len sym) 0) (>= result 0)))", "raw.length ≥ 0 ∧ sym.length > 0 ∧ (result ≥ 0)"].} =
  result = initHashSet[string]()
  for line in raw.splitLines():
    let t = line.strip()
    if not isSmtDeclOrDefLine(t):
      continue
    let sym = scanSmtDeclaredSymbolFromLine(t)
    if sym.len > 0:
      result.incl(sym)
func stripSmtDeclarationLines*(raw: string): string {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (>= result 0)))", "raw.length ≥ 0 ∧ (result ≥ 0)"].} =
  var kept: seq[string] = @[]
  for line in raw.splitLines():
    let t = line.strip()
    if isSmtDeclOrDefLine(t):
      continue
    kept.add(line)
  result = kept.join("\n")
func isSmtControlLine*(t: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0)))", "raw.length ≥ 0"].} =
  t.startsWith("(set-option ") or
    t.startsWith("(set-logic ") or
    t.startsWith("(check-sat") or
    t.startsWith("(get-") or
    t.startsWith("(push") or
    t.startsWith("(pop") or
    t == "(exit)"
func stripSmtProofControlLines*(raw: string): string {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0)))", "raw.length ≥ 0"].} =
  var kept: seq[string] = @[]
  for line in raw.splitLines():
    let t = line.strip()
    if t.len == 0 or isSmtControlLine(t):
      continue
    kept.add(line)
  kept.join("\n")
func collectSmtAssertBodies*(raw: string; skipProofNegations: bool = false): seq[string] {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (or (= skipProofNegations true) (= skipProofNegations false))))", "raw.length ≥ 0 ∧ skipProofNegations = true ∨ skipProofNegations = false"].} =
  for line in raw.splitLines():
    let s = line.strip()
    if s.startsWith("(assert ") and s.endsWith(")"):
      let body = s[8 .. ^2].strip()
      if skipProofNegations and body.startsWith("(not "):
        continue
      result.add(body)
func buildSmtConjunction*(conditions: seq[string]): string {.raises: [], axiom: ["(assert (and (>= (seq.len conditions) 0) (= (str.len conditions) 0) (= (str.len conditions) 1) (forall ((conditionsIdx Int)) (=> (and (>= conditionsIdx 0) (< conditionsIdx (seq.len conditions))) (>= (str.len (seq.nth conditions conditionsIdx)) 0)))))", "conditions.size ≥ 0 ∧ conditions.length = 0 ∧ conditions.length = 1 ∧ (∀ (conditionsIdx : Fin conditions.size), (conditions.get conditionsIdx).length ≥ 0)"].} =
  if conditions.len == 0:
    return ""
  if conditions.len == 1:
    return conditions[0]
  var coerced: seq[string]
  for c in conditions:
    coerced.add(coerceToBool(c))
  smtAndRaw(coerced)
func isSmtSelfEquality*(body: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len body) 0) false))", "body.length ≥ 0 ∧ false"].} =
  let t = body.strip()
  if not (t.startsWith("(= ") and t.endsWith(")")):
    return false
  let inner = t[3 .. ^2].strip()
  let parts = inner.splitWhitespace()
  parts.len == 2 and parts[0] == parts[1]
func hasVacuousSmtAssertion*(raw: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) true))", "raw.length ≥ 0 ∧ true"].} =
  for body in collectSmtAssertBodies(raw):
    let t = body.strip()
    if t == "true" or isSmtSelfEquality(t):
      return true
  false
func isIntegerToken*(raw: string): bool {.raises: [], axiom: ["(assert (and (= (str.len t) 0) false (=> (= (str.len t) 0) (= result false)) (=> (>= startIdx (str.len t)) (= result false))))", "t.length = 0 ∧ false ∧ t.length = 0 → result = false ∧ startIdx ≥ t.length → result = false"].} =
  let t = raw.strip()
  if t.len == 0:
    return false
  let startIdx = if t[0] == '-': 1 else: 0
  if startIdx >= t.len:
    return false
  for idx in startIdx ..< t.len:
    if not t[idx].isDigit:
      return false
  true
func isSmtOperatorToken*(raw: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0)))", "raw.length ≥ 0"].} =
  let t = raw.strip().toLowerAscii()
  t in [
    "and", "or", "not", "=>", "=", "<", "<=", ">", ">=", "+", "-", "*",
    "div", "mod", "true", "false", "int", "bool", "str.len", "seq.len"
  ]
func isMetadataOnlySmtSymbol*(raw: string): bool {.raises: [], axiom: ["(assert (and (= (str.len t) 0) false true (=> (= (str.len t) 0) (= result false))))", "t.length = 0 ∧ false ∧ true ∧ t.length = 0 → result = false"].} =
  let t = raw.strip(chars = {'(', ')', '"', '\''}).toLowerAscii()
  if t.len == 0:
    return false
  if t in [
    "depth", "impact", "impactindex", "dependencydepth", "impactednodecount",
    "nodeid", "label", "functionname", "modulepath", "retrycount",
    "premisecount", "dependencycount", "dependentnodecount",
    "transitivedependentcount", "ast_parse_failed_isolated"
  ]:
    return true
  for suffix in [
    "_depth", "_impact", "_impactindex", "_dependencydepth",
    "_impactednodecount", "_retrycount", "_premisecount", "_dependencycount",
    "_dependentnodecount", "_transitivedependentcount",
    "_ast_parse_failed_isolated"
  ]:
    if t.endsWith(suffix):
      return true
  false

{.pop.}
