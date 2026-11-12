@generated @critical
Feature: monad
  # generated | src/core/trusted/monad.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/trusted/monad" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/trusted/monad" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs seal*[T], unsafeReveal*[T], `==`*[T]
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func seal*[T] is callable
    Given the module "core/trusted/monad" is loaded
    Then func seal*[T] should return a valid value

  Scenario: func unsafeReveal*[T] is callable
    Given the module "core/trusted/monad" is loaded
    Then func unsafeReveal*[T] should return a valid value

  Scenario: func `==`*[T] is callable
    Given the module "core/trusted/monad" is loaded
    Then func `==`*[T] should return a valid value
