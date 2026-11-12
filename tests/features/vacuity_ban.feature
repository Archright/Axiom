@legacy
Feature: Vacuity Ban — Prevent Trivially-True Proofs from Entering the Verification Pipeline

  Background:
    Given the Axiom engine is running
    And the vacuity ban policy is active

  # Path A: submit.nim fallback prevention
  Scenario: Malformed Leanstral output must not generate a tautology theorem
    Given a Leanstral response with no theorem, lemma, or def token
    When sanitizeTheoremSource is invoked
    Then the result must be an error containing "vacuity_ban"
    And no synthetic "theorem generated_theorem : True := by trivial" must be produced

  # Path B: smart_search induction/pattern-matching prevention
  Scenario: Induction and pattern-matching strategies must not emit self-equality
    Given a Nim function with recursive or case-based structure
    When the inference strategy selects structural induction or pattern matching
    And generateSemanticHintWithStrategy returns a SemanticHint
    Then the leanProposition must not contain "∀ (n : Nat), n = n"
    And the leanProposition must not contain "∀ (x : α), x = x"
    And isVacuousHint must return a non-empty error

  # Path C: proof_summarizer static rule cache prevention
  Scenario: Static rules must not cache vacuous SMT constraints
    Given a Lean proof source with no explicit (assert ...) lines
    When smtConstraintFromAssertionLines extracts the constraint
    And normalizeSmtConstraint processes the constraint
    Then the result must be an empty string
    And summarizeSuccessfulProof must return none(StaticRule)
    And saveStaticRule must not be called with a vacuous constraint

  # Path D: gateway SMT injection prevention
  Scenario: Empty expected SMT formula must not default to (assert true)
    Given an AxiomProofRequest with expectedSmtlib2 equal to ""
    When buildInjectedSmtlib2 constructs the SMT payload
    Then ownFormula must be ""
    And proveAxiomNode must return axiomErrVacuousContradiction

  Scenario: SMT proof gate must not inherit first-gate assertions
    Given an AxiomProofRequest with expectedSmtlib2 equal to "(assert (> x x))"
    When buildInjectedSmtlib2 constructs the SMT payload
    Then the first satisfiability gate must be scoped by push and pop
    And the final proof gate must assert the negated proposition outside that scope

  Scenario: Metadata-only SMT must not be promoted as proof evidence
    Given an AxiomProofRequest with expectedSmtlib2 equal to "(assert (and (>= depth 0)))"
    When proveAxiomNode evaluates the SMT payload
    Then the result must be axiomErrVacuousContradiction
    And proof-state anti-vacuity must isolate metadata-only verified entries
    And axiom vault hydration must reject metadata-only cache hits

  # Path E: heal.nim saveHint vacuity gate
  Scenario: saveHint must reject vacuous hints before verifiedKey promotion
    Given a SemanticHint with leanProposition "theorem foo : True := by trivial"
    When saveHint is invoked in any of the three execution paths
    Then isVacuousHint must detect the vacuity
    And the hint must not be promoted to verifiedKey
    And the log must contain "Vacuity Gate rejected"

  # Path F: certificate_cli loadCertificateTactics filter
  Scenario: Certificate tactics must filter out True.intro and trivial
    Given a certificate JSON with tactics ["exact True.intro", "rw [h]", "trivial"]
    When loadCertificateTactics reads the certificate
    Then the returned sequence must not contain "exact True.intro"
    And the returned sequence must not contain "trivial"
    And the sequence must contain exactly ["rw [h]"]

  # Path G: gate_rules missing-loop-invariant blocking
  Scenario: Functions with loops but no invariant must be demoted to certRed
    Given a certGreen function that contains a loop
    And the symbolic analyzer returns no verified loop invariant
    When applySymbolicInvariantGate evaluates the certificate
    Then the violation severity must be agBlocking
    And the certificate status must become certRed
    And the reason must be "missing-loop-invariant"

  # Path H: lean_lsp negative mutation test enforcement
  Scenario: verifyGeneratedLeanSourceWithCompiler must always run negative mutation
    Given a Lean theorem source that compiles successfully
    When the 2-arity overload of verifyGeneratedLeanSourceWithCompiler is called
    Then buildNegativeTestSource must generate a mutated version with False conclusion
    And the negative test must be compiled by the Lean kernel
    And if the negative test succeeds, verified must be false
    And the diagnostic must contain "Vacuity ban"

  # Path I: heal_leanstral semantic integrity checkpoint
  Scenario: Leanstral synthesis results must pass semantic integrity before static rule learning
    Given a Leanstral response with a theorem that passes the Lean kernel
    And the theorem source contains "∀ (n : Nat), n = n"
    When the semantic integrity checkpoint runs
    Then isVacuousLeanSource must return "self-equality tautology"
    And summarizeSuccessfulProof must not be called
    And saveStaticRule must not be called
    And applyGuardToSource must not be called

  # Path J: release build runtime isolation
  Scenario: injectContradiction must be runtime-guarded in release builds
    Given the Axiom engine is compiled with -d:release
    When AxiomProofRequest type is inspected
    Then proveAxiomNode must not reference injectContradiction outside when not defined(release)
    And the default value of injectContradiction must be false

  # Path K: ledger purification
  Scenario: Metadata-only inflation snapshots must be marked VOID
    Given the ASI ledger contains snapshots from 2026-05-05
    When ledger entries are audited for substantive evidence
    Then entries without proof obligation substance must contain void: true
    And the voidReason must be "Metadata-only Inflation"
    And a rebirth entry must exist at ASI 0.0000 after purge

  # Path L: ax prove shortcut vacuity-aware node filtering
  Scenario: ax prove must skip pseudo_verified and vacuous nodes
    Given the proof state contains a node with status pseudo_verified
    And the proof state contains a node with status vacuous_contradiction
    And the proof state contains a node with status verified but empty raw_smt_query
    When ax prove --limit 1 is executed via the shortcut path
    Then the selected node must not be pseudo_verified
    And the selected node must not be vacuous_contradiction
    And the selected node must not have empty raw_smt_query and verified status

  # Path M: atomic state persistence
  Scenario: writeFileOpt must use atomic shadow-write to prevent race conditions
    Given the Axiom engine persists proof state to disk
    When writeFileOpt is invoked with any content
    Then the implementation must write to a .tmp file first
    And moveFile must atomically rename to the target path
    And no intermediate truncated file must be observable

  # Path N: healing boundary
  Scenario: heal must refuse to promote nodes with vacuous history
    Given a proof state entry with transitionLog containing vacuous_contradiction
    When heal attempts to promote the node to verified
    Then the promotion must be refused
    And the node status must remain unverifiable
    And the log must contain "Vacuity Quarantine"
