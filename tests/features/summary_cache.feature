Feature: Summary Cache — AST Hash Deduplication
  As an Axiom operator running batch verification
  I want identical AST structures to share a single check-sat result
  So that redundant solver calls are eliminated without affecting correctness

  Background:
    Given the AST hash module is available
    And the summary cache is initialized

  @core
  Scenario: Cache hit on identical source
    Given a Nim source string "proc add(x, y: int): int = x + y"
    When computeAstHash is called on the source
    And computeAstHash is called again on the same source
    Then both hashes must be equal
    And the cache must return the same result for the second call

  @core
  Scenario: Cache miss on semantic change
    Given a Nim source string "proc add(x, y: int): int = x + y"
    And a modified source string "proc add(x, y: int): int = x - y"
    When computeAstHash is called on both sources
    Then the two hashes must differ

  @core
  Scenario: Whitespace-only change produces same hash
    Given a Nim source string "proc add(x, y: int): int = x + y"
    And a whitespace-variant string "proc  add(x,  y:  int):  int  =  x  +  y"
    When computeAstHash is called on both sources
    Then the two hashes must be equal

  @core
  Scenario: Comment-only change produces same hash
    Given a Nim source string "proc add(x, y: int): int = x + y"
    And a commented variant string "proc add(x, y: int): int = ## add\nx + y"
    When computeAstHash is called on both sources
    Then the two hashes must be equal

  @fallback
  Scenario: Fallback when tree-sitter parser unavailable
    Given the tree-sitter parser is not available
    And a Nim source string "proc greet(): string = \"hello\""
    When computeAstHash is called on the source
    Then a valid content-based hash must be returned
    And the hash must be non-zero

  @core
  Scenario: Determinism — same input always produces same hash
    Given a Nim source string "func max(a, b: int): int = if a > b: a else: b"
    When computeAstHash is called 100 times on the source
    Then all 100 hashes must be identical
