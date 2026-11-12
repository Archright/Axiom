@legacy
Feature: Nim→Lean Transpilation Layer
  As an Axiom integrity engine
  I want Nim AST nodes to be deterministically translated to Lean 4 mathematical structures
  So that certVerifiedAxiom represents a real verified binding, not just a classification label

  Background:
    Given the Axiom project is built and the verified_axioms registry contains 34 mapping entries

  @VerifiedAxiomRegistry
  Scenario: Dictionary maps Nim stdlib to Lean theorems 1:1
    When I query the axiom mapping for "nim.string.len.isNat"
    Then the axiomId "nim.string.len.isNat" maps to Lean theorem "String.length"
    And the leanType is "Nat"
    And the proof obligation is "∀ (s : NimString), s.length ≥ 0"
    And the axiom is verified

  Scenario: Dictionary maps arithmetic commutativity
    When I query the axiom mapping for "nim.int.add.comm"
    Then the proof obligation is "∀ (a b : NimInt), a + b = b + a"
    And the category is acArithmetic

  Scenario: Dictionary maps type coercion isomorphism
    When I query axioms by category acTypeCoercion
    Then at least 10 entries exist
    And "nim.int.iso.lean.int", "nim.string.iso.lean.string", "nim.result.iso.lean.except" are all present

  Scenario: SHA-256 hash is computed deterministically
    Given two calls to computeAxiomHash for the same axiomId
    Then the returned hashes are identical

  Scenario: Unapproved axioms are rejected
    Given a Lean proposition that does not match any approved axiom
    When isVerifiedAxiomProperty is called
    Then the result is false

  @SkeletonGeneration
  Scenario: Bridge translates simple Nim function to Lean def
    Given Nim source "proc add(a, b: int): int = a + b"
    When extractNimFunction is called for "add"
    Then the return type is "int"
    And the param count is 2
    And buildLeanFunctionDef generates "def add (a : NimInt) (b : NimInt) : NimInt :="

  Scenario: Bridge handles Result/Option translation
    Given Nim source "proc check(r: Result[int, string]): bool = r.isOk()"
    When translateNimExprToLean is called on "r.isOk()"
    Then the result is "r.isOk"

  Scenario: Bridge skeleton includes axiom prelude
    When buildBridgeLeanSkeleton is called with valid source
    Then the output contains "NimInt := Int"
    And the output contains "@[aesop safe apply]"

  @TacticHintInjection
  Scenario: Leanstral prompt includes axiom hint database
    When buildLeanstralTacticPrompt is called with a skeleton
    Then the output contains "Axiom Hint Database"
    And the output contains "aesop"

  Scenario: Hint database excludes static prelude entries
    When buildLeanHintDatabase is called
    Then the output omits axioms already in axiomTheoremBlock
    And dynamic-only axioms include "nim.nat.pred.bound"

  @HashVerification
  Scenario: Axiom linkage verifies matching hash
    Given a certVerifiedAxiom certificate with correct axiomHash
    When verifyAxiomLinkage is called
    Then the result.verified is true

  Scenario: Axiom linkage fails on hash mismatch
    Given a certVerifiedAxiom certificate with incorrect axiomHash
    When verifyAxiomLinkage is called
    Then the result.verified is false
    And result.reason contains "hash mismatch"

  Scenario: Axiom linkage fails on missing axiomId
    Given a certVerifiedAxiom certificate with empty axiomId
    When verifyAxiomLinkage is called
    Then the result.verified is false
    And result.reason contains "missing axiomId"

  Scenario: Gate Rule 10 downgrades mismatched certVerifiedAxiom
    Given a certificate with status certVerifiedAxiom and invalid axiomHash
    When applyAxiomLinkageGate is applied
    Then the certificate status is changed to certStale
    And the gate.result.blockingFailures > 0

  Scenario: verifyCertificates applies Gate Rule 10 during full certificate verification
    Given a stored certVerifiedAxiom certificate has an invalid axiomHash
    When verifyCertificates runs against the certificate vault
    Then the certificate status is changed to certStale
    And architectureGate.blockingFailures is greater than 0

  # Wave 15 Fix: abbrev type aliases, get_nat wrapper, PROOF_HERE marker, vacuity bypass

  # Prelude fix: abbrev types, removed aesop, exact Int theorems, deduplication
