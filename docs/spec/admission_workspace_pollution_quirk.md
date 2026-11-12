# Admission Workspace Pollution — landing gates judge TREES, never the executor CWD

**Discovered**: 2026-11-05, merge_group run 41956889390 (PR #1278 queue entry) —
the first merge_group executed against a post-VS-1 base (B carries the Filesystem
Contract V2 validator, `grep _lto_evidence` no longer takes the pre-VS-1 SKIP).

**Quirk.** The `attest` job's workspace root is a B checkout **plus the job's own
staging artifacts**: `manifest.txt` (build-base manifest step) and `_candidate/`
(the H data-only checkout). Any gate that runs a bare/CWD root-layout judgment
there — `make validate-root-layout`, or `bin/validate_root_manifest` without
`--root` — fail-closes on the job's own evidence:

```
FAIL: manifest.txt unknown
FAIL: _candidate unknown
```

This fires for EVERY queue entry regardless of the PR's content: the verdict
says nothing about the candidate tree.

**Consequence (self-referential deadlock).** The landing gate ships in the pinned
workflow chain (org `admission-gate-v2.yml` ruleset pin → `admission-check.yml`
@Axiom pin); a fix PR cannot land through the queue it fixes, and the pin
promotion system (DEBT#473) is monotonic — backward pin rotation is refused and
forward rotation requires the fix to already be on main. The only escape is a
repo/org ruleset admin edit (GitHub-audited), never `--no-verify` and never a
validator exception. The 2026-11-05 escape used exactly that: merge_queue rule
temporarily removed from the repo `main` ruleset, two direct merges under
required-check enforcement, rule restored after forward pin rotation.

**Rule.**

1. Landing gates judge **trees** — `bin/validate_root_manifest --root
   "$CANDIDATE_TREE"` — never the executor CWD. On merge_group `_candidate`
   IS the queue merge commit (H := G): the tree validated is the tree that
   lands. A base-side violation is still caught transitively, because the
   merge result contains the base's content.
2. The judge and its test battery compile from **B's tracked source** (a PR
   never grades itself with a judge it ships). The battery is sandboxed — it
   materializes synthetic trees under the system temp dir and judges them
   with `--root` — so it is CWD-safe in the polluted workspace.
3. The **bare-root verdict** (CWD judgment) belongs to surfaces that own a
   clean tree: local `make validate-root-layout` (GATES_FAST) and the
   pre-push OID snapshot (`git worktree add --detach`).

**Fix**: PR-3 — admission-check.yml root-layout step rewritten from the bare
`make` invocation to judge build + sandboxed battery + `--root` candidate
judgment. Cross-references: `docs/spec/filesystem_contract.md` §6 Enforcement
Scope (admission blocks entry, never a local write).
