# Capability-delta record — nph config parsing (B-SEC-01, facets i+ii)

**Claim recorded here**: at the deployed consumer (`arnetheduck/nph`
@ `2cacf6cc28116e4046e0b67a13545af5c4e756bd`, consuming
`toml_serialization` 0.2.18-76ae1c2a), the two B-1 defects are **reachable**
through the real `.nph.toml` path but confer **no capability beyond a valid
config** — every defect-input behavior is exactly reproducible by a VALID
TOML file. Baseline (no config) is likewise indistinguishable except through
fields a valid config controls anyway (`color`).

Establishing prior run: `/tmp/capdelta/` (nph clone @ 2cacf6cc + `exp/run_tests.sh`,
snapshotted to `earlier_run_snapshot/run_tests.sh`; nph-action clone snapshotted to
`earlier_run_snapshot/nph-action_action.yml`). This record **re-verifies** that
run with a fresh GitHub clone and byte-recorded evidence in
`../link_b_consumer/raw/` (case ids C0–C12 below).

## 1. Dead-code re-verification (protected boundary, source level)

`src/nph.nim` @ 2cacf6cc, fresh clone `/tmp/bsec_consumer/nph`:

- `:429` — `if file in explicitFiles or matchesFilters(file, compiledPatterns):`
- `:327-330` — directory-walked files → `explicitFiles.add(file)`;
  `:334` — explicitly passed files → `explicitFiles.add(f)`;
  `:370` — stdin → `explicitFiles.add(f)`. **Every** infile source inserts
  into `explicitFiles`, so the left disjunct is always true and Nim's
  short-circuit guarantees `matchesFilters` is **never evaluated**.
- `:404-424` — `exclude` / `extend-exclude` / `include` are consumed only to
  build `compiledPatterns`; `matchesFilters` (`:132`) has exactly one call
  site (`:429`). ⇒ the three pattern fields are **dead code** at this
  revision: no behavior channel exists for them at all.
- `:384-385` — `config.color` is **live**: it overrides the TTY/NO_COLOR
  default, and only affects `--diff` output.

This matches the establishing run's static claim (nph v0.6.2 `nph_v062.nim` /
v0.7.0 `nph_v070.nim` extracted sources in `/tmp/capdelta/` show the same
`explicitFiles`-always-populated structure at both deployed versions).

## 2. Three-way comparison per defect (exact nph observations)

Fixture per case: `a.nim` (needs reformat), `b.nims` (unparseable → nph skips
it), `sub/b.nim` (needs reformat), `ok.nim` (already formatted), `c.txt`
(non-Nim). Full bytes: `../link_b_consumer/raw/<case>/`.

### 2.1 B-SEC-01 facet (i) — duplicate keys, dead-field instance

| Arm | `.nph.toml` | nph observation (exact) |
|---|---|---|
| **defect** (C1) | `exclude = ["XXXX_never_matches"]` + `exclude = [".*"]` | exit 3 (fixture b.nims, uniform); **no config warning**; would-reformat listing ≡ baseline |
| **valid contrast** (C2) | `exclude = [".*"]` | byte-identical behavior to C1 |
| **baseline** (C0) | (none) | byte-identical behavior to C1/C2 |

Decisive detail: `exclude = [".*"]` would exclude every file **if the filter
were live** (→ `[Error] no input file.`, no listing). Observed: identical
listing to baseline in all three arms ⇒ field never evaluated ⇒ the
duplicate-key acceptance on this field has **zero** behavioral delta — and so
does the field itself.

### 2.2 B-SEC-01 facet (i) — duplicate keys, live-field instance (`color`)

| Arm | `.nph.toml` | `--diff` stdout (exact) |
|---|---|---|
| **defect** (C3) | `color = true` + `color = false` | no ANSI; **byte-identical to C4** |
| **valid contrast** (C4) | `color = false` | no ANSI |
| **defect** (C5) | `color = false` + `color = true` | ANSI present; **byte-identical to C6** |
| **valid contrast** (C6) | `color = true` | ANSI present |

The one live field applies the duplicate last-wins (defect i) — but the
resulting state (`true` or `false`) is exactly what a single-line valid
config produces. No third state exists: `Option[bool]` has only none/true/false.

### 2.3 B-SEC-01 facet (ii) — early break → trailing spec-invalid input skipped

| Arm | `.nph.toml` | nph observation (exact) |
|---|---|---|
| **defect** (C7) | 4 distinct fields, then `!!!` ⏎ `[[attacker_table]]` ⏎ `some = "garbage"` | **no config warning**; `--diff` output byte-identical to C8 (ANSI present) |
| **valid contrast** (C8) | same 4 fields, document ends after `color = true` | byte-identical stdout/stderr to C7 |
| **baseline** (C12) | (none) | same formatted-tree outcome as C7/C8 in-place |
| boundary (C10b) | 3 distinct fields + `!!!` | `Warning: Failed to parse config file: .nph.toml ((4, 1) illegal character "!")` → **rejected** |
| warning-path control (C9) | `this is [[ not toml` | `Warning: … ((1, 6) expected "=")` — the rejection channel exists and fires |

C10b proves the mechanism: with a field unfilled, the trailing bytes ARE
reached and rejected; in C7 the early break (`fieldsDone >= totalFields`,
reader.nim:326-327 of the consumed 0.2.18) skipped them.

### 2.4 In-place combined (which files get touched)

C10 (defect(i)+(ii): dup `exclude`, all 4 distinct fields, trailing `!!!`) ≡
C11 (valid) ≡ C12 (baseline): identical `nimfiles_after.txt` manifests —
`a.nim` `03b6a60a…→bda43b82…`, `sub/b.nim` `dd847f5a…→b02b19de…`;
`ok.nim`/`b.nims`/`c.txt`/`.nph.toml` untouched. The defect config's touched-file
set and resulting bytes equal the valid config's and the baseline's.

## 3. Structural equivalence (not version-dependent)

`NphConfig` fields are **plain overwrites** with no cross-field or
accumulation semantics (`src/nph.nim:20-25`: `seq[string]` ×3 replaced
wholesale, `Option[bool]` set at most once):

- **duplicate-key last-wins ≡ valid config with only the last value.**
  Rejecting the duplicates or accepting them with last-wins yields the same
  `NphConfig` value whenever the duplicates are byte-identical (B-1 scope) —
  and for the config data model the value is all that exists (no side
  channel: the pattern fields are dead, `color` is a 3-valued overwrite).
- **trailing-skip ≡ the same config without the trailing bytes.**
  Decoding stops after the last consumed field; the resulting `NphConfig` is
  the prefix value. A parser that validated the whole document (spec-
  conforming) would reject; the deployed one accepts — but the accepted state
  is identical to the valid truncated document's state.

These equivalences depend only on the config **data model** (plain
overwrites), not on the defect persisting in any particular toml_serialization
version. Any consumer whose bound type has only plain-overwrite fields and no
post-decode validation of unbound content inherits the same equivalence.

## 4. Protected-boundary findings

From `earlier_run_snapshot/nph-action_action.yml` (verbatim copy of
`arnetheduck/nph-action@v1` `action.yml` @ the earlier run's clone):

- `:42-49` — the "nph" step runs `./nph ${{inputs.options}}` (default `.`)
  **on the PR checkout**. The tree nph formats **is the attacker's own PR
  content** — an attacker who can write `.nph.toml` can already write the
  Nim sources nph reformats; nothing the formatter reads from config
  elevates this.
- `:58-64` — the "View diff" step uses **`git diff --exit-code || exit 1`**
  (fail=true default) — it never invokes `nph --diff`, so the only live
  config field, `color` (ANSI for `--diff`), is **inert** in the protected
  pipeline. reviewdog/action-suggester (`:51-56`) likewise consumes
  `git diff`, not nph's colored stream.
- **No adopter has CODEOWNERS** (establishing-run finding; scope: adopters
  surveyed by that run. The nph repository itself was re-verified here:
  `git ls-files | grep -i codeowners` → empty in the fresh 2cacf6cc clone).

Consequently the only security-relevant judgment surface of the pipeline is
"does `git diff` (post-format) become non-empty", and the content judged is
the attacker's own PR tree.

## 5. Conclusion recorded (no severity assessment)

| Defect | Reaches nph? | Capability beyond a valid config? |
|---|---|---|
| B-SEC-01 facet (i) duplicate keys | yes (C1/C3/C5) | **none** — §2.1/§2.2/§3 |
| B-SEC-01 facet (ii) trailing skip | yes (C7/C10) | **none** — §2.3/§2.4/§3 |

Every (defect input / valid contrast / baseline) triple observed in this
campaign produced byte-identical externally visible behavior. No CVSS score,
severity judgment, or upstream issue is filed here or elsewhere.
