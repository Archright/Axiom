Feature: Namespace Sandbox
  As the hermetic build engine
  I need Linux namespace isolation for gate execution
  So that builds are sandboxed with controlled visibility of the host filesystem and network

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: defaultNamespaceConfig has expected default values
    Given a NamespaceConfig is created with defaults
    Then mount namespace isolation is enabled
    And PID namespace isolation is enabled
    And network namespace isolation is enabled
    And the config specifies a /proc/sys/kernel/unprivileged_userns_clone check

  Scenario: isNamespaceAvailable checks unprivileged userns support
    Given the system kernel parameters are readable
    When I call isNamespaceAvailable for mount namespace
    Then the result reflects whether /proc/sys/kernel/unprivileged_userns_clone is set to 1
    And the result is consistent across repeated calls

  Scenario: namespaceExec with disabled namespaces falls back to direct exec
    Given namespace isolation is disabled in the config
    When I call namespaceExec to run a command
    Then the command executes without namespace isolation
    And the command output is captured successfully
