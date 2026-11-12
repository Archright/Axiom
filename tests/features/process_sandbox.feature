Feature: Process Sandbox — 6-Namespace Complete Isolation
  As the hermetic build engine
  I want Linux namespace isolation for gate execution
  So that gate runners execute in a fully isolated environment

  Background:
    Given the process_sandbox module is available
    And the system runs Linux 5.6 or newer

  Scenario: sandboxFlags combines all 6 namespace flags
    When sandboxFlags is called
    Then the result includes CLONE_NEWNS for mount isolation
    And the result includes CLONE_NEWNET for network isolation
    And the result includes CLONE_NEWPID for PID isolation
    And the result includes CLONE_NEWIPC for IPC isolation
    And the result includes CLONE_NEWUTS for UTS isolation
    And the result includes CLONE_NEWTIME for time isolation

  Scenario: applySandbox returns sandboxed=true on supported kernel
    Given a SandboxConfig with default values
    When applySandbox is called in a forked child process
    Then the result has sandboxed=true

  Scenario: applySandbox falls back gracefully on old kernel
    Given a SandboxConfig on a kernel older than 5.6
    When applySandbox is called in a forked child process
    Then the result has sandboxed=true with 5-namespace isolation
    And a warning is written to stderr about CLONE_NEWTIME unavailability

  Scenario: canSandbox detects namespace support
    When canSandbox is called
    Then the result reflects whether unshare(CLONE_NEWNS) succeeds
    And the result is consistent with /proc/sys/kernel/unprivileged_userns_clone

  Scenario: execSandboxed applies isolation before exec
    Given a SandboxConfig with projectRoot set
    When execSandboxed is called with a test executable
    Then namespace isolation is applied before execvp
    And the executable runs in an isolated environment
