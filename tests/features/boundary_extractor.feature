@legacy
@executable
Feature: BoundaryExtractor deterministic boundary generation

  Background:
    Given the Axiom CLI is compiled and available
    And the verification certificate vault is initialized

  Scenario: Extract string length boundary from function parameter
    Given a Nim function with parameter "s: string"
    When BoundaryExtractor processes the function signature
    Then the generated hint must contain "s.length ≥ 0"
    And the SMT constraint must contain "(str.len s)"
    And the Lean query must declare variable "s : String"

  Scenario: Extract int safe boundary avoiding OfNat errors
    Given a Nim function with parameter "x: int"
    When BoundaryExtractor processes the function signature
    Then the generated hint must contain "x ≥ 0"
    And the Lean query must declare variable "x : Int"
    And the proposition must compile without "OfNat" errors

  Scenario: Extract object field boundaries from JobSemaphore
    Given a Nim function with parameter "sem: var JobSemaphore"
    And JobSemaphore has fields "maxJobs: int" and "activeJobs: int"
    When BoundaryExtractor processes the function signature
    Then the generated hint must contain "sem_maxJobs ≥ 0"
    And the generated hint must contain "sem_activeJobs ≥ 0"
    And the Lean query must declare variables with type "Int"

  Scenario: Resolve renamed module via moduleAliasTable
    Given a nodeId referencing legacy module "cli_utils.nim"
    And the current module is named "file_utils.nim"
    When the heal pipeline assembles fileContext
    Then the alias table must resolve to "file_utils.nim"
    And fileContext must load successfully without error

  Scenario: Prefer src/ over root for guard injection target
    Given duplicate "pipeline_healing_logic.nim" exists in root and src/
    When the heal pipeline selects the source file for guard injection
    Then the src/ path must be selected as the injection target
    And the root duplicate must remain untouched

  Scenario: Extract assignment constraints as data-flow equations
    Given a Nim function body containing `x = y + 1`
    When `extractPathConditions` traverses the AST
    Then the result should contain an equality constraint `(= x (+ y 1))`
    And the Lean proposition should contain `x = y + 1`

  Scenario: Extract assert conditions as programmer invariants
    Given a Nim function body containing `assert x > 10`
    When `extractPathConditions` traverses the AST
    Then the result should contain `(> x 10)`
    And the Lean proposition should contain `x > 10`

  Scenario: Extract return value constraints
    Given a Nim function body containing `return x * 2`
    When `extractPathConditions` traverses the AST
    Then the result should contain a constraint involving `x * 2`
    And duplicate expressions should be deduplicated

  Scenario: Extract conditional return constraints from if-then-else
    Given a Nim function body containing `if x > 10: return x else: return 0`
    When `extractPathConditions` traverses the AST
    Then the result should contain `(=> (> x 10) (= result x))`
    And the result should contain `(=> (not (> x 10)) (= result 0))`
    And the Lean proposition should contain `→ result = x`

  Scenario: Option isSome field access is filtered as trivial
    Given a Nim function with parameter "opt: Option[int]"
    And the function body contains "return opt.isSome"
    When BoundaryExtractor processes the function
    Then "opt.isSome" must be classified as trivial
    And the Lean theorem must not contain "opt.isSome"
    And the Lean theorem must not contain "invalidField"

  Scenario: Dead Logic Elimination removes trivial constraints from Lean theorem
    Given a Nim function with parameters "s: string" and "x: int"
    And the function body contains only "discard"
    When BoundaryExtractor processes the function
    Then "s.length ≥ 0" must be classified as trivial
    And the generated Lean theorem must not contain "s.length ≥ 0"
    And the SMT constraint must not contain "(str.len s)"

  Scenario: Type inference declares Option variables with Option α
    Given a Nim function with parameter "opt: Option[int]"
    And the function body contains a condition "if opt.isSome: return true"
    When the Lean query is built
    Then the variable "opt" must be declared with type "Option α"
    And the variable must not be declared with type "Nat" or "α" alone
