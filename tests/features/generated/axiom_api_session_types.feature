@generated @critical
Feature: axiom_api_session_types
  # generated | src/core/api/axiom_api_session_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/api/axiom_api_session_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types CaptureSessionResponse, stored, sessionId
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/api/axiom_api_session_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type CaptureSessionResponse is instantiable
    Given the module "core/api/axiom_api_session_types" is loaded
    Then type CaptureSessionResponse should be instantiable

  Scenario: type stored is instantiable
    Given the module "core/api/axiom_api_session_types" is loaded
    Then type stored should be instantiable

  Scenario: type sessionId is instantiable
    Given the module "core/api/axiom_api_session_types" is loaded
    Then type sessionId should be instantiable
