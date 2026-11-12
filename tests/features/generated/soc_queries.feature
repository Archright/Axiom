@generated @high
Feature: soc_queries
  # generated | src/gate/nimtry/soc_queries.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/soc_queries" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types DomainLayout, domains, domainPaths
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/soc_queries" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type DomainLayout is instantiable
    Given the module "gate/nimtry/soc_queries" is loaded
    Then type DomainLayout should be instantiable

  Scenario: type domains is instantiable
    Given the module "gate/nimtry/soc_queries" is loaded
    Then type domains should be instantiable

  Scenario: type domainPaths is instantiable
    Given the module "gate/nimtry/soc_queries" is loaded
    Then type domainPaths should be instantiable

  Scenario: func domainForPath is callable
    Given the module "gate/nimtry/soc_queries" is loaded
    Then func domainForPath should return a valid value

  Scenario: func registerSocQueries is callable
    Given the module "gate/nimtry/soc_queries" is loaded
    Then func registerSocQueries should return a valid value
