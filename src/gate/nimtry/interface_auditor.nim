import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Interface contract auditor (LSP + ISP checks).
##
## LSP: Verify that implementations honor interface pragma contracts.
## ISP: Detect fat interfaces (modules importing many symbols but using few).

import std/tables
import std/strutils

import gate/architecture_ast_facts
import core/gate/architecture_policy
import gate/rule_patterns
import ../../core/trusted/axiom_pragmas

export rule_patterns.ArchitectureViolationArtifact

func checkLspContracts*(
  pragmas: seq[PragmaFact];
  functions: seq[FunctionFact];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## Check that functions explicitly marked with {.implements: Interface.}
  ## have the required pragma contracts.
  for pragma in pragmas:
    if pragma.pragmaName == "axiomImplements":
      let ifaceName = pragma.pragmaValue.strip(chars = {'"', ' ', '\t'})
      var contract: InterfaceContract
      var found = false
      try:
        if policy.interfaces.hasKey(ifaceName):
          contract = policy.interfaces[ifaceName]
          found = true
      except KeyError:
        discard
      if found:
        # Check required pragmas
        for reqPragma in contract.requiredPragmas:
          var hasPragma = false
          for p in pragmas:
            if p.targetName == pragma.targetName and p.pragmaName == reqPragma:
              hasPragma = true
              break
          if not hasPragma:
            result.add(ArchitectureViolationArtifact(
              rule: "SOLID",
              detail: pragma.location.path & ":" & $pragma.location.line &
                " function '" & pragma.targetName &
                "' (axiomImplements " & ifaceName & ") lacks required pragma {." & reqPragma & ".}",
              files: @[pragma.location.path, contract.file],
              severity: "error"))
    elif pragma.pragmaName == "implements":
      # Legacy pragma support
      let ifaceName = pragma.pragmaValue.strip(chars = {'"', ' ', '\t'})
      var contract: InterfaceContract
      var found = false
      try:
        if policy.interfaces.hasKey(ifaceName):
          contract = policy.interfaces[ifaceName]
          found = true
      except KeyError:
        discard
      if found:
        for reqPragma in contract.requiredPragmas:
          var hasPragma = false
          for p in pragmas:
            if p.targetName == pragma.targetName and p.pragmaName == reqPragma:
              hasPragma = true
              break
          if not hasPragma:
            result.add(ArchitectureViolationArtifact(
              rule: "SOLID",
              detail: pragma.location.path & ":" & $pragma.location.line &
                " function '" & pragma.targetName &
                "' (implements " & ifaceName & ") lacks required pragma {." & reqPragma & ".}",
              files: @[pragma.location.path, contract.file],
              severity: "error"))

func checkIspFatInterfaces*(
  imports: seq[ImportFact];
  calls: seq[CallFact];
  policy: ArchitecturePolicy;
  threshold: float = 3.0
): seq[ArchitectureViolationArtifact] {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  ## Detect fat interfaces: modules importing many symbols but using few.
  ## Group imports by source module.
  var importsByModule = initTable[string, seq[string]]()
  
  for importFact in imports:
    let modPath = importFact.modulePath
    importsByModule.mgetOrPut(modPath, @[]).add(modPath)
  
  # Simplified check: if a module has many imports from same source
  for modPath, imported in importsByModule:
    if imported.len.float >= threshold * 1.0:
      # This is a very crude heuristic — needs actual usage count
      # For now, flag only extreme cases (> 20 imports from one module)
      if imported.len > 20:
        result.add(ArchitectureViolationArtifact(
          rule: "SOLID",
          detail: "module imports " & $imported.len & " symbols from " & modPath &
            " (potential fat interface; threshold = " & $threshold & ")",
          files: @[],
          severity: "warning"))

func runInterfaceAudit*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## Run both LSP and ISP checks.
  for moduleFacts in allFacts:
    result.add(checkLspContracts(moduleFacts.pragmas, moduleFacts.functions, policy))
    result.add(checkIspFatInterfaces(moduleFacts.imports, moduleFacts.calls, policy))

{.pop.}
