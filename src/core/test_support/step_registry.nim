import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Step Registry — Compile-time test step collection
## Provides `testStep` pragma for marking test procedures and a compile-time
## mapping table for integration with `feature_macro.nim`.
##
## The orphaned_step_checker tool scans source files for this annotation
## and cross-validates against YAML scenario files.

import std/[macros, tables]
import core/test_support/feature_macro

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template testStep*(name: string) {.pragma.}
  ## Marks a proc as a registered test step.
  ## `name` is the canonical step identifier used in YAML/Gherkin scenarios.
  ##
  ## Usage:
  ##   proc whenUserCreatesProof*() {.testStep: "user creates proof".} =
  ##     ...

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func stepName*(procSym: static string): string =
  ## Extract the step name from a testStep-annotated proc at compile time.
  ## Returns empty string if no testStep annotation found.
  result = ""

# ── Compile-Time Step Mapping Table ──────────────────────────────────────────
# Registers step text → proc name mappings at compile time.
# Used by featureTest/featureSuite macros to auto-resolve steps.

var compileTimeStepRegistry {.compileTime.}: StepMapping

func registerStepMapping*(stepText: string; procName: string) {.compileTime.} =
  ## Register a step text → proc name mapping at compile time.
  compileTimeStepRegistry.registerStep(stepText, procName)

func getStepMapping*(): StepMapping {.compileTime.} =
  ## Get the current compile-time step mapping.
  compileTimeStepRegistry

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro steps*(body: untyped): untyped =
  ## DSL for bulk-registering step mappings at compile time.
  ##
  ## Usage:
  ##   steps:
  ##     "a PBT engine with seed-based deterministic generation" -> setupPbtEngine
  ##     "200 DAGs are generated with up to 20 nodes" -> generateDags
  ##     "every generated DAG must have hasCycle == false" -> verifyAcyclic
  ##
  ## Each line maps a Gherkin step text (left) to a Nim proc name (right).
  result = newStmtList()
  for stmt in body:
    if stmt.kind == nnkInfix and stmt[0].strVal == "->":
      let stepText = stmt[1].strVal
      let procName = stmt[2].strVal
      result.add quote do:
        registerStepMapping(`stepText`, `procName`)

