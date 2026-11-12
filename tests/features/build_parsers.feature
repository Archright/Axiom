Feature: Build Parsers Tool

  Scenario: Build tree-sitter parser from vendored sources
    Given the vendored tree-sitter sources exist
    When build_parsers.nim is executed
    Then libtreesitter_nim.a is produced
    And the tree_sitter_nim symbol is exported
    And build stamp is written with content hashes

  Scenario: Rebuild is idempotent
    Given a previous build exists
    When build_parsers.nim is executed again
    Then the output is identical if sources unchanged
