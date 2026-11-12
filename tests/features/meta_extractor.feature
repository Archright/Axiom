@legacy
Feature: Meta-Extractor C FFI Boundary Analysis
  Detects {.importc.}, {.cdecl.} patterns and marks nodes for enhanced
  boundary extraction via Nim compile-time macro.

  Scenario: FFI detection triggers in source text
    Given source contains "{.importc.}"
    When detectFfiInSource is called
    Then result is true

  Scenario: Non-FFI source returns false
    Given source is "proc foo(x: int) = discard"
    When detectFfiInSource is called
    Then result is false
