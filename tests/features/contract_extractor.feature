@legacy
Feature: Contract Extractor generates valid SMT-LIB2 from Nim source
  When the vault has no smtlib2 for a function, the contract extractor
  must infer preconditions from Nim AST patterns and translate them into
  valid Lean 4 theorems without sorry.

  Background:
    Given the contract extractor is initialized

  Rule: String parameters produce str.len >= 0 preconditions
    Scenario: consumeSExpr raw string parameter
      Given a Nim function "consumeSExpr" in "src/core/smt_to_lean_bridge.nim"
      And the function has a parameter "raw" of type "string"
      When the extractor generates a contract
      Then the preconditions contain "(assert (>= (str.len raw) 0))"
      And the generated Lean theorem contains "Nat.zero_le raw.length"
      And the theorem does not contain "sorry"

  Rule: Seq parameters produce seq.len >= 0 preconditions
    Scenario: Array indexing on a seq parameter
      Given a Nim function "processItems" with parameter "items" of type "seq[int]"
      And the body contains "items[i]"
      When the extractor generates a contract
      Then the preconditions contain "(assert (>= i 0))"
      And the preconditions contain "(assert (< i (seq.len items)))"

  Rule: Division implies non-zero divisor precondition
    Scenario: Integer division in function body
      Given a Nim function "safeDiv" with parameters "a" and "b" of type "int"
      And the body contains "a div b"
      When the extractor generates a contract
      Then the preconditions contain "(assert (not (= b 0)))"

  Rule: Field accesses are skipped due to lack of type info
    Scenario: Object field access with .len
      Given a Nim function "sexprToZ3ProofNode" with parameter "node" of type "SExprNode"
      And the body contains "node.children.len"
      When the extractor generates a contract
      Then the preconditions do not contain "node.children"
      And the generated Lean theorem does not contain "sorry"

  Rule: Functions with no extractable contracts fall back to trivial
    Scenario: Semaphore acquire with no primitive preconditions
      Given a Nim function "acquire" in "src/gate/semaphore.nim"
      And the function has no string or seq parameters
      And the body contains no array indexing or division
      When the extractor generates a contract
      Then the preconditions are empty
      And the generated Lean theorem contains "True := by trivial"
      And the theorem does not contain "sorry"

  Rule: AST-based extraction avoids string-matching false positives
    Scenario: Commented code does not generate spurious preconditions
      Given a Nim function "safeComment" with parameter "arr" of type "seq[int]"
      And the body contains "# arr[999] div 0"
      When the extractor generates a contract
      Then the preconditions are empty

    Scenario: Type declaration brackets are not confused with indexing
      Given a Nim function "typeInBody" with parameter "items" of type "seq[int]"
      And the body contains "var tmp: seq[int]"
      When the extractor generates a contract
      Then the preconditions do not contain "tmp"

  Rule: @axiom-hint annotations override heuristic extraction
    Scenario: sexprToZ3ProofNode with @axiom-hint smt annotation
      Given a Nim function "sexprToZ3ProofNode" in "src/core/smt_to_lean_bridge.nim"
      And the source contains "# @axiom-hint: lean=... smt=..."
      When the extractor reads the @axiom-hint annotation
      Then the SMT contains "(and (>= (str.len node_atom) 0) (>= (seq.len node_children) 0) (or (= node_isList true) (= node_isList false)))"
      And the generated Lean theorem contains "constructor"
      And the theorem contains "Nat.zero_le node_atom.length"
      And the theorem does not contain "sorry"
