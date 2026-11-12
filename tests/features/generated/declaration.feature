@generated @critical
Feature: declaration
  # generated | src/core/topology/declaration.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/declaration" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types Subdomain, description, paths
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/declaration" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs globToRegex, globMatch, parseSubdomains, parseStringSeq, parseDomains, parseTopologyDeclarationJson, parseTopologyDeclaration, classifyFile, expectedPath, effectiveLevel, isStdlibImport, classifyImportDomain, listGhostPaths, isForwardingStub
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type Subdomain is instantiable
    Given the module "core/topology/declaration" is loaded
    Then type Subdomain should be instantiable

  Scenario: type description is instantiable
    Given the module "core/topology/declaration" is loaded
    Then type description should be instantiable

  Scenario: type paths is instantiable
    Given the module "core/topology/declaration" is loaded
    Then type paths should be instantiable

  Scenario: func globToRegex is callable
    Given the module "core/topology/declaration" is loaded
    Then func globToRegex should return a valid value

  Scenario: func globMatch is callable
    Given the module "core/topology/declaration" is loaded
    Then func globMatch should return a valid value

  Scenario: func parseSubdomains is callable
    Given the module "core/topology/declaration" is loaded
    Then func parseSubdomains should return a valid value

  # +11 more scenarios (types+funcs) omitted to stay under 50 lines
