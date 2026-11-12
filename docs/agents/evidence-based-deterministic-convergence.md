# Evidence-Based Deterministic Convergence (EDC)

## Protocol

Every `delegate_task` MUST include a `post_condition` array of shell-checkable commands. Sub-agents call `verify_success` before terminating. The main agent checks `docs/evidence/verifications/` evidence and confirms all VERIFY entries show PASS before trusting work.

## Rationale

Without deterministic post-conditions, sub-agent work cannot be mechanically validated. EDC ensures that delegation produces observable, reproducible artifacts rather than narrative claims.

## Enforcement

- `docs/evidence/verifications/` directory is the SSOT for delegation evidence.
- Any task without `post_condition` is considered incompletely specified.
- Main agent MUST NOT proceed on trust alone; PASS entries are required.
