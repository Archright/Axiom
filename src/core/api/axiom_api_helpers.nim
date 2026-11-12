import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Axiom API Helpers
## Internal helper functions and semantic payload operations.

import std/options
import std/strutils

import core/gateway/gateway
import core/gateway/gateway_types
import core/json/json_scan_parse
import core/types/domain_utils
import core/types/results
import core/solver/types
import core/solver/type_serialize

import core/contracts/universal_pipeline_contract
import core/api/axiom_api_types
import ../../core/trusted/axiom_pragmas
export axiom_api_types

## Describe Error.
func describeError*(e: AxiomError; target: string = ""): string {.raises: [], axiom: ["(assert (and (= (str.len target) 0) axiomErrExportTargetUnsupported axiomErrNetworkFailure axiomErrFileSystemError axiomErrInconsistentState))", "target.length = 0 ∧ axiomErrExportTargetUnsupported ∧ axiomErrNetworkFailure ∧ axiomErrFileSystemError ∧ axiomErrInconsistentState"].} =
  let base = axiomErrorMessage(e)
  case e
  of axiomErrExportTargetUnsupported, axiomErrNetworkFailure, axiomErrFileSystemError, axiomErrInconsistentState:
    if target.len == 0:
      base
    else:
      base & ": " & target
  else:
    base

func stateDeltaWithinBalance*(stateValue: int; inputDelta: int): bool {.raises: [], axiom: ["(assert (and (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807))))", "stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ inputDelta >= -9223372036854775808 ∧ inputDelta <= 9223372036854775807"].} =
  inputDelta <= stateValue

func toSymbolicFailure*(e: AxiomError; smt2: string = ""): SymbolicFailure {.raises: [], axiom: ["(assert (and ast_parse_failed_isolated (>= (str.len smt2) 0) (= (str.len smt2) 0)))", "ast_parse_failed_isolated ∧ smt2.length >= 0 ∧ smt2.length = 0"].} =
  SymbolicFailure(
    code: e,
    message: axiomErrorMessage(e),
    solverStatus: none(SolverStatus),
    counterExample: none(SolverCounterExample),
    smt2: if smt2.len == 0: none(string) else: some(smt2)
  )

func gatekeepStateInputAsSymbolicFailure*(
  stateValue: int;
  inputDelta: int;
  smt2: string = ""
): Result[(int, int), SymbolicFailure] {.raises: [], axiom: ["(assert (and (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807)) (>= (str.len smt2) 0)))", "stateValue >= -9223372036854775808 ∧ stateValue <= 9223372036854775807 ∧ inputDelta >= -9223372036854775808 ∧ inputDelta <= 9223372036854775807 ∧ smt2.length >= 0"].} =
  let gated = gatekeepStateInput(
    stateValue,
    inputDelta,
    InputConstraintDefinition(
      relationalInvariant: gateway_types.some(stateDeltaWithinBalance)
    )
  )
  if gated.isErr():
    return err(toSymbolicFailure(gated.error, smt2))
  ok(gated.get())

func parseSemanticEnumLabels*(rawLabels: seq[string]): Result[seq[SemanticEnumLabel], AxiomError] {.raises: [], axiom: ["(assert (and (>= (seq.len rawLabels) 0) (forall ((rawLabelsIdx Int)) (=> (and (>= rawLabelsIdx 0) (< rawLabelsIdx (seq.len rawLabels))) (>= (str.len (seq.nth rawLabels rawLabelsIdx)) 0))) (< (str.len rawLabels) 2) duplicate (= duplicate true) (>= rawLabels 0) (>= duplicate 0) (>= labels 0) (forall ((rawLabelsIdx Int)) (=> (and (>= rawLabelsIdx 0) (< rawLabelsIdx (seq.len rawLabels))) (>= (str.len (seq.nth rawLabels rawLabelsIdx)) 0)))))", "rawLabels.size >= 0 ∧ (forall (rawLabelsIdx : Fin rawLabels.size), (rawLabels.get rawLabelsIdx).length >= 0) ∧ rawLabels.length < 2 ∧ duplicate ∧ duplicate = true ∧ (rawLabels >= 0) ∧ (duplicate >= 0) ∧ (labels >= 0) ∧ (forall (rawLabelsIdx : Fin rawLabels.size), (rawLabels.get rawLabelsIdx).length >= 0)"].} =
  if rawLabels.len < 2:
    return err(axiomErrInvalidValue)
  var labels: seq[SemanticEnumLabel] = @[]
  for raw in rawLabels:
    let labelRes = ??toSemanticEnumLabel(raw)
    let label = labelRes
    var duplicate = false
    for existing in labels:
      if semanticEnumLabelString(existing) == raw:
        duplicate = true
        break
    if duplicate:
      return err(axiomErrInvalidValue)
    labels.add(label)
  ok(labels)

## Parse Semantic Equality Payload Json.
func parseSemanticEqualityPayloadJson*(payloadJson: string): Result[SemanticEqualityPayload, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len payloadJson) 0)))", "payloadJson.length >= 0"].} =
  let schemaVersionRawRes = ??parseJsonStringAtPath(payloadJson, ["schemaVersion"])
  let schemaVersionRes = ??toSemanticPayloadSchemaVersion(schemaVersionRawRes)
  let schemaVersion = schemaVersionRes

  let modulePathRawRes = ??parseJsonStringAtPath(payloadJson, ["modulePath"])
  let modulePathRes = ??toSemanticModulePath(modulePathRawRes)
  let modulePath = modulePathRes

  let functionNameRawRes = ??parseJsonStringAtPath(payloadJson, ["functionName"])
  let functionNameRes = ??toSemanticFunctionName(functionNameRawRes)
  let functionName = functionNameRes

  let enumTypeNameRawRes = ??parseJsonStringAtPath(payloadJson, ["enumTypeName"])
  let enumTypeNameRes = ??toSemanticEnumTypeName(enumTypeNameRawRes)
  let enumTypeName = enumTypeNameRes

  let leftSymbolRawRes = ??parseJsonStringAtPath(payloadJson, ["leftSymbol"])
  let leftSymbolRes = ??toSemanticSymbolName(leftSymbolRawRes)
  let leftSymbol = leftSymbolRes

  let rightSymbolRawRes = ??parseJsonStringAtPath(payloadJson, ["rightSymbol"])
  let rightSymbolRes = ??toSemanticSymbolName(rightSymbolRawRes)
  let rightSymbol = rightSymbolRes

  let throwsSymbolRawRes = ??parseJsonStringAtPath(payloadJson, ["throwsSymbol"])
  let throwsSymbolRes = ??toSemanticSymbolName(throwsSymbolRawRes)
  let throwsSymbol = throwsSymbolRes
  if semanticSymbolNameString(leftSymbol) == semanticSymbolNameString(rightSymbol):
    return err(axiomErrInvalidValue)
  if semanticSymbolNameString(throwsSymbol) == semanticSymbolNameString(leftSymbol):
    return err(axiomErrInvalidValue)
  if semanticSymbolNameString(throwsSymbol) == semanticSymbolNameString(rightSymbol):
    return err(axiomErrInvalidValue)
  let rawEnumValuesRes = ??parseJsonStringArrayAtPath(payloadJson, ["enumValues"])
  let enumValuesRes = ??parseSemanticEnumLabels(rawEnumValuesRes)
  let enumValues = enumValuesRes

  let proofGoalRawRes = ??parseJsonStringAtPath(payloadJson, ["proofGoal"])
  let proofGoalRes = ??toSemanticProofGoal(proofGoalRawRes)
  let proofGoal = proofGoalRes
  ok(SemanticEqualityPayload(
    schemaVersion: schemaVersion,
    modulePath: modulePath,
    functionName: functionName,
    enumTypeName: enumTypeName,
    leftSymbol: leftSymbol,
    rightSymbol: rightSymbol,
    throwsSymbol: throwsSymbol,
    enumValues: enumValues,
    proofGoal: proofGoal,
    unsatCore: @[]
  ))

func semanticEnumDatatypeDecl*(payload: SemanticEqualityPayload): string {.raises: [], axiom: ["(assert (and (>= (seq.len payload_enumValues) 0) (>= (seq.len payload_unsatCore) 0)))", "payload_enumValues.size >= 0 ∧ payload_unsatCore.size >= 0"].} =
  var labels: seq[string] = @[]
  for label in payload.enumValues:
    labels.add(semanticEnumLabelString(label))
  "(declare-datatypes () ((" &
    semanticEnumTypeNameString(payload.enumTypeName) &
    " " &
    labels.join(" ") &
    ")))"

## Semantic Rule String.
func semanticRuleString*(payload: SemanticEqualityPayload): string {.raises: [], axiom: ["(assert (and (>= (seq.len payload_enumValues) 0) (>= (seq.len payload_unsatCore) 0)))", "payload_enumValues.size >= 0 ∧ payload_unsatCore.size >= 0"].} =
  semanticSymbolNameString(payload.throwsSymbol) &
    " <=> " &
    semanticSymbolNameString(payload.leftSymbol) &
    " != " &
    semanticSymbolNameString(payload.rightSymbol)

## Build Semantic Equality Payload Smt.
func buildSemanticEqualityPayloadSmt*(payload: SemanticEqualityPayload): Result[string, AxiomError] {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  if payload.enumValues.len < 2:
    return err(axiomErrInvalidValue)
  var lines: seq[string] = @[
    "(set-logic ALL)",
    semanticEnumDatatypeDecl(payload),
    "(declare-const " & semanticSymbolNameString(payload.leftSymbol) & " " & semanticEnumTypeNameString(payload.enumTypeName) & ")",
    "(declare-const " & semanticSymbolNameString(payload.rightSymbol) & " " & semanticEnumTypeNameString(payload.enumTypeName) & ")",
    "(declare-const " & semanticSymbolNameString(payload.throwsSymbol) & " Bool)",
    "(assert (= " & semanticSymbolNameString(payload.throwsSymbol) & " (not (= " & semanticSymbolNameString(payload.leftSymbol) & " " & semanticSymbolNameString(payload.rightSymbol) & "))))"
  ]
  case payload.proofGoal
  of semanticGoalEqualValuesDoNotThrow:
    lines.add("(assert (= " & semanticSymbolNameString(payload.leftSymbol) & " " & semanticSymbolNameString(payload.rightSymbol) & "))")
    lines.add("(assert " & semanticSymbolNameString(payload.throwsSymbol) & ")")
  of semanticGoalMismatchedValuesThrow:
    lines.add("(assert (not (= " & semanticSymbolNameString(payload.leftSymbol) & " " & semanticSymbolNameString(payload.rightSymbol) & ")))")
    lines.add("(assert (not " & semanticSymbolNameString(payload.throwsSymbol) & "))")
  lines.add("(check-sat)")
  lines.add("(get-model)")
  ok(lines.join("\n"))

func semanticPayloadResponse*(
  payload: SemanticEqualityPayload;
  smt2: string;
  status: SolverStatus;
  counterExample: Option[SolverCounterExample]
): SemanticPayloadVerificationResponse {.raises: [], axiom: ["(assert (and (>= (seq.len payload_enumValues) 0) (>= (seq.len payload_unsatCore) 0) (>= (str.len smt2) 0)))", "payload_enumValues.size >= 0 ∧ payload_unsatCore.size >= 0 ∧ smt2.length >= 0"].} =
  var labels: seq[string] = @[]
  for value in payload.enumValues:
    labels.add(semanticEnumLabelString(value))
  SemanticPayloadVerificationResponse(
    status: solverStatusString(status),
    smt2: smt2,
    verified: status == solverUnsat,
    hasCounterExample: counterExample.isSome(),
    counterExampleProperty: if counterExample.isSome(): counterExample.get().violatedProperty else: "",
    counterExampleBindings: if counterExample.isSome(): counterExample.get().bindings else: @[],
    proofGoal: semanticProofGoalString(payload.proofGoal),
    modulePath: semanticModulePathString(payload.modulePath),
    functionName: semanticFunctionNameString(payload.functionName),
    enumTypeName: semanticEnumTypeNameString(payload.enumTypeName),
    semanticRule: semanticRuleString(payload),
    enumValues: labels
  )

## Encode Semantic Equality Payload.
func encodeSemanticEqualityPayload*(payload: SemanticEqualityPayload): Result[SemanticPayloadVerificationResponse, AxiomError] {.raises: [], axiom: ["(assert (and (>= (seq.len payload_enumValues) 0) (>= (seq.len payload_unsatCore) 0)))", "payload_enumValues.size >= 0 ∧ payload_unsatCore.size >= 0"].} =
  let smt2Res = ??buildSemanticEqualityPayloadSmt(payload)
  let smt2 = smt2Res
  var labels: seq[string] = @[]
  for value in payload.enumValues:
    labels.add(semanticEnumLabelString(value))
  ok(SemanticPayloadVerificationResponse(
    status: "encoded",
    smt2: smt2,
    verified: false,
    hasCounterExample: false,
    counterExampleProperty: "",
    counterExampleBindings: @[],
    proofGoal: semanticProofGoalString(payload.proofGoal),
    modulePath: semanticModulePathString(payload.modulePath),
    functionName: semanticFunctionNameString(payload.functionName),
    enumTypeName: semanticEnumTypeNameString(payload.enumTypeName),
    semanticRule: semanticRuleString(payload),
    enumValues: labels
  ))

{.pop.}
