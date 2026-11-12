@legacy
Feature: Public API Boundary and Package Entrypoints
  As an external Nim consumer
  I want to import the verification loop through stable api modules
  So that I can control the engine without bypassing the core integrity boundary

  Scenario: package exposes explicit verification loop entrypoints
    Given the repository is installed as a Nimble package
    When an external project imports the public API boundary
    Then the import path must resolve through "src/api/"
    And the top-level package entrypoint must allow "import api"
    And the repository consumer fixture must avoid direct "core/" imports for orchestration execution
    And the repository consumer fixture must compile through the top-level api package
    And the executable repository fixture must run a deterministic empty verification loop through the top-level api package
    And the API must expose typed constructors for sorter state and proof requests
    And the API must expose typed node-id helpers through the same public boundary
    And the API must expose a verification loop executor without mutating core purity contracts

  Scenario: core modules remain library-importable after packaging
    Given the package uses "src" as its Nim source root
    When an external project imports core modules directly for read-only integration
    Then src/core modules must remain importable as package modules
    And the public API boundary must stay explicit for orchestration execution