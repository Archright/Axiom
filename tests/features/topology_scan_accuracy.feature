@legacy
@topology @scan @accuracy
Feature: Topology Scan Declaration Accuracy
  The topology scanner must correctly distinguish function declarations from
  call expressions in Nim source files, preventing phantom nodes from
  polluting the verification queue.

  Background:
    Given a Nim project source root is scanned

  Rule: C-style declaration detection is skipped for Nim source files
    Scenario: Call expressions are not classified as declarations
      Given a Nim source file containing the line `let args = commandLineParams()`
      When the topology scanner processes the file
      Then the symbol `commandLineParams` must NOT appear in the verification queue

    Scenario: Method calls are not classified as declarations
      Given a Nim source file containing the line `if token.startsWith("-"):`
      When the topology scanner processes the file
      Then the symbol `startsWith` must NOT appear in the verification queue

    Scenario: Assignment calls are not classified as declarations
      Given a Nim source file containing the line `result = joinPath(dir, file)`
      When the topology scanner processes the file
      Then the symbol `joinPath` must NOT appear in the verification queue

  Rule: Real Nim function declarations are still detected
    Scenario: Nim proc declarations are detected as symbols
      Given a Nim source file containing the line `proc foo*(x: int): int =`
      When the topology scanner processes the file
      Then the symbol `foo` must appear in the verification queue with a valid source body

    Scenario: Nim func declarations are detected as symbols
      Given a Nim source file containing the line `func bar(): string {.noSideEffect.} =`
      When the topology scanner processes the file
      Then the symbol `bar` must appear in the verification queue
