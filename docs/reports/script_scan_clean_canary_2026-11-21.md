# Script-scan clean canary (2026-11-21)

This file is the positive control for the Unicode Script Allowlist Admission
dimension introduced by ADR-0044.

It contains only ASCII and Latin characters. When this change is armed in the
merge queue, every required check must pass and the pull request must land on
`main` through the normal queue path with a native MERGE commit.

The negative controls (PRs adding Korean, keeping Korean on an edited line, and
adding invalid UTF-8) must be rejected by the same queue. Both outcomes together
prove that the new dimension blocks violations without blocking normal English
development.
