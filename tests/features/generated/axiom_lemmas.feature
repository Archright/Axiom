@generated @critical
Feature: axiom_lemmas
  # generated | src/core/proof/axiom_lemmas.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/proof/axiom_lemmas" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types LemmaCategory, LemmaMapping, lemmaId, nimPattern, leanStatement, smtPattern, category, verified
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/proof/axiom_lemmas" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs findLemmaByName, findLemmasForPattern, findLemmasByCategory
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type LemmaCategory is instantiable
    Given the module "core/proof/axiom_lemmas" is loaded
    Then type LemmaCategory should be instantiable

  Scenario: type LemmaMapping is instantiable
    Given the module "core/proof/axiom_lemmas" is loaded
    Then type LemmaMapping should be instantiable

  Scenario: type lemmaId is instantiable
    Given the module "core/proof/axiom_lemmas" is loaded
    Then type lemmaId should be instantiable

  Scenario: type nimPattern is instantiable
    Given the module "core/proof/axiom_lemmas" is loaded
    Then type nimPattern should be instantiable

  Scenario: type leanStatement is instantiable
    Given the module "core/proof/axiom_lemmas" is loaded
    Then type leanStatement should be instantiable

  Scenario: type smtPattern is instantiable
    Given the module "core/proof/axiom_lemmas" is loaded
    Then type smtPattern should be instantiable

  # +5 more scenarios (types+funcs) omitted to stay under 50 lines
