## Description

<!-- What does this PR do? -->

## Architecture Impact

- [ ] This PR does NOT change architecture constraints (`tests/architecture_constraints.nim`)
- [ ] This PR does NOT modify SDK interfaces
- [ ] This PR does NOT change templates
- [ ] OR: Architect-approved violation is included (link PR approval below)

## Testing

<!-- How was this tested? -->

## Merge Strategy

> Landing uses the GitHub native **MERGE commit** — merge commit enabled; rebase/squash disabled at the repository level (AGENTS.md §2 RULES & WORKFLOW; docs/agents/rules_workflow.md §2.8 Native-MERGE Landing Policy, ratified Verdict B 2026-09-10). The merge commit is 2-parent — `parent2` = PR head — and INV-1 binds `parent2 == cert.headSha` (docs/spec/certification_continuity_contract.md INV-1), so a rebase/squash would break the certified-landing invariant. Do NOT instruct contributors to rebase or squash; keep the PR head untouched so it lands as `parent2`.
>
> (Note: the previous "Rebase and Merge 전용 / main history 100% linear" claim cited "AGENTS.md §2.8", which does not exist — AGENTS.md has no §2.8; its landing policy is at §2 and rules_workflow.md §2.8 states the opposite. The repo previously used rebase-and-merge as the landing mode, superseded by the native-MERGE Verdict B.)


<!-- sha-pin-validate -->

<!-- probe/repositoryrole-write-actor: authority-first P-admission/P-surface Write-role positive probe -->
