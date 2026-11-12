# 2026-06-02 Topology CLI Diagnosis Helper Cleanup

## Intent

Remove the dead `diagnosisTargetIds` helper from `src/cli/topology_cli.nim` as a follow-up to the topology split/refactor wave. The helper had no live callers and caused `nim check` to report an unused declaration.

## Changes

- `src/cli/topology_cli.nim`: deleted `diagnosisTargetIds`, which was no longer referenced after the topology split/refactor wave.
- Verified `nim check -p:src src/cli/topology_cli.nim` succeeds after the deletion.
- Commit: `68f06bec fix(cli): remove dead topology diagnosis helper`

## Relation

- This is a follow-up cleanup to the `1dc0eed` compile-cleanup wave that carried the `DEBT#105` remediation message.
- The registry entry for `DEBT#105` in `docs/DEBT_REGISTRY.md` remains reserved for the deleted test stub; this note documents the leftover helper that surfaced during the same cleanup wave.

## Restoration Risk

Low. If a future topology diagnosis caller is reintroduced, the helper should be restored together with a live call site and an updated diagnosis flow.

## SSOT Authority

- AGENTS.md §2.1, Annals Write-Back
- AGENTS.md §0.6, Static First Enforcement
- `docs/history/test-deletion-registry.md` for the deletion-record pattern
