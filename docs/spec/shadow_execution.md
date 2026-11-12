# Shadow Execution Specification

## Purpose

Shadow Execution provides a safe migration path from Python gate runners to
native Nim gate runners. It runs both implementations, compares their outputs,
and only allows removal of the Python original after semantic equivalence is
proven.

## Trigger Conditions

Shadow Execution is disabled by default to manage CI cost. It runs under one of
the following conditions:

| Mode | Trigger | Frequency |
|------|---------|-----------|
| Local | `--legacy-verify <py>` CLI flag | Developer-driven |
| PR opt-in | `AXIOM_SHADOW_GATE=1` | Per-PR |
| Targeted | Changed files include the runner source | Automatic |
| Nightly | `GITHUB_EVENT_NAME=schedule` or `CIRCLECI_EVENT=schedule` | Daily |
| Promotion | `AXIOM_SHADOW_PROMOTION=1` | Before Python removal |

## Normalization Rules

Before comparison, outputs are normalized:

1. Strip ANSI escape codes.
2. Strip trailing whitespace per line.
3. Remove empty lines.
4. Normalize absolute paths to repo-relative paths.
5. JSON output is parsed and re-serialized with sorted keys.
6. Line-oriented output may be sorted if the runner declares
   `DeterministicOutputOrder = true`.

## Equivalence Criteria

Two executions are equivalent iff:

- Exit codes are identical.
- Normalized stdout/stderr are identical.

Any semantic difference in normalized output is a failure.

## CI Integration

- Normal PR gates do **not** run Shadow Execution.
- Nightly builds run Shadow Execution for all ported runners.
- A runner may be promoted (Python removed) only after a clean Promotion-mode
  Shadow Execution pass.

## Runner Contract

Every ported Nim runner MUST:

1. Accept `--legacy-verify <path-to-python-original>`.
2. Parse the same CLI arguments as the Python original.
3. Produce semantically identical output after normalization.

## Build environment

Shadow Execution compares runners that have already been built. Compilation
happens on the host (or CI worker) using the persistent Nim cache; the
hermetic policy verifier (`bin/hermetic-build`) only executes pre-built
binaries. See `docs/spec/hermetic_build.md` for the decoupled build model.

## Tools

- `src/gate/lib/legacy_verifier.nim` — comparison engine.
- `src/gate/lib/shadow_normalize.nim` — output normalization.
- `src/gate/lib/shadow_trigger.nim` — trigger logic.
- `tools/update_exemption_registry.nim` — removes ported entries from the
  exemption registry.
