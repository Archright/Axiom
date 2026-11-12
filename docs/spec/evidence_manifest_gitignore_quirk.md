# Evidence-manifest gitignore quirk (SHA256SUMS over disk set ≠ committed set)

Status: documented 2026-11-02 (discovered while verifying the landing of the
③ u64 slice closure PR #1178: 8 evidence artifacts were silently dropped;
fixed by the follow-up rename commit; OBSERVATION.md §3-d records the
correction).

## 1. Symptom

An experiment closure commit added `experiments/<slice>/` with
`git add experiments/<slice>`, and the evidence manifest (SHA256SUMS) had
been generated over the DISK file set. After the merge, `git ls-tree -r
<merge-sha> --name-only -- experiments/<slice>` counted 49 files while the
directory held 57: `.gitignore` patterns `*.log` (L113), `*.sh` (L143),
`*.diff` (L238) had silently excluded 8 evidence artifacts — and the
committed SHA256SUMS still referenced them. In a fresh clone,
`sha256sum -c SHA256SUMS` fails; the evidence set is not independently
verifiable.

## 2. Root Cause

`git add <dir>` skips gitignored files without failing (documented git
behavior — not an error). A manifest generated from the disk set therefore
describes a SUPERSET of the committed set whenever any artifact matches a
global ignore pattern. Repo history holds two conventions: the act2-*
experiments force-added `.log`/`.sh` evidence; the ④①② slices renamed all
evidence artifacts to `.txt` so the patterns never apply.

## 3. Correct pattern

- Slice convention (preferred): name evidence artifacts `.txt`
  (`runner_verbatim.txt`, `make_build.txt`, `run_A.stderr.txt`, …) — the
  global ignore patterns then never apply. Force-adding (`git add -f`) is
  the act2-era alternative; do not mix silently.
- Generate SHA256SUMS AFTER the final name set is fixed.
- After the closure merge, VERIFY the committed set equals the manifest:
  `git ls-tree -r <merge-sha> --name-only -- experiments/<slice>` must
  list exactly the manifest entries plus the manifest files themselves.
- Treat a manifest that references non-repo files as an evidence-integrity
  defect requiring a correction commit — never as cosmetic.

## 4. Observed environment

git 2.43.0 (Ubuntu), Axiom4, PR #1178 (merge `da7e52e5ad18…`), 2026-11-02.

Recurrence 2026-11-03: the node24 merge-queue critical-path census landing
(PR #1232, `34540935180e…`) dropped `data/ci_provider/census_20261103T025821Z/analyze.py`
via `.gitignore:142` (`*.py`) — the landed `manifest.json` files section and the
report §9 reproduction command referenced it. Correction commit force-added the
script (act2-era alternative: the file is executable reproduction
infrastructure, not a log — renaming to `.txt` would break `python3 analyze.py`).
Post-landing check that catches this class: `ls <data-dir> | wc -l` vs
`git ls-tree origin/main <data-dir> | wc -l`.
