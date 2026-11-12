# Rename --heal-only to --heal and Remove ax recertify-lean

## Intent
The `--heal-only` flag name was verbose and inconsistent with CLI conventions.
`ax recertify-lean` was functionally redundant with `ax prove --heal`.
Consolidate both into a single `--heal` flag on `ax prove`.

## Specification
1. Rename `--heal-only` to `--heal` across all CLI surface files
2. Remove `ax recertify-lean` command and all associated types/flags/parsers
3. Update all tests and feature files to use `--heal`

## Test
- tests/gateway/cli_surface_test.nim: parses `--heal` correctly
- tests/gateway/ax_prove_heal_feature_test.nim: regression surface for `--heal`
- tests/features/ax_prove_heal.feature: BDD specification for `--heal` dispatch

## Code
- src/cli/cli_types.nim: evHealOnly → evHeal, removed RecertifyVariant/AxRecertifyLeanFlags
- src/cli/cli_surface_generated.nim: regenerated with `--heal`
- src/cli/action_plan_cli.nim: removed recertify-lean command, updated help text
- src/cli/main.nim: removed recertify_lean import/export
- src/cli/certificate_cli.nim: removed recertify-lean registry entry
- src/cli/wf_runners.nim: evHealOnly → evHeal
- src/cli/wf_render.nim: --heal-only → --heal
- src/cli/ax_workflow_shortcuts.nim: --heal-only → --heal
- src/gate/generators/cli_surface_generator.nim: --heal-only → --heal, removed AxRecertifyLeanFlags
- src/gate/generators/certified_exempt_generator.nim: removed AxRecertifyLeanFlags refs
