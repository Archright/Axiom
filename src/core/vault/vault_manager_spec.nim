import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/options
import std/strutils
import std/tables
import core/json/std_redirect

import core/identity/axiom_identity
import core/gateway/gateway
import core/types/results
import core/types/error_types
import core/types/domain_utils
import ../../core/trusted/axiom_pragmas

type
  AxiomInvalidError* = enum
    axiomInvalidFingerprintMismatch

  VaultLoadErrorKind* = enum
    vaultLoadInvalidAxiom,
    vaultLoadStorageFailure

  VaultLoadError* = object
    case kind*: VaultLoadErrorKind
    of vaultLoadInvalidAxiom:
      invalidError*: AxiomInvalidError
    of vaultLoadStorageFailure:
      storageError*: AxiomError

  AxiomSpec* = object
    modulePath*: string
    functionName*: string
    fingerprint*: string
    storedAt*: string
    smtlib2*: string
    winningStrategy*: string
    retryCount*: int
    vacuityProven*: Option[bool]

## Axiom Invalid Error Message.
func axiomInvalidErrorMessage*(err: AxiomInvalidError): string {.inline, axiom: ["(assert (and axiomInvalidFingerprintMismatch))", "axiomInvalidFingerprintMismatch"].} =
  case err
  of axiomInvalidFingerprintMismatch:
    "stored axiom fingerprint differs from current source"

## Vault Load Error Message.
  ## axiom-smt: (assert (and vaultLoadInvalidAxiom vaultLoadStorageFailure))
  ## axiom-lean: vaultLoadInvalidAxiom ∧ vaultLoadStorageFailure
func vaultLoadErrorMessage*(err: VaultLoadError): string {.axiom, axiomImpl.} =
  case err.kind
  of vaultLoadInvalidAxiom:
    axiomInvalidErrorMessage(err.invalidError)
  of vaultLoadStorageFailure:
    axiomErrorMessage(err.storageError)

## Invalid Load Error.
func invalidLoadError*(err: AxiomInvalidError): VaultLoadError {.inline.} =
  VaultLoadError(kind: vaultLoadInvalidAxiom, invalidError: err)

## Storage Load Error.
func storageLoadError*(err: AxiomError): VaultLoadError {.inline.} =
  VaultLoadError(kind: vaultLoadStorageFailure, storageError: err)

## Compute Source Fingerprint.
func computeSourceFingerprint*(sourceCode: string): string {.inline, axiom: ["(assert (and (>= (str.len sourceCode) 0)))", "sourceCode.length ≥ 0"].} =
  axiom_identity.computeAxiomFingerprint(sourceCode)

## Owned Axiom Spec.
func ownedAxiomSpec*(spec: sink AxiomSpec): AxiomSpec {.inline, axiom: ["(assert (and (= result spec) (>= result 0)))", "result = spec ∧ (result ≥ 0)"].} =
  result = spec

## Init Axiom Spec.
func initAxiomSpec*(
  modulePath: sink string;
  functionName: sink string;
  fingerprint: sink string;
  smtlib2: sink string;
  storedAt: sink string = "";
  winningStrategy: sink string = "";
  retryCount: int = 0;
  vacuityProven: Option[bool] = some(true)
): AxiomSpec {.inline, axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  result = AxiomSpec(
    modulePath: modulePath.strip(),
    functionName: functionName.strip(),
    fingerprint: fingerprint.strip(),
    storedAt: storedAt.strip(),
    smtlib2: smtlib2,
    winningStrategy: winningStrategy.strip(),
    retryCount: retryCount,
    vacuityProven: vacuityProven
  )

## Sanitize Vault Token.
  ## axiom-smt: (assert (and (>= result 0) (>= raw 0)))
  ## axiom-lean: (result ≥ 0) ∧ (raw ≥ 0)
func sanitizeVaultToken*(raw: string): string {.axiom, axiomOpaque.} =
  result = newStringOfCap(raw.len)
  for ch in raw:
    if (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9'):
      result.add(ch)
    else:
      result.add('_')

## Axiom Spec File Name.
  ## axiom-smt: (assert (and (>= (str.len spec_modulePath) 0) (>= (str.len spec_functionName) 0) (>= (str.len spec_fingerprint) 0) (>= (str.len spec_storedAt) 0) (>= (str.len spec_smtlib2) 0) (>= (str.len spec_winningStrategy) 0) (and (>= spec_retryCount -9223372036854775808) (<= spec_retryCount 9223372036854775807))))
  ## axiom-lean: spec_modulePath.length ≥ 0 ∧ spec_functionName.length ≥ 0 ∧ spec_fingerprint.length ≥ 0 ∧ spec_storedAt.length ≥ 0 ∧ spec_smtlib2.length ≥ 0 ∧ spec_winningStrategy.length ≥ 0 ∧ spec_retryCount ≥ -9223372036854775808 ∧ spec_retryCount ≤ 9223372036854775807
func axiomSpecFileName*(spec: AxiomSpec): string {.axiom, axiomOpaque.} =
  sanitizeVaultToken(spec.modulePath) & "__" & sanitizeVaultToken(spec.functionName) & ".json"

## Axiom Spec To Json Node.
  ## axiom-smt: (assert (and (>= (str.len spec_modulePath) 0) (>= (str.len spec_functionName) 0) (>= (str.len spec_fingerprint) 0) (>= (str.len spec_storedAt) 0) (>= (str.len spec_smtlib2) 0) (>= (str.len spec_winningStrategy) 0) (and (>= spec_retryCount -9223372036854775808) (<= spec_retryCount 9223372036854775807))))
  ## axiom-lean: spec_modulePath.length ≥ 0 ∧ spec_functionName.length ≥ 0 ∧ spec_fingerprint.length ≥ 0 ∧ spec_storedAt.length ≥ 0 ∧ spec_smtlib2.length ≥ 0 ∧ spec_winningStrategy.length ≥ 0 ∧ spec_retryCount ≥ -9223372036854775808 ∧ spec_retryCount ≤ 9223372036854775807
func axiomSpecToJsonNode*(spec: AxiomSpec): JsonNode {.axiom, axiomImpl.} =
  %*{
    "modulePath": spec.modulePath,
    "functionName": spec.functionName,
    "fingerprint": spec.fingerprint,
    "storedAt": spec.storedAt,
    "smtlib2": spec.smtlib2,
    "winningStrategy": spec.winningStrategy,
    "retryCount": spec.retryCount,
    "vacuityProven": spec.vacuityProven.get(true)
  }

## Parse Axiom Spec.
  ## axiom-lean: node_is_json_object_or_error
func parseAxiomSpec*(node: JsonNode): Result[AxiomSpec, AxiomError] {.axiom, axiomOpaque.} =
  let modulePath = ??jsonGetNonEmptyStringField(node, "modulePath")
  let functionName = ??jsonGetNonEmptyStringField(node, "functionName")
  let fingerprint = ??jsonGetNonEmptyStringField(node, "fingerprint")
  let storedAt = ??jsonGetNonEmptyStringField(node, "storedAt")
  let smtlib2 = ??jsonGetNonEmptyStringField(node, "smtlib2")
  let wsNode = node.fields.getOrDefault("winningStrategy", newJNull())
  let winningStrategy = if wsNode.kind == JString: wsNode.getStr() else: ""
  let rcNode = node.fields.getOrDefault("retryCount", newJNull())
  let retryCount = if rcNode.kind == JInt: rcNode.getInt() else: 0
  let vpNode = node.fields.getOrDefault("vacuityProven", newJNull())
  let vacuityProven = if vpNode.kind == JBool: some(vpNode.getBool()) else: some(true)
  let spec = initAxiomSpec(
    modulePath = modulePath,
    functionName = functionName,
    fingerprint = fingerprint,
    smtlib2 = smtlib2,
    storedAt = storedAt,
    winningStrategy = winningStrategy,
    retryCount = retryCount,
    vacuityProven = vacuityProven
  )
  ok(spec)

## Load Axiom Spec.
func loadAxiomSpec*(spec: sink AxiomSpec; currentFingerprint: sink string): Result[AxiomSpec, AxiomInvalidError] =
  var ownedSpec = ownedAxiomSpec(spec)
  if ownedSpec.fingerprint != currentFingerprint.strip():
    return err(axiomInvalidFingerprintMismatch)
  let hydrated = move ownedSpec
  ok(hydrated)

{.pop.}

import std/times

## Current Vault Timestamp.
proc currentVaultTimestamp*(): string {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")

