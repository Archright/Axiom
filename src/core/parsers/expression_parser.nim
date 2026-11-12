import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import ../../core/trusted/axiom_pragmas
import core/bmc/bmc_race
import core/gateway/gateway
import core/types/results
import std/strutils
func compactExpression(raw: string): string {.raises: [], axiom: ["(assert (and (>= result 0) (>= raw 0)))", "(result ≥ 0) ∧ (raw ≥ 0)"].} =
  result = newStringOfCap(raw.len)
  for ch in raw:
    if not ch.isSpaceAscii:
      result.add(ch)
func parseDelta(compact: string; startIdx: int): Result[int, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len compact) 0) (and (>= startIdx -9223372036854775808) (<= startIdx 9223372036854775807)) (= idx startIdx) (< idx (str.len compact)) (and (>= idx 0) (< idx compact)) (>= delta 0)))", "compact.length ≥ 0 ∧ startIdx ≥ -9223372036854775808 ∧ startIdx ≤ 9223372036854775807 ∧ idx = startIdx ∧ idx < compact.length ∧ ((idx ≥ 0) ∧ (idx < compact)) ∧ (delta ≥ 0)"].} =
  if startIdx >= compact.len:
    return err(axiomErrInvalidValue)
  var idx = startIdx
  var delta = 0
  while idx < compact.len:
    let ch = compact[idx]
    if ch < '0' or ch > '9':
      return err(axiomErrInvalidValue)
    delta = delta * 10 + (ord(ch) - ord('0'))
    inc idx
  if idx == startIdx:
    return err(axiomErrInvalidValue)
  ok(delta)
func parseSignedInt(compact: string; startIdx: int): Result[int, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len compact) 0) (and (>= startIdx -9223372036854775808) (<= startIdx 9223372036854775807)) (< idx (str.len compact)) (= sign -1) (and (>= idx 0) (< idx compact)) (>= sign 0) (>= value 0)))", "compact.length ≥ 0 ∧ startIdx ≥ -9223372036854775808 ∧ startIdx ≤ 9223372036854775807 ∧ idx < compact.length ∧ sign = -1 ∧ ((idx ≥ 0) ∧ (idx < compact)) ∧ (sign ≥ 0) ∧ (value ≥ 0)"].} =
  if startIdx >= compact.len:
    return err(axiomErrInvalidValue)
  var idx = startIdx
  var sign = 1
  if compact[idx] == '-':
    sign = -1
    inc idx
  if idx >= compact.len:
    return err(axiomErrInvalidValue)
  var value = 0
  while idx < compact.len:
    let ch = compact[idx]
    if ch < '0' or ch > '9':
      return err(axiomErrInvalidValue)
    value = value * 10 + (ord(ch) - ord('0'))
    inc idx
  ok(sign * value)
func normalizeNaturalConstraint(raw: string): string {.raises: [], axiom: ["(assert (and (>= result 0) (>= raw 0)))", "(result ≥ 0) ∧ (raw ≥ 0)"].} =
  result = newStringOfCap(raw.len)
  for ch in raw:
    if not ch.isSpaceAscii and ch != '"' and ch != '\'':
      result.add(ch.toLowerAscii())
func extractValueAfterPrefix(compact: string; prefix: string): Result[int, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len compact) 0) (>= (str.len prefix) 0) (>= prefixEnd (str.len compact)) (>= (str.len compact) 0) (>= (str.len prefix) 0)))", "compact.length ≥ 0 ∧ prefix.length ≥ 0 ∧ prefixEnd ≥ compact.length ∧ compact.length ≥ 0 ∧ prefix.length ≥ 0"].} =
  if compact.find(prefix) < 0:
    return err(axiomErrInvalidValue)
  let prefixEnd = compact.find(prefix) + prefix.len
  if prefixEnd >= compact.len:
    return err(axiomErrInvalidValue)
  parseSignedInt(compact, prefixEnd)

## Parse User Code To Rule.
func parseUserCodeToRule*(code: string): Result[TransitionRule, AxiomError] {.raises: [], axiom: ["(assert (and (= (str.len code) 0) (= (str.len compact) 0)))", "code.length = 0 ∧ compact.length = 0"].} =
  if code.len == 0:
    return err(axiomErrEmptyString)
  let compact = compactExpression(code)
  if compact.len == 0:
    return err(axiomErrEmptyString)

  if compact.startsWith("x=x-"):
    let delta = ??parseDelta(compact, 4)
    return ok(makeSubtractRule(delta))

  if compact.startsWith("x=x+"):
    let delta = ??parseDelta(compact, 4)
    return ok(makeAddRule(delta))

  if compact.startsWith("x-="):
    let delta = ??parseDelta(compact, 3)
    return ok(makeSubtractRule(delta))

  if compact.startsWith("x+="):
    let delta = ??parseDelta(compact, 3)
    return ok(makeAddRule(delta))

  err(axiomErrInvalidValue)

## Parse Natural Constraint To Invariant.
func parseNaturalConstraintToInvariant*(raw: string): Result[InvariantRule, AxiomError] {.raises: [], axiom: ["(assert (and (= (str.len raw) 0) (= (str.len compact) 0)))", "raw.length = 0 ∧ compact.length = 0"].} =
  if raw.len == 0:
    return err(axiomErrEmptyString)
  let compact = normalizeNaturalConstraint(raw)
  if compact.len == 0:
    return err(axiomErrEmptyString)

  if compact.startsWith("x>="):
    let value = ??parseSignedInt(compact, 3)
    return ok(makeMinValueInvariant(value))

  if compact.startsWith("balance>="):
    let value = ??parseSignedInt(compact, 9)
    return ok(makeMinValueInvariant(value))

  if compact.startsWith("x<="):
    let value = ??parseSignedInt(compact, 3)
    return ok(makeMaxValueInvariant(value))

  if compact.startsWith("balance<="):
    let value = ??parseSignedInt(compact, 9)
    return ok(makeMaxValueInvariant(value))

  if compact.find("always") >= 0 and compact.find("at_least") >= 0:
    let value = ??extractValueAfterPrefix(compact, "at_least")
    return ok(makeMinValueInvariant(value))

  if compact.find("always") >= 0 and compact.find("at_most") >= 0:
    let value = ??extractValueAfterPrefix(compact, "at_most")
    return ok(makeMaxValueInvariant(value))

  err(axiomErrInvalidValue)

## Parse User Code And Invariant To Rule.
func parseUserCodeAndInvariantToRule*(code: string; invariantText: string): Result[TransitionRule, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len code) 0) (>= (str.len invariantText) 0) (>= merged 0)))", "code.length ≥ 0 ∧ invariantText.length ≥ 0 ∧ (merged ≥ 0)"].} =
  let ruleRes = ??parseUserCodeToRule(code)
  let invRes = ??parseNaturalConstraintToInvariant(invariantText)
  var merged = ruleRes
  merged.invariant = invRes
  ok(merged)
{.pop.}
