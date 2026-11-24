# libpcre3 Supply Ordering - Immutable Asset Ahead of apt (2026-11-24)

> Status: execution-path change record for `libpcre3` provisioning inside
> `.github/actions/setup-axiom-toolchain/action.yml`.
> Base: `dea3cce0` (`origin/main`)
> Precedent: `docs/evidence/supply_policy_registration_2026-11-19.md`
> (`supply-pins-libpcre3-8.39-15build1`)

## 1. What changed

The `Install system deps (canonical system_deps parity — libpcre3)` step already
carried a five-tier supply ladder. This change reorders it, and changes how the
pinned payload is materialized:

| Tier | Before | After |
|---|---|---|
| 0 | `ldconfig` hit → skip | unchanged |
| 1 | `apt-get install libpcre3=$VERSION` (+ `update` retry) | **pinned release asset** → verify → `dpkg-deb -x /` → `ldconfig` |
| 2 | pinned release asset → `dpkg -i` | the same pinned asset through `dpkg -i` |
| 3 | ordered mirrors | `apt-get install libpcre3=$VERSION` (+ `update` retry) |
| 4 | `external_dependency` fail-closed | ordered mirrors, unchanged |
| 5 | — | `external_dependency` fail-closed, unchanged |

`verify_pinned_deb` (sha256 + Package + Version + Architecture), the tier-0
guard, the mirror tier, the final `ldconfig -p | grep 'libpcre\.so\.3'`
assertion and the fail-closed abort are all unchanged. Tier 1 additionally
asserts its own postcondition before reporting success, so an extraction that
does not make the soname visible falls through to tier 2 instead of masking a
failure.

Two supporting edits:

1. `install_pinned_deb` runs `sudo dpkg -i "$1"` instead of
   `sudo apt-get install -y -qq "$1"`. The argument must stay quoted: an
   unexpanded glob exits 2 with `cannot access archive`.
2. A best-effort `systemctl stop` + `mask` for `apt-daily.service`,
   `apt-daily-upgrade.service` and `unattended-upgrades.service` runs before the
   ladder. Each unit's outcome is logged; no outcome aborts the step.

## 1a. Why tier 1 skips dpkg

`dpkg -i` is not cheap enough. It unpacks in 0.08 s, but it also reads its
216,720-entry database (~6 s) and runs the `libc-bin` trigger (~7 s) on every
job. Five jobs × ~13 s leaves the critical path short of its floor: measured
on-path cost 126 s, available headroom 85 s, so admission-gate would land near
401 s instead of the 377 s the floor allows.

Tier 1 therefore treats the archive as what it is — a payload:

- `Depends: libc6 (>= 2.34)` is the only dependency and is already satisfied, so
  a resolver has nothing to decide.
- No `Conffiles` and no maintainer scripts, so nothing but the two shared
  objects and their symlinks needs to land.
- The package's one trigger, `activate-noawait ldconfig`, is reproduced by the
  explicit `ldconfig` call.

The payload is staged and copied into `/usr/lib/x86_64-linux-gnu` — a default
ldconfig search path, listed in `/etc/ld.so.conf.d`. Extracting into a *private*
directory does not work and is not attempted: `LD_LIBRARY_PATH` is not an
ldconfig input, and `ldconfig -n` does not rewrite `/etc/ld.so.cache`.
Extracting **onto `/`** does not work either — see the merged-usr hazard in §3.

Measured on this tree: `dpkg-deb -x` of the pinned archive 0.01–0.02 s, full
cache rebuild (`ldconfig -C`) 0.05–0.19 s.

## 2. Measured basis

One merge group, one step, five jobs — `merge_group dea3cce0`,
`admission-gate` run `45346019458` (`duration_ms` from the step itself):

| job | duration |
|---|---|
| `attest / admission-check` | 6,915 ms |
| `mint-prepare / prepare` | 32,0xx ms |
| `mint-publish / publish` | 16,0xx ms |
| `build-base-artifacts` | 36,832 ms |
| `go-critical-lane (1)` | 34,266 ms |

A 5.3x spread around 0.08 s of actual install work (`Setting up libpcre3` in the
`mint-prepare` log). The package is 248,274 bytes. Inside the slowest sample:

```
07:16:34.49  step start
07:16:55.11  Selecting previously unselected package   (20.6 s of silence)
07:17:01.62  (Reading database ... 216720 files)       (6.3 s)
07:17:01.70  Setting up libpcre3                       (0.08 s)
```

The silence is `apt-get`'s dependency resolution plus the
`DPkg::Lock::Timeout=300` budget being spent against a frontend lock held by the
image's own `unattended-upgrades` boot timer. `dpkg -i` performs no resolution
and has no wait budget, and the pre-ladder suppression removes the holder.

## 3. Equivalence evidence

- `Depends: libc6 (>= 2.34)` — the only dependency. `Pre-Depends` and
  `Recommends` are absent, so a resolver has nothing to decide.
- No `Conffiles`, no maintainer scripts, so `--force-conf*` is irrelevant.
- The archive contains exactly two shared objects and their soname symlinks;
  `dpkg-deb -c` lists no other payload.
- The `activate-noawait ldconfig` trigger is processed by bare `dpkg -i`
  (verified in an isolated `--admindir`: `Processing triggers for libc-bin …
  ARG1=triggered ARG2=ldconfig`), and tier 1 reproduces it with an explicit
  `ldconfig`.
- Reinstalling the same version exits 0 under both installers.
- `ldconfig` indexes an extracted soname: building a private cache over an
  extracted tree yields
  `libpcre.so.3 (libc6,x86-64) => <tree>/lib/x86_64-linux-gnu/libpcre.so.3`,
  and `dlopen("libpcre.so.3")` against it returns `LOADED`.
- The archive itself is unchanged and still pin-verified (`sha256
  62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43`,
  248,274 bytes, `libpcre3 2:8.39-15build1 amd64`).

### Merged-usr hazard (observed in CI, then fixed)

The archive ships a real `./lib/x86_64-linux-gnu/` directory, and Ubuntu 24.04
is merged-usr: `/lib` is a symlink to `usr/lib`. Extracting the archive **onto
`/`** therefore replaces that symlink with a real directory, hiding
`/usr/lib/x86_64-linux-gnu/libm.so.6`. The first CI attempt did exactly this
and three jobs died with:

```
/usr/bin/ld: cannot find /lib/x86_64-linux-gnu/libm.so.6: No such file or directory
/usr/bin/ld: cannot find /lib/x86_64-linux-gnu/libmvec.so.1: No such file or directory
```

The extraction path is therefore staged: unpack into `$work/root`, then
`cp -a` only the four payload members (`libpcre.so.3.13.3`, `libpcre.so.3`,
`libpcreposix.so.3.13.3`, `libpcreposix.so.3`) into
`/usr/lib/x86_64-linux-gnu`. `cp -a` preserves the two soname symlinks as
symlinks rather than dereferencing them.

Two assertions make the hazard non-recurring:

- each payload member must be present in the staged tree, else the tier fails;
- after the copy, `<real>/libm.so.6` must still exist. If a future archive
  layout ever displaces a system library again, the step fails loudly instead of
  succeeding and breaking every later link.

Verified locally against a fake real-directory carrying a canary `libm.so.6`:
the four members land with both symlinks intact, the canary is unchanged, the
ldconfig postcondition holds, and `dlopen` reports `LOADED`.

This equivalence holds **for this package only**. `verify_pinned_deb` pins
Version and Architecture, so a pin bump re-opens the review, and an archive that
grows maintainer scripts or conffiles would invalidate tier 1.

### Failure semantics

Tier 1 asserts `ldconfig -p | grep 'libpcre\.so\.3'` before returning success; if
the loader still cannot see the soname, the ladder falls through to tier 2
(`dpkg -i`) and then to apt. `dpkg` has no lock-wait option, so a held frontend
lock makes tier 2 exit 2 immediately and the ladder falls to tier 3, where the
300 s budget is a retry allowance rather than the critical path. Nothing is
swallowed: the only terminal state is a successful tier or an
`external_dependency` exit 1, and the step ends with the same ldconfig
assertion it always had.

## 4. Runtime requirement is real

`libpcre.so.3` is not statically linked. `bin/ax` declares only `libm.so.6` and
`libc.so.6` in `DT_NEEDED`; the Nim `re` module reaches the library through
`dlopen` (`wrappers/pcre.nim` requests `libpcre.so(.3|.1|)`), and
`admission-check` run `35949574909` failed with `could not load:
libpcre.so(.3|.1|)`. Provisioning therefore cannot be removed by linking
differently — only by making it cheap.

The runner image does not ship the package (`toolset-2404.json` lists it in no
section), so the tier-0 guard cannot be relied on.

## 5. Known cost of landing this change

`script_hash = sha256(.github/actions/setup-axiom-toolchain/action.yml +
nimble.lock)` is a component of the A-layer cache key. Editing `action.yml`
therefore invalidates every A-layer key exactly once: the landing PR runs cold
on all consumers, and any latency measured on the landing PR is a regression by
construction. The benefit begins with the next merge-group run.

## 6. Expected recovery, and its bound

An independent cost ledger over five merge-group runs (`45346019458`,
`45344816547`, `45343731589`, `45342645873`, `45341004919`) splits the on-path
cost into phases and re-binds the saving to the new terminal job:

| scenario | on-path saving (realized) | resulting wall | share |
|---|---|---|---|
| apt phase only removed | 55.7 – 113.8 s | 382 – 437 s | 12.3 – 20.7 % |
| whole step removed | 98.4 – 162.7 s | 332 – 388 s | 21.8 – 29.5 % |

On the audited run the split is `S1a 79.772 s` (apt alone → 382.228 s) versus
`S1b 130.099 s` (step gone → 331.901 s), with the residual 50.327 s being dpkg's
own work: `dbread 22.182 s` + `postinst 27.211 s` + `unpack 0.815 s` +
`prep 0.112 s`.

Tier 1 removes the whole step, not just the apt phase, because it never invokes
`dpkg` at all — it stages the payload and copies four members. That places the
expected outcome above the S1a band and below the S1b band — see §6a for the
correction that keeps this from overstating the saving.

### 6a. Correction — tier 1 is cheap, not free

S1b models the step as **gone**. Tier 1 does not remove it; it replaces a
dpkg-driven path with a short one. Measured on the head commit (§9.2), the nine
jobs that materialized the payload through tier 1 took 0.96 – 8.6 s, median ≈ 7.9 s.
Treating the step as zero would overstate the saving by roughly five calls ×
7 s ≈ 35 s.

The honest expectation is therefore **between** the two bands:

| bound | derivation | wall |
|---|---|---|
| S1b (upper bound, not achievable) | step removed entirely | 331.9 s |
| realistic | 130.099 s − (5 × ≈7 s) | ≈ 357 – 370 s |
| S1a (lower bound, superseded) | apt phase only removed | 382.2 s |

The acceptance threshold stays at ≤ 377 s, which the realistic band clears with
margin but not with the S1b margin. Landing, not arithmetic, decides it.

## 7. Remote-SHA pins that this change does not reach

Three call sites pin the action by commit SHA rather than resolving the local
path, so they keep the old ladder until the pin moves:

```
.github/workflows/admission-gate-v2.yml:285   @c021c338…   job: closure-deriver
.github/workflows/ci-cache-publisher.yml:411  @ba51c8d7…   (2 sites, same SHA)
```

`closure-deriver` is not on the measured admission chain (it completes well
before the spine), and `ci-cache-publisher` is not a required context. Moving
these pins is a separate change: it alters protected workflow bytes and would
rotate the A-layer key a second time for no measured gain in this slice.

A fourth site, `.github/workflows/admission-check.yml:889`, duplicates the apt
ladder inline for the landing-verdict venue, pinned only as `libpcre3` with no
version. It is a distinct defect (unpinned supply on the verdict path) and is
recorded here rather than fixed, because that file is a manifest path and mixing
an unpinned-supply fix into a latency change would make neither attributable.

## 8. Authority

`.github/actions/setup-axiom-toolchain/action.yml` is path 0 of 18 in
`config/policy/trust_surface_manifest.json`, which the independent verifier
compares blob-for-blob between G and `B_mg`. The manifest requires the audited
break-glass lane for such a change. `config/repository_surface.json` is a
registration of the same path and is itself a manifest entry, so no separate
surface-policy amendment is possible or useful here.## 9. CI epoch record (AGENTS.md §2.5)

This change edits the shared toolchain action that every workflow executes, so it
is a CI change regardless of size and follows the cutover protocol in
`docs/agents/ci_epoch_cutover.md` rather than an in-place patch.

### 9.1 Freeze

| item | value |
|---|---|
| freeze tag | `ci-frozen-2026-11-24-pcre-supply` (annotated, pushed to origin) |
| tag → commit | `dea3cce064c570a4738d11470d62fbe44d62be13` — main before this cutover |
| frozen `action.yml` blob | `d01432f6dde45cfe7ff101f8494387fe79cb4621` (old ladder) |
| rollback reference | the tag above; nothing else is needed to restore the previous execution surface |

The tag is the rollback reference required by protocol step 10. It is not a
gate exemption and carries no authority.

### 9.2 Record — what the pre-cutover epoch charges per job

Measured on the head commit `85550955…` of this PR, by reading each job's
composite-action step markers rather than inferring from job wall time:

| job (required context marked) | action revision executed | supply tier | step wall |
|---|---|---|---|
| `tests-ci-unit-diagnostic` | head | 1 (extract) | 5.505 s |
| `verify-trusted-writer-set` | head | 1 (extract) | 6.574 s |
| `secret-scan` | head | 1 (extract) | 6.999 s |
| `fresh-prove-observation` | head | 1 (extract) | 7.285 s |
| `debt-registry-gate` ★ | head | 1 (extract) | 7.904 s |
| `repository-surface` | head | 1 (extract) | 8.592 s |
| `axiom-operational-slice` ★ | head | 1 (extract) | 8.048 s |
| `publication-integrity` ★ | head | 1 (extract) | 0.959 s |
| `readiness-verdict` ★ | head | 1 (extract) | 8.1 s |
| `generation-acceptance` ★ | base | old ladder | 36.387 s |
| `observe` | base | old ladder | 23.129 s |
| `closure-deriver` | pinned `c021c338…` | old ladder | 30.429 s |
| `attest / build-base-artifacts` | base | old ladder | 30.295 s |
| `attest / admission-independents` | base | old ladder | 31.110 s |
| `attest / admission-check` | base | old ladder | 39.611 s |

Tier 1 succeeded on **9 of 9** jobs that executed the head revision; no job fell
through to tier 2, tier 3, or `external_dependency`, and none hit the tier-0
guard either — every one of the nine materialized the payload.

The 0.959 s entry is the same tier-1 path, not a skip, on a runner whose payload
fetch was fast. The log does not distinguish download from `ldconfig` cost, so
the reason for the spread (0.96 – 8.6 s) is recorded as unexplained rather than
assumed; the acceptance cohort in §9.6 re-measures it.

### 9.3 Why nine jobs still show the old ladder

ADR-0021 requires the execution surface to be read from the trusted base tree,
never from the candidate. Each of the nine reads the action from a **checked-out
base tree**, by one of two mechanisms:

- `generation-acceptance.yml:94` and `observation.yml:36` check out
  `merge_group.base_sha || pull_request.base.sha` into the workspace root and
  then resolve `./.github/actions/setup-axiom-toolchain` from it.
- `admission-check.yml:277` does the same with `inputs.baseSha` for the
  `attest/*` jobs and the verdict leg, and `certificate-mint.yml:1326` does it
  with `inputs.baseSha` for both mint jobs.

The ninth, `closure-deriver`, is the remote-SHA pin from §7 — a different
mechanism, not part of this propagation path.

Because `B` on this PR is `dea3cce0…`, those jobs executed the **pre-cutover**
revision. This is the propagation path rather than a coverage gap: on the first
merge-group run whose base is post-cutover main, they inherit the new ladder
with no further change.

It also bounds the blast radius. A tier-1 failure is not swallowed — it falls
through to `dpkg -i`, then apt, which is exactly what production runs today. The
worst case for a base-tree job is therefore today's latency, not a broken job.

The three remote-SHA pins in §7 are a different mechanism entirely: they resolve
the action from the repository at a pinned commit and are not reached by this
change at all.

### 9.4 Atomic binding update

Protocol step 5 requires workflow bytes and their trust bindings to move as one
unit. This cutover moves the action blob `d01432f6…` → `fe590d1d…` and changes
**no** binding, because no reachable binding consumes that blob:

- `config/executor_authority.json` lists six action blobs as the
  TrustedExecutorSet, but `EXECUTOR_MISMATCH` has zero occurrences under
  `.github/`, `src/`, `bin/`, and `tools/` — the enforcement that ADR-0021 D7
  describes is not wired anywhere, and the set has been stale since
  `eb48f902…` (main's blob has been `d01432f6…` for several generations).
  Rotating a set nothing reads would be theater, so this record states the fact
  instead of performing an update that changes no behaviour.
- `config/trusted_writer_set.json`'s `trustedCheckerTreeClosure` covers the Nim
  checker closure, not `action.yml`; `trustedAdmissionWorkflowSha` pins
  `admission-check.yml`, which this PR does not touch. `epoch_manifest.json`'s
  `productionExecutionPin` is likewise unchanged.
- The A-layer cache key includes `script_hash = sha256(action.yml + nimble.lock)`,
  so the key rotates exactly once, by construction, with no manual re-anchor.

### 9.5 Tombstone

The retired implementation is the apt-first ladder: `apt-get install` as the
primary path with the pinned asset demoted behind it. Nothing is removed from
the gate surface — all six tiers remain reachable, the pinned-asset
verification is unchanged, and `external_dependency` still fails closed when
every tier fails. No required check, producer identity, or trust condition is
retired by this cutover.

### 9.6 Cutover and acceptance

Cutover is the break-glass merge of PR #450 (see §8 for why the App verdict must
be `failure` here: the manifest is read from `B_mg`, so a passing verdict would
mean it had been read from the candidate's own tree).

Acceptance is a separate observation, recorded after landing:

1. merge-group cohort with `base_sha` at or after the cutover commit, n ≥ 5;
2. `admission-gate` wall ≤ 377 s and the tier census above re-run on those runs,
   with `generation-acceptance` and `observe` now showing tier 1;
3. the seven required contexts still mapped to App `5795152` +
   `15368`, verdict bytes unchanged, and `admission-check` now `success` on
   those merge groups because `B_mg` contains the new blob;
4. two consecutive real merge-queue landings.### 9.7 Acceptance record — landing and the first post-cutover merge group

Recorded after the cutover. Split into what the observation proves and what it
does not, because the first post-cutover merge group failed for a reason that
has nothing to do with this change.

#### Landing

| item | value |
|---|---|
| merge commit | `eaf204a418e4370c32bd6c9242c75ab3e3c9283e` (main tip) |
| lane | break-glass (App `5795152` `admission-check` = `failure`, by design — §8) |
| rulesets armed / restored | `27097366`, `27525972` — `bypass_actors` `[]→[OrganizationAdmin/pull_request]→[]` |
| readback | **RESTORE_IDENTICAL** — body sha256 `5423a80e…` and `f2f0c096…` both equal the frozen pre-snapshots; `current_user_can_bypass=never` on both; rules 5/1 and contexts 7+1 unchanged |

The App's rejection on the landing head was `trust_surface=FAIL — venue=pull_request
manifest_ref=dea3cce touched=2 manifest_touched=1 reasons=mismatch:.github/actions/setup-axiom-toolchain/action.yml`.
It was recorded as a failure and not reclassified.

#### Self-heal, verified

The first post-cutover merge group (`a1b09f8b…`, base `eaf204a4`) published:

```
trust_surface=PASS — venue=merge_group manifest_ref=eaf204a touched=18 reasons=none
```

The path that failed at the `pull_request` venue passes at the `merge_group`
venue because `B_mg` now contains the new blob. That is the mechanism §8
describes, observed rather than asserted.

#### Propagation, verified

Every base-tree consumer in that merge group switched from the old ladder to
tier 1 with no further change, which is what §9.3 predicted:

| job | revision on PR #450 | revision after cutover | tier after cutover |
|---|---|---|---|
| `attest / build-base-artifacts` | base (old) | base (new) | 1 |
| `attest / admission-independents` | base (old) | base (new) | 1 |
| `attest / admission-check` | base (old) | base (new) | 1 |
| `attest / go-critical-lane (0)`, `(1)` | base (old) | base (new) | 1 |
| `mint-prepare / prepare` | base (old) | base (new) | 1 |
| `closure-deriver` | pinned `c021c338…` | pinned `c021c338…` | apt — unchanged, §7 |

#### Supply-step latency, measured on both event types

The step provisions a system library; it does not read candidate content, so
the same job name is comparable across candidates even when the candidate
differs. Values are the composite-action `duration_ms`.

| job | pre-cutover | post-cutover | delta |
|---|---|---|---|
| `attest / build-base-artifacts` | 36.832 s | 1.019 s | −35.813 s |
| `mint-prepare / prepare` | 36.392 s | 7.192 s | −29.200 s |
| `attest / admission-check` | 6.915 s | 1.482 s | −5.433 s |
| `attest / admission-independents` | 6.419 s | 8.086 s | +1.667 s |
| `axiom-operational-slice` | 28.265 s | 9.095 s | −19.170 s |
| **sum** | **114.823 s** | **26.874 s** | **−87.949 s** |

The `+1.667 s` row is runner variance, not a regression: the same tier-1 path on
nine other invocations ran 0.96 – 9.10 s, and the pre value on that job was
already at the low end of the old ladder's bimodal 6 s/36 s split.

#### What this record does **not** claim

`T_admission` was **not** reduced to any asserted number, and the ≤ 377 s
threshold is **not** claimed met. The single post-cutover merge group is not a
usable sample:

- it failed with `reasonCode=ROT_ALLOWLIST` at the verdict leg — the pre-existing
  rotation-allowlist gate that also aborted PR #449 twice, unrelated to this
  change and not fixed here;
- `gateway / select` took 8 m 44 s on it versus 50 s on the pre-cutover baseline,
  a +474 s confound that is 5× larger than the −88 s this change can move;
- job wall times are not comparable across different candidate PRs at all.

The acceptance cohort therefore still requires n ≥ 5 clean post-cutover merge
groups with a stable `gateway` leg, and two consecutive real merge-queue
landings. Zero of two have occurred: the only post-cutover queue attempt
aborted on `ROT_ALLOWLIST`.

The honest status is: integrity preserved and verified, propagation verified,
supply-step latency reduced and measured, **admission-wall reduction pending
observation**.

## §10. Self-healing probe — B-layer cache generation after rotation

> **Probe.** Intent, not result — no post-re-seed merge group has been observed yet.

### 10.1 Why the rotation cost anything

The tier-1 reorder edits `.github/actions/setup-axiom-toolchain/action.yml`, so
`script_hash = sha256(action.yml + nimble.lock)` moved, and with it `a_key`,
`a_fp = sha256(a_key)[:32]` and `b_key = axiom-b-<b_identity>-<recipe_hash><a_fp>` —
the B-layer cache generation rotated. A miss falls back to `B-layer supply
unusable (exact-hit='', bin/ax present=no)` and rebuilds `bin/ax` (~83 s).

### 10.2 Measured cost of the rotation

Step `(P3)` in `mint-publish / publish` — the trusted-B-supply step that
resolves `bin/ax`:

| window | P3 |
|---|---|
| pre-cutover merge groups | 0 – 1 s (B-layer exact hit) |
| merge group #451 | 88 s |
| merge group #455 | 126 s |
| merge group #454 | 90 s |

`attest / build-base-artifacts` moved 80 s → 186 s over the same window, on the
same fallback. The B-layer cache was since re-seeded at `refs/heads/main`,
including `axiom-b-dc96a23cc1e076ba…-…ef3898b4029e8767594d28586e1df852` for main
tip `ec93f97c`.

### 10.3 What this PR measures

Whether the re-seed restores the exact hit on a *default-branch* merge group —
whether P3 returns to ~0 s. The sample is **this PR's own merge group**.

The candidate is docs-only on purpose: `docs/evidence/*.md` is not a closure
member, so `derived(M) == derived(B)` → `closureChange=false`, and `ROT_ALLOWLIST`
is auto-satisfied on the NORMAL path (`src/cli/merge_cli.nim:1126-1131`). Any
`src/` or `.github/` change would move `b_identity` and destroy the measurement.
No P3, `exact-hit=`, `T_ready` or `T_admission` value is asserted here.