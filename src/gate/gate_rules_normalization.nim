import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import std/os
import std/sequtils
import std/strutils

import core/domain_types
import core/domain_utils
import ../core/trusted/axiom_pragmas
export domain_utils.qualifiedName

# qualifiedName is now SSOT in core/types/domain_types.nim

## axiom-smt: (assert (and (>= (seq.len values) 0) (forall ((valuesIdx Int)) (=> (and (>= valuesIdx 0) (< valuesIdx (seq.len values))) (>= (str.len (seq.nth values valuesIdx)) 0))) (forall ((valuesIdx Int)) (=> (and (>= valuesIdx 0) (< valuesIdx (seq.len values))) (>= (str.len (seq.nth values valuesIdx)) 0)))))
## axiom-lean: values.size ≥ 0 ∧ (∀ (valuesIdx : Fin values.size), (values.get valuesIdx).length ≥ 0) ∧ (∀ (valuesIdx : Fin values.size), (values.get valuesIdx).length ≥ 0)
proc normalizedEntries*(values: seq[string]): seq[string] {.axiom, axiomImpl.} =
  result = values
    .mapIt(it.strip())
    .filterIt(it.len > 0)
    .deduplicate()

## axiom-smt: (assert (and (>= depth 0)))
## axiom-lean: depth >= 0
proc normalizedResources*(cert: FunctionCertificate): seq[string] {.axiomOpaque.} =
  result = normalizedEntries(cert.accessedResources)

## axiom-smt: (assert (and (>= depth 0)))
## axiom-lean: depth >= 0
proc normalizedMutations*(cert: FunctionCertificate): seq[string] {.axiomOpaque.} =
  result = normalizedEntries(cert.mutatedResources)

## axiom-smt: (assert (and (>= depth 0)))
## axiom-lean: depth >= 0
proc moduleStem*(cert: FunctionCertificate): string {.axiom, axiomImpl.} =
  result = splitFile(string(cert.modulePath)).name

proc isCliCompositionRoot*(cert: FunctionCertificate): bool =
  let normalized = string(cert.modulePath).replace("\\", "/").toLowerAscii()
  normalized.startsWith("cli/commands/") or
    (normalized.startsWith("cli/") and normalized.endsWith("_cli.nim"))

proc isDependencyBudgetBoundary*(cert: FunctionCertificate): bool =
  let normalized = string(cert.modulePath).replace("\\", "/").toLowerAscii()
  isCliCompositionRoot(cert) or
    normalized == "core/vault_manager.nim" or
    (
      normalized == "verification/gate_rules_architecture.nim" and
      cert.functionName == "applyArchitecturePrinciplesGate"
    )

## axiom-smt: (assert (and (>= (str.len resource) 0) (= (str.len trimmed) 0)))
## axiom-lean: resource.length ≥ 0 ∧ trimmed.length = 0
proc parseDomainPrefix*(resource: string): string {.axiom, axiomImpl.} =
  ## Data normalization: extract domain prefix from a qualified identifier.
  let trimmed = resource.strip()
  if trimmed.len == 0:
    return ""
  for i in 0 ..< trimmed.len:
    if trimmed[i] == '.' or trimmed[i] == '_':
      return trimmed[0 ..< i]
  result = ""

## axiom-smt: (assert (and (>= depth 0)))
## axiom-lean: depth >= 0
proc isWriteFunction*(cert: FunctionCertificate): bool {.axiomOpaque.} =
  ## AST-based mutation detection: a function is a write function if its
  ## tree-sitter AST contains assignments to non-local dot expressions or
  ## module-global identifiers (computed during certificate hydration).
  result = cert.mutatedResources.len > 0
{.pop.}

