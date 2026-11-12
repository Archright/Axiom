@generated @critical
Feature: nim_ast_to_json_nodes
  # generated | src/core/translator/nim_ast_to_json_nodes.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/translator/nim_ast_to_json_nodes" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/translator/nim_ast_to_json_nodes" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs sourceCodeToJsonNodes
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func sourceCodeToJsonNodes is callable
    Given the module "core/translator/nim_ast_to_json_nodes" is loaded
    Then func sourceCodeToJsonNodes should return a valid value
