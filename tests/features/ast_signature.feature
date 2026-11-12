@legacy
Feature: AST-Based Axiom Signature
  Provides deterministic structure-level matching. Two functions with
  identical IR structure produce the same signature regardless of variable
  names or formatting. Uses SHA-256 for hashing.

  Background:
    Given the Axiom system is initialized

  Scenario: IR type to canonical short name
    When irTypeShortName is called with irtBitVec64
    Then the result is "bv64"

  Scenario: Parameter signature generation
    When paramSignature is called
    Then the result is a deterministic hash string

  Scenario: Structural equality detection
    Given two structurally identical IR function defs
    When their signatures are computed
    Then the signatures are equal
