Feature: Vendored tree-sitter Build

  Scenario: Vendored C runtime compiles successfully
    Given the vendored tree-sitter C runtime exists at vendor/tree-sitter/
    When the vendored_build module is compiled
    Then the tree_sitter_nim symbol is available
    And the ABI shim bridges Nim and C calling conventions

  Scenario: Parser grammar compiles from vendored sources
    Given the vendored parser grammar exists at vendor/tree-sitter-nim/
    When the parser.c and scanner.c are compiled
    Then the tree_sitter_nim function is exported
    And the parser can parse Nim source code
