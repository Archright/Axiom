# Capability-delta record — stickyshell + click (B-SEC-01, facets i+ii)

**Claim recorded here**: at the two newly-found "untrusted repo checkout"
consumers — `xTrayambak/stickyshell` @ `df552203e55a287264d513d82e964199810a9b6d`
and `ab9st8/click` @ `305847074f4b377ccb3ca74eecab1e1c15c34a37`, both built
against `toml_serialization` subject `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`
— the two B-1 typed-decode defects are **reachable** through the real config
path but confer **no capability beyond a valid config**. Every defect-input
state is byte-identical (or, where the consumer is random-by-design, decode-
state-identical) to the state of some **valid TOML config**. nph's NO-GO does
NOT transfer by assumption — it was **re-established here per consumer** by its
own C-series; the shared precondition (plain-overwrite config data model) was
verified independently for both (§3).

Method mirror: `bsec/capdelta/capdelta.md` (baseline / defect input / valid
contrast, byte-recorded). Raw evidence: `raw/click/`, `raw/stickyshell/`.
Drivers: `run_click.sh`, `run_click_witness.sh`, `run_stickyshell.sh`
(copies in `tools/`); state instrument: `probe_sth_state.nim`.

## 1. Identity and call form (Task A)

| | stickyshell | click |
|---|---|---|
| repo | `xTrayambak/stickyshell` | `ab9st8/click` |
| commit (HEAD of `master`, 2026-10-12) | `df552203e55a287264d513d82e964199810a9b6d` (single commit "initial commit", 2024-09-15) | `305847074f4b377ccb3ca74eecab1e1c15c34a37` (last commit 2021-07-19) |
| declared deps | `nim >= 2.0.0`, `colored_logger >= 0.1.0`, `jsony >= 1.1.5`, `toml_serialization >= 0.2.12` | `nim >= 1.2.0`, `tomlserialization >= 0.2.0` (legacy package name) |
| lockfile | **none — floating** | **none — floating** |
| resolved dep commit | **UNPINNED consumer-side.** Experiment pinned `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (subject working tree). The tag `0.2.18` = `b5b387e6` also satisfies both declared ranges — the "0.2.18 spans 17 commits" instability noted in `bsec/JUDGMENT.md` applies here verbatim; a fresh `nimble install` resolution is an observation about the registry, not a property of the range | same |
| decode call | `src/sth.nim:8` (`/etc/stickyshell.conf`, root) / `:12` (CWD `stickyshell.conf`): `Toml.decode(readFile(...), StickyshellOpts)` | `src/compile.nim:40`: `config = Toml.decode(readFile(workspace / "click.toml"), ClickConfig)`; workspace = nearest ancestor dir containing `click.toml` (`src/click.nim:7-13`) |
| form class | typed object, un-keyed, no flags | typed object, un-keyed, no flags |
| flavor | bare `Toml` default flavor; B-1 facets are flavor-independent (`link_a_flavor`: default ≡ v100 byte-identical on these inputs) | same |
| build used | Nim **2.0.8** `-d:release --mm:orc --deepCopy:on` (repo `nim.cfg` flag) | Nim **2.0.8** `-d:release --mm:orc` (2.2.10 also compiles; 2.0.8 used for uniformity) |

Toolchain scope facts (recorded, not adjudicated): stickyshell does **not**
compile with Nim 2.2.10 — `src/stickyshell.nim:203` passes an `int` var where
posix `poll` wants `cint` (overload resolution regression vs 2.0.8); with the
repo's own `nim.cfg` flag `--deepCopy:on` and Nim 2.0.8 it builds. The B-1
decode behavior is a `toml_serialization` property (JUDGMENT §1.5: `--mm:orc`
and `refc` agree); the library toolchain pin (2.2.10) governs the library
slice, the consumer toolchain (2.0.8) governs the consumer binary.

## 2. Config data model (Task B)

**stickyshell** — `StickyshellOpts` (`src/stickyshell.nim:29-34`), 5 fields,
each a simple set with a type default:

| field | type (default) | consumed at |
|---|---|---|
| `port` | `uint` (22) | `bindAddr`/`listen` (`stickyshell.nim:258-265`) |
| `delay` | `uint` (8000) | banner scheduling (`:121`, `:191`) |
| `maxLineLength` | `uint` (250) | random banner length (`:63`) |
| `maxConcurrentClients` | `uint` (100) | listen backlog + poll gate (`:203`, `:265`) |
| `customMessages` | `seq[string]` (`@[]`) | banner source: empty → random line, else `sample()` (`:62-83`) |

**click** — `ClickConfig` (`src/compile.nim:5-8`), 11 fields, zero defaults,
all plain overwrites: `name`, `compiler`, `outputDir` (`string`);
`auxOutput` (`bool`); `extensions`, `ignoreDirs`, `ignoreFiles`, `flags`,
`libs`, `includes`, `linkDirs` (`seq[string]`). Downstream: `compiler` is the
first token of a shell command executed verbatim via `execShellCmd`
(`:59-77`); `flags`/`libs`/`includes`/`linkDirs` are appended tokens;
`outputDir`/`name` form the output path; `extensions`/`ignoreDirs`/
`ignoreFiles` filter the source walk; `auxOutput` echoes the command.

**Answer: both are plain-overwrite models.** No accumulation, no ordering
sensitivity, no denylist, no cross-field coupling, no post-decode validation
of unbound content. The consumer behavior downstream is a pure function of the
decoded value (+ the workspace/environment). Caveat recorded (not hidden):
click's `compiler` makes *arbitrary command execution* a property of any valid
config already — the attacker who can write `click.toml` can run commands with
no defect at all; this record makes no severity judgment about that design.

## 3. Observed semantics of the two defects on this library revision

The T2 rule from the library record (`observations/t2_*`: input
`a,a,b,c` → `a=second, b=third, c=[]`) reproduces identically through both
consumers:

- **(i) duplicate key**: the duplicate **consumes a `fieldsDone` slot**; the
  decode loop breaks one application early, so the **final document key is
  silently dropped** (stickyshell s1; click k1/k11). If the duplicate sits on
  the **final** field, the loop breaks at its first occurrence and the **second
  duplicate is never read** — first value wins (stickyshell s3).
- **(ii) trailing input**: once all fields are filled the loop breaks and
  trailing bytes — spec-invalid (`!!!` + `[[attacker_table]]`) or valid-TOML
  unknown keys — are skipped identically (s5/s6/s8, k5/k6/k8).
- Mechanism control: with one field unfilled, trailing bytes ARE reached and
  rejected — stickyshell s7: `Error: unhandled exception: (5, 1) illegal
  character "!" [TomlError]`, exit 1; click k7: `(11, 1) illegal character "!"`,
  exit 1. The rejection channel exists and fires (C10b analog).

Consequently the precise equivalences are **not** always "last value only":
a duplicate-on-non-final-field config ≡ a valid config **with the last document
key removed**; a duplicate-on-final-field config ≡ a valid config with only the
**first** value. Both witnesses were **run and byte-verified** (§4). Both
remain inside the valid-config reachable state set.

## 4. C-series results (Task C)

### 4.1 click (binary `click208`, fixed workspace path; raw bytes compared)

| arm | config | observation |
|---|---|---|
| k0 baseline | (none) | interactive prompt → answered `n` → "Discarding.", exit 0 |
| k1 defect(i) | `compiler` duplicated (echo-first, echo-second) + 10 fields | `$ echo-second …` command line; **byte-identical stdout/stderr/exit to k2** |
| k2 valid | `compiler = "echo-second"` only | identical to k1 |
| k3 defect(i) reversed | echo-second then echo-first | **byte-identical to k4** |
| k4 valid | `compiler = "echo-first"` only | identical to k3 |
| k9/k10 | dup vs single `compiler = "echo"` (real command) | **byte-identical; exit 0; command executed** (echo output in stdout) |
| k5 defect(ii) | 11 fields + `!!!` + `[[attacker_table]]` + `rogue` | **byte-identical to k6 and k8** |
| k6 valid | 11 fields only | identical |
| k8 valid-TOML trailing | 11 fields + `rogue_key = "x"` | identical to k5 (valid trailing skipped same as invalid) |
| k7 control | 10 fields + `!!!` | TomlError, exit 1 — differs (rejection fires) |
| k11 defect witness | dup `compiler` + 10 fields + `linkDirs = ["realdir"]` (12 keys) | `linkDirs` line dropped from the built command — **byte-identical to k12** |
| k12 valid witness | same config without the `linkDirs` line | identical to k11 |
| k13 valid full | with `linkDirs = ["realdir"]` | command contains `-L…/realdir` — **differs from k11**, i.e. the drop is real, and the defect state = the valid config that omits the line |

### 4.2 stickyshell (binary `sth208`; TCP port probes + banner bytes)

Observables: `port9393`/`port9494` connect results, banner bytes read from the
listening socket. `delay = 1` and single-element `customMessages` keep the
banner deterministic; the `customMessages = @[]` state emits a random-by-design
banner, so its equivalence is proven at decode level (below).

| arm | config | observation |
|---|---|---|
| s0 baseline | (none → defaults) | bind port 22 as non-root → `BindFailed`, exit 1; no listener (baseline differs only through fields a valid config controls — port) |
| s1 defect(i) | `port` duplicated (9393, 9494) + 4 fields (6 keys) | 9393 REFUSED, 9494 OPEN; banner random garbage → `customMessages` (final key) dropped |
| s1b valid witness | same without the `customMessages` line | **probe state identical to s1** (ports, delay → banner arrives ~1s); decode state byte-identical |
| s2 naive contrast | last value only, `customMessages` kept | banner `BANNER-ARM-VALUE` — **differs from s1** (documents that the naive contrast is not the equivalent state) |
| s3 defect(i) on final field | `customMessages` duplicated reversed (SECOND, FIRST) | banner `BANNER-SECOND` — second duplicate never read; **byte-identical probe to s3b** |
| s3b valid witness | single `customMessages = ["BANNER-SECOND"]` | identical to s3 |
| s4 naive contrast | `customMessages = ["BANNER-FIRST"]` | differs from s3 |
| s5 defect(ii) | 5 fields + `!!!` + `[[attacker_table]]` + `rogue` | 9494 OPEN, banner `BANNER-ARM-VALUE\r\n` — **byte-identical to s6 and s8** |
| s6 valid | 5 fields only | identical |
| s8 valid-TOML trailing | 5 fields + `rogue = "x"` | identical to s5 |
| s7 control | 4 fields + `!!!` | `(5, 1) illegal character "!"` → exit 1, no listener (rejection fires) |

Decode-state instrument (`probe_sth_state.nim`, consumer's exact call form,
same subject revision) — byte-identical states: **s1 ≡ s1b, s3 ≡ s3b,
s5 ≡ s6 ≡ s8**; differs: s1 vs s2, s3 vs s4; s7 raises. Raw: `raw/stickyshell/
state_probe/`.

## 5. Conclusion recorded (no severity assessment)

| consumer | plain-overwrite? | defect reaches? | capability beyond a valid config? | verdict |
|---|---|---|---|---|
| stickyshell | **yes** (§2) | yes (s1/s3/s5) | **none** — every defect state byte-verified ≡ a valid config's state | **NO-GO** (R2) |
| click | **yes** (§2) | yes (k1/k5/k11) | **none** — same | **NO-GO** (R2) |

**nph's NO-GO does not transfer by default — it was re-established here**: the
transfer precondition (plain-overwrite config model) was verified per consumer,
and each consumer's own 3-way C-series produced equivalence evidence
independently. Scope conditions: pinned consumer commits above; dep commit is
floating on both (experiment pinned `4aa8e22`); stickyshell's buildability is
Nim-2.0.8-scoped. No CVSS score, severity judgment, or upstream issue is filed
here or elsewhere.

## 6. Reproduction

```bash
# consumers + probes (neutral cwd /tmp; binaries in /tmp only)
bash /tmp/checkout_trio/build_consumers.sh          # click (2.2.10+2.0.8), sth (2.0.8 + repo --deepCopy:on)
bash /tmp/checkout_trio/run_click.sh                # k0-k8 + comparisons
bash /tmp/checkout_trio/run_click_witness.sh        # k11-k13
bash /tmp/checkout_trio/run_stickyshell.sh          # s0-s8 (server + port probes)
nim208 c ... followup/checkout_trio/probe_sth_state.nim   # state instrument
```

Clones used (read-only): `/tmp/checkout_trio/{stickyshell,click,jsony,colored_logger}`;
subject `<workspace>/nim-toml-serialization` untouched.
Dep paths: `~/.nimble/pkgs2/{serialization-0.5.4-6a75be38…, faststreams-0.5.2-589a9cf0…,
stew-0.5.0-db229429…}`.
