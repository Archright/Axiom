@legacy
Feature: Heal Recovery Contract
  As an Axiom maintainer
  I want heal-generated Lean sources and proof state retries to be type-directed
  So that recovery remains deterministic across repeated self-healing rounds

  Background:
    Given heal recovery contract checks are executing

  Scenario: Lean query variables are declared from observed field use
    Given a hint proposition "items.size ≥ 0"
    When buildLeanQuery creates the theorem source
    Then the source should declare "items" as "NimSeq α"
    And the source should not declare the field name "size" as a variable

  Scenario: String length projection forces a String declaration
    Given a hint proposition "name.length ≥ 0"
    When buildLeanQuery creates the theorem source
    Then the source should declare "name" as "String"
    And the source should not declare the field name "length" as a variable

  Scenario: Sequence element length projection forces String elements
    Given a hint proposition "∀ (i : Fin items.size), items.get i.length ≥ 0"
    When buildLeanQuery creates the theorem source
    Then the source should declare "items" as "NimSeq String"
    And the source should not declare the bound name "i" as a top-level variable

  Scenario: Bool equality behavior forces a Bool declaration
    Given a hint proposition "isValid = true ∨ isValid = false"
    When buildLeanQuery creates the theorem source
    Then the source should declare "isValid" as "Bool"

  Scenario: Known String parameters normalize invalid size projections
    Given a typed hint proposition "label.size ≥ 0 ∧ label.length ≥ 0" for "label: string"
    When buildLeanQuery creates the theorem source
    Then the source should declare "label" as "String"
    And the source should rewrite "label.size" to "label.length"

  Scenario: Nested sequence parameters are parenthesized in Lean declarations
    Given a typed hint proposition for "dependents: seq[seq[int]]"
    When buildLeanQuery creates the theorem source
    Then the source should declare "dependents" as "NimSeq (NimSeq Int)"

  Scenario: Natural domain names map to the natural nonnegative axiom
    Given a hint proposition "depth ≥ 0"
    When verifiedAxiomName evaluates the proposition
    Then the axiom name should be "natural-nonneg"

  Scenario: Bool exhaustive propositions map to the bool cases axiom
    Given a hint proposition "emitJson = true ∨ emitJson = false"
    When verifiedAxiomName evaluates the proposition
    Then the axiom name should be "bool-cases"

  Scenario: Lean keyword-prefixed identifiers are escaped
    Given a hint proposition "universe_totalFunctions ≥ 0"
    When buildLeanQuery creates the theorem source
    Then the source should declare "v_universe_totalFunctions"
    And the source should not declare "universe_totalFunctions"

  Scenario: Lean reserved parameter identifiers are escaped in propositions
    Given a typed hint proposition "theorem.length ≥ 0" for "theorem: string"
    When buildLeanQuery creates the theorem source
    Then the source should declare "v_theorem"
    And the proposition should use "v_theorem.length"

  Scenario: Lean command keywords are escaped in variable declarations
    Given a typed hint includes a parameter named "axiom"
    When buildLeanQuery creates the theorem source
    Then the source should declare "v_axiom"
    And the source should not declare "axiom"

  Scenario: Lean notation keywords are escaped in propositions
    Given a typed hint proposition "prefix.length ≥ 0" for "prefix: string"
    When buildLeanQuery creates the theorem source
    Then the source should declare "v_prefix"
    And the proposition should use "v_prefix.length"

  Scenario: Leanstral theorem source always carries the extended prelude
    Given a Leanstral theorem source containing "theorem generated : NimExcept String Nat := by"
    When the source is prepared for kernel replay
    Then the prepared source should contain "inductive NimExcept"
    And the prepared source should place the prelude before the theorem

  Scenario: High attempt counts are reset before heal scheduling
    Given an ax proof state entry with attemptCount 64 and status "unverifiable"
    When the heal attempt circuit breaker runs
    Then the entry attemptCount should become 0
    And the entry should record "attempt-circuit-reset"

  Scenario: Prove refresh preserves failed heal state
    Given a previous ax proof state entry with status "unverifiable"
    When ax prove rebuilds the proof state and the current entry is "unattempted"
    Then the merged entry should keep status "unverifiable"
    And the merged entry should preserve retry metadata

  Scenario: Proof state persistence recomputes summary from entries
    Given proof state entries with verified, unverifiable, and unattempted statuses
    When the proof state is saved
    Then the persisted summary should match the entry status counts

  Scenario: Duplicate node identities share verified status
    Given proof state entries contain the same nodeId twice
    And one duplicate entry is verified
    When the proof state is saved
    Then every duplicate for that nodeId should be persisted as verified

  Scenario: Heal scheduling advances the fresh frontier before cooldown retries
    Given one fresh "unattempted" node and one previously "unverifiable" node
    When heal scheduling ranks the next batch
    Then the fresh node should be ranked before the cooldown retry node

  Scenario: Heal scheduling removes duplicate node identities from a batch
    Given the scheduler candidate list contains the same nodeId twice
    When the heal batch is finalized
    Then the nodeId should appear only once in the batch

  Scenario: Legacy stale certificates do not shadow canonical fresh certificates
    Given a canonical certificate for a node is not stale
    And an older legacy certificate path for the same node is "certStale"
    When heal checks whether the node is stale
    Then the node should not be scheduled as stale

  Scenario: Z3 persistent worker restarts after a failed query
    Given a persistent Z3 worker receives a query that exits the process
    When a normal query is submitted after the failure
    Then the normal query should still return a solver result

  Scenario: Semantic contrast uses one-shot Z3 isolation
    Given a semantic contrast query is submitted during heal
    When Z3 execution is required
    Then the contrast check should run through a bounded one-shot process

  Scenario: Repeated heal rounds do not duplicate existing source hints
    Given a function already has the same generated axiom hint in its leading comment block
    When virtual hint injection runs again for the function
    Then the source should still contain exactly one copy of that hint

  Scenario: Sequence element field hints are emitted with explicit projection binding
    Given a function parameter has type "seq[string]"
    When BoundaryExtractor emits an element length invariant
    Then the Lean hint should contain "(items.get itemsIdx).length"

  Scenario: Sequence element binders do not capture later parameter constraints
    Given a function has a seq parameter and a later parameter named "i"
    When BoundaryExtractor emits an element invariant and an integer boundary
    Then the generated forall binder should be unique
    And the later integer boundary should stay outside the forall scope

  Scenario: Prelude-owned isolation atoms are not shadowed by variable declarations
    Given a hint proposition "path.length ≥ 0 ∧ external_io_isolated"
    When buildLeanQuery creates the theorem source
    Then the source should not declare "external_io_isolated" as a variable

  Scenario: Leanstral prelude injection removes embedded imports
    Given a generated theorem body contains an embedded "import Std"
    When the source is prepared for kernel replay
    Then the prepared source should contain only the leading import

  Scenario: Proof state converges to physical certificate status
    Given a physical certificate has status "certGreen"
    And the matching proof-state entry is "unattempted"
    When certificate convergence renders the proof-state universe
    Then the proof-state entry should become "verified"
    And the convergence metadata should record the checked certificate count

  Scenario: Existing proof-state labels converge outside the current sourceRoot scope
    Given the current proof-state sourceRoot is "src/core"
    And an existing proof-state entry belongs to "src/verification"
    And the matching physical certificate has status "certGreen"
    When certificate convergence renders the proof-state universe
    Then the existing out-of-scope proof-state entry should become "verified"
    And the matching certificate should be included in the convergence metadata

  Scenario: Stale physical certificates block historical verified carry-forward
    Given a previous proof-state entry is "verified"
    And the current physical certificate is "certStale"
    When previous proof state is merged into the current proof state
    Then the current entry should remain "certStale"
    And the historical "verified" state should not be carried forward

  Scenario: Architecture gate rejects proof-state and certificate divergence
    Given a physical certificate has status "certStale"
    And the proof-state entry claims "verified"
    When read-source convergence is validated
    Then the architecture gate should reject the mismatch

  Scenario: Canonical engineAsiFixed4 takes precedence over substantiveAsiFixed4 in lock-file fallback
    Given a proof state has engineAsiFixed4 = "0.5766" and substantiveAsiFixed4 = "1.0000"
    When the lock-file fallback parses the state
    Then engineAsiFixed4 must be selected as the canonical ASI
