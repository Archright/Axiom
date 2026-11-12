# Technical Debt Remediation — Historical Documentation

> **Status**: COMPLETE  
> **Migrated from**: `tests/features/tech_debt_remediation.feature`  
> **Date**: 2026-05-30  
> **Authority**: Plan Phase 3 — migration tracker consolidation

This document preserves the technical debt remediation BDD scenarios that
verified post-remediation invariants. These are **historical contracts**,
not active regression guards. The actual debt items are tracked in
`docs/DEBT_REGISTRY.md`.

---


Feature: Technical Debt Remediation
  As a maintainer of the Axiom codebase
  I want deterministic codebase hygiene standards
  So that architectural integrity is preserved across all modules

  Background:
    Given the Axiom codebase at HEAD

  Scenario: Core modules import SSOT constants instead of duplicating paths
    When I search for "const defaultCertDir" in src/cli/
    Then no file should define its own defaultCertDir
    And src/cli/cst_cli.nim should import core/constants
    And src/cli/certificate_cli.nim should import core/constants
    And src/cli/basic_commands_cli.nim should import core/constants
    And src/cli/report_cli.nim should import core/constants
    And src/cli/ax_heal_action_cli.nim should import core/constants

  Scenario: .physically_impure_modules accurately reflects core module purity
    When I read src/core/.physically_impure_modules
    Then it should contain "io_utils"
    And it should contain "shell_bridge"
    And it should not contain "orchestrator_types"

  Scenario: No template performs IO as computation substitute
    When I search for "template.*resolveStandardLibraryContract" in src/core/ecosystem_linkage.nim
    Then no template should perform file I/O

  Scenario: Tests use Option/Result types instead of try-except CatchableError
    When I search for "except CatchableError" in tests/integrity_check.nim
    Then no match should be found
    When I search for "except CatchableError" in tests/gateway/gateway_pipeline_test.nim
    Then no match should be found

  Scenario: Git hooks are Nim-compiled binaries with thin POSIX shims
    When I check the file type of .git/hooks/pre-commit
    Then it should be a POSIX shell script
    And it should exec scripts/gate_hook with stage "pre-commit"
    When I check scripts/gate_hook
    Then it should be a compiled ELF binary

  Scenario: declarationTags is defined once in tree_sitter_bridge.nim
    When I search for "const declarationTags" in src/core/tree_sitter_bridge.nim
    Then exactly 0 matches should be found inside function bodies
    And the module-level const declarationTags should be public

  Scenario: lakefile.toml version matches axiom.nimble version
    When I read lakefile.toml
    Then version should be "0.3.6"

  Scenario: Hardcoded localhost port uses traceInspectorPort constant
    When I search for "localhost:12345" in src/core/axiom_api.nim
    Then no match should be found

  Scenario: tests/snapshots directory exists
    When I check tests/snapshots/
    Then the directory should exist
    And it should contain README.md
  Scenario: CI workflows have been abolished in favor of local quality gates
    When I check .github/workflows/
    Then the directory should not exist

  Scenario: perfectAsi constant replaces magic string
    When I search for '"1.0000"' in src/ui/ax_tui_reporter.nim
    Then no match should be found
    And src/core/constants.nim should define perfectAsi* = "1.0000"

  Scenario: asi_cli uses atomic writePrettyJsonFile instead of raw writeFile
    When I search for "writeFile(cert.certificatePath" in src/cli/cst_cli.nim
    Then no match should be found
    And writePrettyJsonFile should be used instead

  Scenario: sorter.nim is documented as intentional facade
    When I read src/cli/sorter.nim
    Then it should contain "Facade: re-exports core/sorter_core"

  Scenario: MCP server stdout echo is documented as protocol transport
    When I read src/mcp/server.nim
    Then it should contain "stdout IS the MCP transport channel"


  Scenario: CLI output routes through structured log module
    When I read src/cli/log.nim
    Then it should define tagHeal, tagInfo, tagError, tagSuccess constants
    And it should define logStderr, logStdoutData procs

  Scenario: Log tag prefixes are centralized in src/cli/log.nim
    When I search for '"\\[heal\\]"' in src/cli/ax_heal_action_cli.nim
    Then no hardcoded tag string should be found
    And tagHeal from cli/log should be used instead

  Scenario: axiom.nimble declares checksums dependency
    When I read axiom.nimble
    Then it should contain 'requires "checksums >= 0.2.0"'

  Scenario: .gitignore exception allows bin/main and bin/ax
    When I read .gitignore
    Then it should contain "!bin/main"
    And it should contain "!bin/ax"


  Scenario: ax heal autonomous mode caps batch size to prevent unbounded batch
    When I read src/cli/commands/heal.nim
    Then it should not contain "high(int)" in batchSize assignment
    And it should contain "let batchSize = if autonomous: 50 else: healArgs.limit"

  Scenario: symbolic_cli uses requireArg helper instead of duplicated parsing
    When I search for "die(\"missing value:" in src/cli/symbolic_cli.nim
    Then no match should be found
    And requireArg from cli_io should be used for all flag value extraction

  Scenario: lean4_provider_test has meaningful assertions not check true
    When I search for "check true" in tests/unit/lean4_provider_test.nim
    Then no match should be found
    And SolverResult assertions should validate the return type


  Scenario: cli_utils module has been renamed to file_utils
    When I check src/core/file_utils.nim
    Then the file should not exist
    And src/core/file_utils.nim should exist
    And no import should reference core/cli_utils

  Scenario: No stale evidence files are tracked in git
    When I run git ls-files docs/evidence/context7/
    Then only index.md should be listed

  Scenario: No compiled gate binaries are tracked in git
    When I run git ls-files scripts/gates/
    Then only .nim source files and context7_evidence_gate should be listed


  Scenario: JsonNode field extractors live in json_utils.nim not verify_workflow_cli
    When I search for "func readRequiredJsonString" in src/cli/verify_workflow_cli.nim
    Then no match should be found
    And src/core/json_utils.nim should define readRequiredJsonString*
    And src/cli/verify_workflow_cli.nim should import core/json_utils

  Scenario: executeHealNode is decomposed into focused sub-procedures
    When I read src/cli/commands/heal.nim
    Then it should define tryStaticRuleMatch
    And it should define tryStrategyRotation
    And it should define tryLeanstralSynthesis
    And it should define analyzeBottleneck
  Scenario: Weaver stripAllGuardBlocks preserves source on unterminated markers
    When stripAllGuardBlocks encounters an AxiomGuard marker without EndAxiomGuard
    Then it preserves all lines from the marker onward instead of stripping to EOF

  Scenario: Weaver findProcBodyStartLine ignores equals inside default parameters
    When findProcBodyStartLine processes "proc foo(x: int = 5) =\n  body"
    Then it returns the body line, not the default parameter line

  Scenario: Weaver findProcBodyStartLine ignores equals inside comments and strings
    When findProcBodyStartLine processes "proc foo() # a = b\n  =\n  body"
    Then it returns the line after the actual body separator

  Scenario: Architecture gate filters known debt via baseline TOML
    Given src/gate/architecture_debt_baseline.toml contains a SOLID debt entry
    When runArchitectureGate evaluates a matching module
    Then the violation is excluded from the final fail set
    And stderr contains "[DEBT] Baseline exclusion"

  Scenario: Rebuild assets writes full symbol graph for Merkle SSOT
    When rebuild_assets persists global_symbol_graph.json
    Then the file contains schemaVersion, symbols array, and edges array
    And the file size exceeds 1000 bytes
