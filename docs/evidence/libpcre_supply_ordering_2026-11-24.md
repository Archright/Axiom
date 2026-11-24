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
expected outcome in the S1b band rather than the S1a band, which is why the
Terminal Outcome is reachable: the second-latest required context on the audited
run finished 85 s after `admission-gate` started its tail, and S1b's realized
saving is 98.4 s at its minimum.

A 50 s residual would have landed at ~401 s and missed. The distinction is the
whole reason tier 1 does not use `dpkg -i`.

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
surface-policy amendment is possible or useful here.