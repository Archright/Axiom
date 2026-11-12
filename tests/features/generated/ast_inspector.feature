@generated @medium
Feature: ast_inspector
  # generated | src/sieve/ast_inspector.nim | sieve | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "sieve/ast_inspector" is loaded
    Then all exported types should be instantiable
