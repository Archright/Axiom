import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## SOLID queries — SRP cohesion, LSP/ISP interface audit, query dispatch.
##
## DIP + OCP extracted to solid_queries_dip_ocp.nim.
## This module re-exports DIP/OCP symbols and provides registerSolidQueries.

import gate/nimtry/solid_queries_dip_ocp
export solid_queries_dip_ocp

import std/tables
import std/sets
import std/sequtils
import std/os
import std/strutils
import std/json
import gate/nimtry/nimtry_registry
import gate/nimtry/interface_auditor
import gate/architecture_ast_facts
import core/gate/architecture_policy
import gate/rule_patterns
import gate/cohesion_enforce
import core/trusted/axiom_pragmas

proc registerSolidQueries*(queries: var seq[NimtryQuery]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # ── SOLID queries ────────────────────────────────────────────────────
  # SOLID: LSP pragma contract violations (from query_engine)
  queries.add(NimtryQuery(
    name: "solid-lsp",
    rule: "SOLID",
    severity: "warning",
    taxonomy: structural,
    checker: proc(allFacts: seq[ModuleFacts]; policy: ArchitecturePolicy): seq[ArchitectureViolationArtifact] {.raises: [].} =
      runInterfaceAudit(allFacts, policy)
  ))

  # SOLID: SRP cohesion metrics (from query_engine)
  queries.add(NimtryQuery(
    name: "solid-srp",
    rule: "SOLID",
    severity: "error",
    taxonomy: structural,
    checker: checkCohesionV2
  ))

  # SOLID: Forbidden concrete calls / DIP (from core_rules)
  queries.add(NimtryQuery(
    name: "solid-forbidden-calls",
    rule: "SOLID",
    severity: "error",
    taxonomy: structural,
    checker: checkForbiddenCallsWrapper
  ))

  # SOLID: OCP registry violation detection
  queries.add(NimtryQuery(
    name: "solid-ocp",
    rule: "SOLID",
    severity: "warning",
    taxonomy: structural,
    checker: checkOcpViolation
  ))

  # SOLID: Forbidden pragma usage / SoC enforcement
  queries.add(NimtryQuery(
    name: "solid-forbidden-pragmas",
    rule: "SOLID",
    severity: "error",
    taxonomy: structural,
    checker: checkForbiddenPragmas
  ))

  # SoC: Leaf module import restriction
  queries.add(NimtryQuery(
    name: "soc-leaf-module-imports",
    rule: "SoC",
    severity: "error",
    taxonomy: structural,
    checker: proc(allFacts: seq[ModuleFacts]; policy: ArchitecturePolicy): seq[ArchitectureViolationArtifact] {.raises: [].} =
      for m in allFacts:
        # Leaf modules in src/core/types/ must not import other modules.
        # stdlib imports (std/*) are allowed — they are immutable infrastructure.
        # Sibling imports within core/types/ are allowed — type cross-referencing is expected.
        if m.path.startsWith("src/core/types/") and m.imports.len > 0:
          # Forwarding stubs have no type defs and no functions — exempt them
          let isStub = m.typeDefs.len == 0 and m.functions.len == 0
          if not isStub:
            let nonStdImports = m.imports.filterIt(
              not it.modulePath.startsWith("std/") and
              not it.modulePath.startsWith("core/types/") and
              not it.modulePath.startsWith("core/symbolic/") and
              not it.modulePath.startsWith("core/integrity/") and
              # Declarative metadata pragmas (axiomLayer/spec) are compile-time
              # annotations, not runtime/domain-logic dependencies — the leaf-module rule
              # targets runtime dependency direction, so trusted/contracts imports of
              # pragma/macro definitions are exempt (docs/spec/gate_runner_lcom_policy.md §2).
              not it.modulePath.startsWith("core/trusted/") and
              not it.modulePath.startsWith("core/contracts/"))
            if nonStdImports.len > 0:
              let importNames = nonStdImports.mapIt(it.modulePath).join(", ")
              result.add(ArchitectureViolationArtifact(
                rule: "SOC-leaf-module-imports",
                detail: m.path & ": leaf type module must not import non-stdlib modules. Found: " & importNames,
                files: @[m.path],
                severity: "error",
              ))
  ))

  # SoC: Cyclic import detection (direct A↔B cycles)
  queries.add(NimtryQuery(
    name: "soc-cyclic-imports",
    rule: "SoC",
    severity: "error",
    taxonomy: structural,
    checker: proc(allFacts: seq[ModuleFacts]; policy: ArchitecturePolicy): seq[ArchitectureViolationArtifact] {.raises: [].} =
      # Build import adjacency: module → set of imported modules
      var importMap: Table[string, HashSet[string]]
      for m in allFacts:
        var s = initHashSet[string]()
        for imp in m.imports:
          s.incl(imp.modulePath)
        importMap[m.path] = s
      # Detect direct cycles: A imports B and B imports A
      for m in allFacts:
        for imp in m.imports:
          if importMap.hasKey(imp.modulePath) and importMap.hasKey(m.path):
            let targetSet = importMap.getOrDefault(imp.modulePath)
            if m.path in targetSet and m.path < imp.modulePath:  # Report each cycle only once
              result.add(ArchitectureViolationArtifact(
                rule: "SOC-cyclic-imports",
                detail: "Circular import detected: " & m.path & " ↔ " & imp.modulePath,
                files: @[m.path, imp.modulePath],
                severity: "error",
              ))
  ))

  # SoC: Domain placement enforcement — top-level files in src/core/ should be in subdirectories
  queries.add(NimtryQuery(
    name: "soc-domain-placement",
    rule: "SoC",
    severity: "warning",
    taxonomy: structural,
    checker: proc(allFacts: seq[ModuleFacts]; policy: ArchitecturePolicy): seq[ArchitectureViolationArtifact] {.raises: [].} =
      # Load root_primitives from domain_layout.json (SSOT)
      let layoutPath = "src/core/domain_layout.json"
      if not fileExists(layoutPath): return
      let layoutContent = try: readFile(layoutPath) except CatchableError: return
      var rootPrimitives = initHashSet[string]()
      block parseLayout:
        let layoutJson = try: parseJson(layoutContent) except CatchableError: break parseLayout
        let rpNode = layoutJson{"root_primitives"}
        if rpNode.isNil or rpNode.kind != JArray: break parseLayout
        for rp in rpNode:
          rootPrimitives.incl(rp.getStr(""))
      # Files in src/core/ that aren't in a subdirectory must be in root_primitives
      for m in allFacts:
        if not m.path.startsWith("src/core/"): continue
        if m.path.contains("_parts/"): continue
        let relPath = m.path.replace("src/core/", "")
        if "/" in relPath: continue  # already in a subdirectory
        let moduleName = relPath.replace(".nim", "")
        if moduleName in rootPrimitives: continue
        result.add(ArchitectureViolationArtifact(
          rule: "SOC-domain-placement",
          detail: m.path & ": top-level file in src/core/ — should be in a domain subdirectory per domain_layout.json",
          files: @[m.path],
          severity: "warning",
        ))
  ))

{.pop.}
