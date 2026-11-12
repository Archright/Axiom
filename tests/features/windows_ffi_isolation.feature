@legacy
Feature: Windows FFI Isolation

  As an Axiom maintainer
  I want all external process calls to be cross-platform
  So that the CLI builds and runs on Windows without Unix shell assumptions

  Background:
    Given windows ffi isolation feature runner is executing

  Scenario: solver_bridge uses cross-platform command execution
    Given file src/core/solver_bridge.nim
    Then file should not contain "execShellCmd(\"cd "
    And file should not contain "&& elan run"
    And file should contain "runCommandInDir"
    When nim check is run on src/core/solver_bridge.nim
    Then all compilations should succeed

  Scenario: smoke_test uses findExe instead of Unix command -v
    Given file scripts/smoke_test.nim
    Then file should not contain "command -v ax"
    And file should contain "findExe(\"ax\")"
    When nim check is run on scripts/smoke_test.nim
    Then all compilations should succeed

  Scenario: refresh_cli_binaries uses native SHA1 instead of sha256sum
    Given file scripts/refresh_cli_binaries.nim
    Then file should not contain "sha256sum"
    And file should contain "secureHash"
    When nim check is run on scripts/refresh_cli_binaries.nim
    Then all compilations should succeed

  Scenario: shell_bridge provides runCommandInDir wrapper
    Given file src/core/shell_bridge.nim
    Then file should contain "proc runCommandInDir"
    And file should contain "proc checkToolAvailable"
    And file should contain "proc runCommandSeqInDir"
    When nim check is run on src/core/shell_bridge.nim
    Then all compilations should succeed
