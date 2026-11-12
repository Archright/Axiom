@generated @medium
Feature: convergence_sidecar
  # generated | src/cli/convergence_sidecar.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/convergence_sidecar" is loaded
    Then all exported types should be instantiable
