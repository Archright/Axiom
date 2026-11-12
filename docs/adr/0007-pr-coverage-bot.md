# ADR-0007: PR Coverage Bot

## Status
Accepted

## Context
Pull requests introducing new code often bypass verification gates. Without automated enforcement, unverified changes accumulate in the main branch over time. Manual code review cannot reliably catch missing tests or skipped gate runs, especially in large PRs.

## Decision
Deploy an automated bot that reviews every pull request for gate coverage. The bot checks that all changed files have corresponding gate executions recorded in the receipt log. If a PR modifies code without running relevant gates, the bot comments requesting the author to run `axiom-gate` locally before merging.

## Consequences
- Every merged PR has verified gate coverage, maintaining the integrity invariant.
- Authors get immediate feedback before merge, reducing rework cycles.
- Bot is non-blocking — it comments rather than blocks CI, allowing architect override.
- Coverage metrics feed into dashboards showing project health trends over time.
