# Exposure search — nim-toml-serialization D1 (typed-accessor SIGSEGV) & D2 (\xHH raw byte)

**Observation date**: 2026-10-11 (~12:06–13:00 UTC) · **Searcher**: agent `developer` via `gh` CLI
**Scope**: public GitHub, default branches, as indexed by GitHub code search on the observation date.
**Nature of result**: fact-finding only. "No path found" is a property of the search; "no path exists" is a property of the world. No repo was modified; no severity assessment; no issue filed.
**Queries used**: `queries.md` (exact, reproducible). **Per-repo matrix**: `consumers.tsv` (36 rows).

---

## Task 1 — consumers of the typed accessor (`toml_serialization/value_ops`)

**Result: NONE FOUND on public GitHub default branches as of 2026-10-11.**

- Every query shape for the submodule import (`toml_serialization/value_ops`, quoted import
  phrase, `from`-import phrase, `filename:value_ops.nim` vendored-copy hunt) returned only:
  (a) our own `Archright/Axiom` probe/evidence files, (b) the library itself and its tests,
  (c) one unrelated same-name file (`gene-lang/gene/src/gene/types/core/value_ops.nim`).
- The `TomlValueRef language:Nim` sweep (83 files) is dominated by **`parsetoml`** consumers —
  a different library that shares the type name `TomlValueRef` and owns the `parseToml` macro
  (`NimParsers/parsetoml/src/parsetoml.nim:1735`). All such hits were classified out one by one
  (moe, nimdow, configlet, cligen, ggplotnim, TimepixAnalysis, chalk (`parsetoml == 0.7.1`),
  NimPlant, Nimhawk, dfkup, arturo, scrolls, nimib, xTrayambak/neo, NimLaunch, …).
- Real toml_serialization consumers that decode into dynamic nodes
  (`Toml.decode(..., TomlValueRef)`) exist — ImThemes, ImClocks/ImDemo/ImPasswordGen, scoopx —
  but **all use the untyped accessor or `hasKey` + field access; none uses the two-arg typed
  accessor `["key", T]`, and none imports `value_ops`** (`toml_serialization.nim` does not
  re-export it, so the import is mandatory for the SIGSEGV form).

### D1 refinement observed while pinning revs (fact-finding)

- At `b5b387e6` (v0.2.18 tag, 2025-09-25): untyped `[]` = `node.tableVal[name]` → raises
  `KeyError` on absent key; typed `[]` therefore raises, does not segfault. `getOrDefault`
  (value_ops.nim:128) already existed with nil-returning semantics, but nothing fed its nil
  into `innerValue`.
- At HEAD (`4aa8e22`): untyped `[]` = `node.tableVal.getOrDefault(name)` → nil on absent key;
  typed `[]` = `node[name].innerValue(T)` → nil deref ⇒ SIGSEGV. The poisoning of the typed path
  came with the #105-era change (`71ed1393`, 2026-06-14, "Add raises").
- ⇒ D1 exists only for consumers whose resolved rev ≥ `71ed1393` **and** which import
  `value_ops` and call the typed accessor on a possibly-absent key. The set of consumers with
  rev ≥ `71ed1393` found anywhere: exactly one (nimbus-eth1's submodule, `73529768`) — and it
  has zero `value_ops`/`TomlValueRef` usage (repo-scoped searches returned 0; the client uses
  only the typed `TomlReader` API).

## Task 2 — consumers resolving ≥ `c838ca0` (D2-active revs)

**Resolution fact**: library tags are `v0.2.18 → b5b387e6` (2025-09-25), `v0.2.16`, `v0.2.14`.
All post-`b5b387e6` commits still declare version 0.2.18 but are **untagged** — so plain
`nimble install` / `requires`-only resolution lands on the **tag = `b5b387e6`**, not HEAD.
Only lock files, submodules, and vendored copies can reach newer revs.

**D2 timeline** (verified against `format.nim` content): `TomlHexEscape` ABSENT from
`Toml_v110_Flags` at `c838ca01` (#107) and `d019566f` (#109); PRESENT from `62dcb2ce`
(#115 "Enable TOML v1.1.0", 2026-06-18) through `73529768` (#118) to HEAD `4aa8e22` (#120).
`format.nim` at `73529768` is byte-identical to HEAD. Default flavor `Toml` uses
`flavorRuntimeFlags = Toml_v110_Flags` ⇒ `\xHH` accepted (→ lone raw byte, invalid UTF-8 for
≥ 0x80) for any consumer at rev ∈ {`62dcb2ce`…`4aa8e22`}.

**Consumers with a hard pin (lock / submodule / vendored), all enumerated:**

| Consumer | Pin mechanism | Resolved rev | D2-active? |
|---|---|---|---|
| status-im/nimbus-eth1 | vendor submodule | **`73529768`** (2026-07-02; ancestor of HEAD, 2 behind) | **YES** |
| status-im/nimbus-eth2 | vendor submodule | `b5b387e6` | no |
| logos-co/nimbos | vendor submodule | `b5b387e6` | no |
| logos-storage/logos-storage-nim | vendor submodule | `b5b387e6` | no |
| durability-labs/archivist-node | vendor/nimble submodule | `b5b387e6` | no |
| promethei-project/nim-promethei-node | vendor/nimble submodule | `b5b387e6` | no |
| Patitotective/ImThemes | nimble.lock | `b5b387e6` | no |
| dneumann42/nide | nimble.lock | `b5b387e6` | no |
| logos-messaging/logos-delivery | nimble.lock | `b5b387e6` | no |
| getenu/enu | atlas.lock | `b5b387e6` | no |
| NixOS/nixpkgs (nph) | lock.json | `b5b387e6` | no |
| metacraft-labs/reprobuild | vendored dir (no format.nim; value_ops/types byte-identical to b5b387e6) | ≈ `b5b387e6` | no |
| nix-community/flake-nimble | package def | `a390a673` (2021, packaging only) | no |

**Floating consumers** (no lock/submodule found): nim-confutils, nim-eth, nim-graphql (pkg/
alias, rev unresolved), arpm/libarpm, reprobuild-llm-agent-packages, Im* apps, sidebard, goodwm,
scoopx, GDGW-Maverick-Bot, click, xTrayambak/{feko,stickyshell,trayfetch,districity},
kaushalmodi, penguinite/everything. **None was found pinning ≥ `c838ca0`**; absent a lock their
default resolution is the tag `b5b387e6` (build-environment-dependent; cannot exclude a
source-checkout workflow, but none was observed).

**API-marker searches**: `createTomlFlavor`, `Toml_v110_Flags`, `toml_serialization/format`
have **zero external consumers** in the index; `TomlHexEscape` matches only the library and
reprobuild's old-vintage vendored copy.

### The one D2-reachable consumer

**status-im/nimbus-eth1** (Nimbus execution client) pins `vendor/nim-toml-serialization` at
`73529768ced17720f78fb5b57191e863f8d8a9c1` — post-#115, `\xHH` default-ON, byte-identical
`format.nim` to HEAD. Decode path: confutils TOML config loading (`execution_chain/conf.nim`
imports `confutils/toml/defs`, `toml_serialization`, `toml_serialization/std/net|uri`; TOML
entered via `--config-file`; custom `readValue(TomlReader, …)` overloads in conf.nim and via
nim-eth's `enr_toml.nim` / `nat_toml.nim`). Input origin: **operator-supplied config file**
(local). This converts D2's "N/A at the two known pins" into a **testable, named
consumer-deposit pair** (defect at pinned rev ↔ consumer at that rev), with the input-origin
caveat recorded: operator config, not remote-attacker-fed data.

## Task 3 — consumers feeding untrusted bytes into the library

**Updated survey (36-row matrix in `consumers.tsv`). Input-origin classification:**

| Input-origin class | Consumers |
|---|---|
| First-party HTTPS feed | Patitotective/ImThemes (`browseview.nim:193` — downloads repo-owner's `themes.toml` over HTTPS, then `Toml.loadFile`; re-verified unchanged) |
| Untrusted repo checkout (CWD/workspace config pickup) | **arnetheduck/nph** (`.nph.toml` from the repo being formatted — known, re-verified: `src/nph.nim loadConfig`), **xTrayambak/stickyshell** (`sth.nim:8,12` — reads CWD `stickyshell.conf`), **ab9st8/click** (`compile.nim:40` — reads `click.toml` from managed workspace) — the latter two are NEW; beef331/goodwm and xTrayambak/feko also have CWD fallback paths |
| First-party aggregator repo | ArgonLinux/arpm + libarpm (`package_info.nim:28,40` — `Toml.decode` of package metadata from the ArgonLinux/packages aggregator repo; no `httpClient` found in the decode path) |
| Local operator config (blockchain/logos nodes) | nimbus-eth1, nimbus-eth2, nimbos, logos-storage, logos-delivery, archivist-node, promethei-node (all confutils `--config-file`; transitive libs nim-confutils + nim-eth) |
| Local user/operator config | nide, enu, sidebard, goodwm, scoopx, GDGW-Maverick-Bot, feko, stickyshell(/etc), trayfetch, districity, ImClocks/ImDemo/ImPasswordGen, kaushalmodi (dev tool), reprobuild(+llm-agent-packages) |
| First-party tests only | status-im/nim-graphql (`test_common.nim:232,288`), logos-storage testpresets |
| Not consumers | nim-lang/Nim (testament `packagebatches.nim` — CI duration string), nim-lang/atlas-tests (resolver test URL list), EmilIvanichkovv/nim-playground (research notes), penguinite/everything (meta-package), eth-pkg/pkg-builder (recipes), NetSP-KAIST/forky + CASABECI (archived/copied nimbus sources) |

**No consumer was found feeding an HTTP response body, upload, p2p message, CLI-arg-supplied
TOML string, or env var directly into `Toml.decode`/`Toml.loadFile`/`parseToml`.** The closest
attacker-influenced classes remain: the untrusted-repo-checkout trio (nph / stickyshell / click)
and ImThemes' first-party feed.

Known-consumer verification: logos-delivery, reprobuild, arpm, nide, nph, ImThemes all
re-checked today — resolution revs and call forms unchanged; nothing regressed onto newer revs.

## Task 4 — verdict support

### D1 — typed-accessor SIGSEGV
**No reachable consumer found.** The required conjunction — (a) resolved lib rev ≥ `71ed1393`,
(b) explicit `import toml_serialization/value_ops`, (c) typed accessor on a possibly-absent key —
has **zero** observed instances: (b) has no public-GitHub instances at any rev, and the only
(a)-satisfied consumer (nimbus-eth1 submodule `73529768`) fails (b) and (c) outright.

Coverage bounding a continued **UNKNOWN** (or a NO-GO on exposure): public GitHub, default
branches, GitHub-indexed, as of 2026-10-11; all 13 hard pins enumerated = `b5b387e6` or older
except nimbus-eth1; floating consumers tag-resolve `b5b387e6`. Not covered: non-default
branches, forks, non-GitHub forges, private/deleted/unindexed repos, build-time source
checkouts that float to HEAD.

### D2 — `\xHH` raw-byte insertion
**One concrete reachable consumer found: `status-im/nimbus-eth1`** (submodule pinned
`73529768`; default flavor flags include `TomlHexEscape`; `format.nim` byte-identical to HEAD).
Reachability is through operator-supplied `--config-file` TOML — an exposed decode path at a
D2-active rev, suitable as a testable consumer↔deposit pair. No consumer was found feeding
remote/attacker-controlled bytes (see Task 3 classes). All other enumerated consumers sit at
`b5b387e6`, where the gate rejects `\xHH`.

### Standing limitations (apply to both verdicts)
1. GitHub code search indexes **default branches only**; forks are excluded. Non-default
   branches were NOT searched (not reachable via code search).
2. Submodule contents are not indexed — nimbus-eth1's exposure was found via `.gitmodules` +
   submodule-SHA enumeration, not code search; the same blind spot applies to any future
   submodule-based consumer.
3. The legacy index is demonstrably incomplete: `repo:status-im/nim-graphql toml_serialization`
   returned 0 despite the import existing; quoted-phrase queries returned 0 despite known
   matches. Negative query results are weaker than positive ones.
4. Non-GitHub forges (GitLab/Codeberg/self-hosted) and private repos are out of coverage.
5. "Floating" consumers (no lock/submodule) were classified as tag-resolving to `b5b387e6`;
   an operator checkout of the default branch would float them to HEAD — none was observed.
