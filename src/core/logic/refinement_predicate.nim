import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import core/integrity/integrity_refinement_types
import core/logic/refinement_string

## Has Negative Top Token.
func hasNegativeTopToken*(tokens: seq[string]): bool {.inline.} =
  var i = 0
  while i < tokens.len - 4:
    if tokens[i] == "stacktop" and tokens[i + 1] == "(" and tokens[i + 2] == "-" and tokens[i + 3] == "1" and tokens[i + 4] == ")":
      return true
    if i + 6 < tokens.len and tokens[i] == "stacktop" and tokens[i + 1] == "<" and tokens[i + 2] == "int" and tokens[i + 3] == ">" and tokens[i + 4] == "(" and tokens[i + 5] == "-" and tokens[i + 6] == "1" and tokens[i + 7] == ")":
      return true
    i += 1

## Has Bound Guard Token.
func hasBoundGuardToken*(tokens: seq[string]): bool {.inline.} =
  for token in tokens:
    if token == "MAX_STACK_SIZE":
      return true
  var i = 0
  while i < tokens.len - 4:
    if tokens[i] == "stack" and tokens[i + 1] == "." and tokens[i + 2] == "size" and tokens[i + 3] == "(" and tokens[i + 4] == ")":
      return true
    i += 1

## Predicate Rule.
func predicateRule*(
  subject: PredicateSubject;
  relation: PredicateRelation;
  intValue: int = 0;
  valueKind: PredicateValueKind = predicateConstValue;
  otherSubject: PredicateSubject = predicateStackSize
): PredicateRule {.inline.} =
  PredicateRule(
    subject: subject,
    relation: relation,
    intValue: intValue,
    valueKind: valueKind,
    otherSubject: otherSubject
  )

## Top Validity Implication Rule.
func topValidityImplicationRule*(): ImplicationRule {.inline.} =
  ImplicationRule(
    id: invariantId(invariantTopValidity) & ".implication.0",
    condition: predicateRule(predicateStackSize, predicateGreaterThan, 0),
    consequence: predicateRule(predicateTopValidity, predicateIsTrue)
  )

## Relational Top Validity Predicate Rule.
func relationalTopValidityPredicateRule*(): NamedPredicateRule {.inline.} =
  NamedPredicateRule(
    id: invariantId(invariantTopValidity) & ".predicate.relational",
    rule: predicateRule(
      predicateStackSize,
      predicateGreaterThan,
      valueKind = predicateSubjectValue,
      otherSubject = predicateIndex
    )
  )

## Concrete Predicate Rule.
func concretePredicateRule*(
  targetTag: InvariantTag;
  subject: PredicateSubject;
  relation: PredicateRelation;
  intValue: int
): NamedPredicateRule {.inline.} =
  NamedPredicateRule(
    id: invariantId(targetTag) & ".predicate." & $ord(subject) & "." & $ord(relation) & "." & $intValue,
    rule: predicateRule(subject, relation, intValue)
  )

## Subject Expr.
func subjectExpr*(subject: PredicateSubject): string {.inline.} =
  case subject
  of predicateStackSize: "size"
  of predicateTopValidity: "valid_top"
  of predicateIndex: "index"
  of predicateObservedValue: "observed"

## Predicate Expr.
func predicateExpr*(rule: PredicateRule): string {.inline.} =
  let lhs = subjectExpr(rule.subject)
  let rhs =
    if rule.valueKind == predicateSubjectValue:
      subjectExpr(rule.otherSubject)
    else:
      $rule.intValue
  case rule.relation
  of predicateGreaterThan: "(> " & lhs & " " & rhs & ")"
  of predicateGreaterEqual: "(>= " & lhs & " " & rhs & ")"
  of predicateLessThan: "(< " & lhs & " " & rhs & ")"
  of predicateLessEqual: "(<= " & lhs & " " & rhs & ")"
  of predicateEqual: "(= " & lhs & " " & rhs & ")"
  of predicateNotEqual: "(not (= " & lhs & " " & rhs & "))"
  of predicateIsTrue: lhs
  of predicateIsFalse: "(not " & lhs & ")"

## Has Top Validity Protection.
func hasTopValidityProtection*(entry: TrackedInvariant): bool {.inline.} =
  entry.dsl.requireValidTop or entry.dsl.implications.len > 0 or entry.dsl.predicates.len > 0

## Is Special Bit Pattern.
func isSpecialBitPattern*(value: int): bool {.inline.} =
  if value == -1: return true
  if value <= 0: return false
  (value and (value - 1)) == 0

{.pop.}

{.pop.}
