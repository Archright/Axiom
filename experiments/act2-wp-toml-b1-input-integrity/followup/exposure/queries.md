# Exposure search — exact queries (observation date: 2026-10-11, ~12:06–13:00 UTC)

Scope: public GitHub, **default branches only** (GitHub code search limitation), forks excluded
by the index. `gh search code` uses the legacy REST code-search index; submodule contents are
NOT indexed (vendored/submodule consumers must be found via `.gitmodules` + submodule SHA API).
Tool: `gh` CLI authenticated as `developer`.

## A. `gh search code` queries (Task 1 — typed accessor / value_ops)

| # | Query | Result summary |
|---|-------|----------------|
| A1 | `toml_serialization/value_ops` | 14 hits, all `Archright/Axiom` (our own probes/evidence) |
| A2 | `"import toml_serialization/value_ops"` (quoted phrase) | 0 |
| A3 | `"from toml_serialization/value_ops"` (quoted phrase) | 0 |
| A4 | `value_ops filename:value_ops.nim` | `gene-lang/gene` (unrelated same-name file), `status-im/nim-toml-serialization` (self). No vendored toml copies. |
| A5 | `TomlValueRef language:Nim` | 83 files; nearly all are `parsetoml` consumers (shared type name). Only toml_serialization users: ImThemes, reprobuild vendored, Im* apps. |
| A6 | `parseToml language:nim` | ALL hits are `parsetoml` consumers — `parseToml` is a parsetoml macro (`src/parsetoml.nim:1735`); it does not exist in nim-toml-serialization HEAD. |
| A7 | repo-scoped `repo:status-im/nimbus-eth1 value_ops`, `repo:status-im/nimbus-eth1 TomlValueRef`, same for `nimbus-eth2` | 0 (both clients use only the typed reader API) |

## B. `gh search code` queries (consumer enumeration)

| # | Query | Result summary |
|---|-------|----------------|
| B1 | `nim-toml-serialization` | ~75 files: consumers, locks, packaging indexes, CHANGELOGs, logs |
| B2 | `import toml_serialization language:nim` | 63 files — the authoritative consumer sweep (nimbus-eth2/eth1, nim-confutils, nim-eth, nim-graphql, nimbos, logos-storage, archivist, promethei, arpm/libarpm, nide, ImThemes, nph, reprobuild(+llm-agent), enu via lock, sidebard, goodwm, scoopx, GDGW-Maverick-Bot, click, xTrayambak apps, kaushalmodi, penguinite/everything, atlas-tests) |
| B3 | `"import toml_serialization"` (quoted phrase) | 0 — legacy index does not reliably serve quoted phrases; B2 is the working shape |
| B4 | `toml_serialization filename:nimble.lock` | ImThemes, nide, logos-delivery |
| B5 | `Toml.loadFile language:nim` | sidebard, ImThemes, nph, nide, nim-graphql (tests), library tests |
| B6 | `Toml.decode language:nim` | arpm, libarpm, GDGW-Maverick-Bot, ImClocks/ImDemo/ImPasswordGen, goodwm, scoopx, click, kaushalmodi/nim-systemverilog-dpic, logos-storage (tests), reprobuild(+llm-agent-packages), xTrayambak/{districity,feko,stickyshell,trayfetch}, library tests |

## C. `gh search code` queries (Task 2 — newer-than-pin API markers)

| # | Query | Result summary |
|---|-------|----------------|
| C1 | `createTomlFlavor` | only `status-im/nim-toml-serialization` (toml_serialization.nim, format.nim, tests/test_flavor.nim) |
| C2 | `Toml_v110_Flags` | only the library (format.nim) |
| C3 | `toml_serialization/format` | 0 external consumers |
| C4 | `TomlHexEscape` | library (+tests), `metacraft-labs/reprobuild` vendored copy (lexer/types/writer/README), `jonbaldie/database` (Go file, unrelated string) |

## D. API / raw fetches (resolution + vintage pinning)

- `nimble.lock` / `atlas.lock` grep for `toml_serialization`:
  Patitotective/ImThemes, dneumann42/nide, logos-messaging/logos-delivery, getenu/enu → all `b5b387e6fb2a7cc75d54a269b07cc6218361bd46`.
- `NixOS/nixpkgs pkgs/by-name/np/nph/lock.json` → toml_serialization `b5b387e6…`; `package.nix` = nph 0.7.0.
- `nix-community/flake-nimble packages/toml_serialization.json` → rev `a390a673…` (2021-02-16, packaging only, "HEAD" label).
- `nimpkgs/nimpkgs packages/to/toml_serialization/pkg.json` → catalog metadata (0.2.18), no rev pin.
- Library git tags: `v0.2.18→b5b387e6`, `v0.2.16→c8dc4527`, `v0.2.14→fea85b27`. HEAD commits still declare 0.2.18 but are untagged ⇒ plain nimble resolution lands on the tag = `b5b387e6`.
- `compare/b5b387e6...4aa8e22` → 17 commits, 2026-06-13..2026-09-11: 4f1e8b73(#100), 8a0c1bd7(#104), **71ed1393(#105 "Add raises")**, 9e42585d(#106), **c838ca01(#107 "Add flavor")**, 4eed91e3(#108), d019566f(#109), 58c40e65(#110), 09b92c60(#111), a519b347(#112), 7b700ce6(#114), 9f35d5d7(#113), **62dcb2ce(#115 "Enable TOML v1.1.0")**, 096659b7(#117), **73529768(#118)**, 96eb1b25(#119), 4aa8e222(#120).
- `compare/73529768...4aa8e22` → ahead_by 2, behind_by 0 (73529768 is an ancestor of HEAD).
- Submodule SHAs (`contents/<path>?ref=HEAD`, type=submodule):
  - `status-im/nimbus-eth2 vendor/nim-toml-serialization` → `b5b387e6…`
  - `status-im/nimbus-eth1 vendor/nim-toml-serialization` → `73529768…`
  - `logos-co/nimbos vendor/nim-toml-serialization` → `b5b387e6…`
  - `logos-storage/logos-storage-nim vendor/nim-toml-serialization` → `b5b387e6…`
  - `durability-labs/archivist-node vendor/nimble/toml_serialization` → `b5b387e6…`
  - `promethei-project/nim-promethei-node vendor/nimble/toml_serialization` → `b5b387e6…`
- `metacraft-labs/reprobuild libs/nim-toml-serialization` = plain vendored dir (not submodule); vendored `value_ops.nim` and `types.nim` byte-identical to `b5b387e6`; vendored tree has **no `format.nim`**.
- `format.nim` flag-set check: `TomlHexEscape` ABSENT at `c838ca01`(#107) and `d019566f`(#109); PRESENT at `62dcb2ce`(#115), `73529768`, `4aa8e22`. `format.nim` at `73529768` is byte-IDENTICAL to `4aa8e22` (diff clean). `Toml_v110_Flags` = {InlineTableNewline, InlineTableTrailingComma, **HexEscape**, HourMinute, StrictComma}; `flavorRuntimeFlags(Toml) = Toml_v110_Flags`.
- `value_ops.nim` b5b387e6 vs HEAD: at `b5b387e6` the untyped `[]` is `node.tableVal[name]` (raises KeyError) while `getOrDefault` (line 128) already existed with nil-returning semantics; at HEAD the untyped `[]` itself is `node.tableVal.getOrDefault(name)` (nil on absent), so the typed `[]` (`node[name].innerValue(T)`) derefs nil ⇒ SIGSEGV. The poisoning of the typed path is the #105-era change (71ed1393).
- `.gitmodules` sweeps across all candidate repos (grep `toml_serialization`): confirmed submodules at nimbos, logos-storage, archivist, promethei, nimbus-eth1/2; none at nim-graphql (its `pkg/toml_serialization` import resolves via `config.nims` paths; no lock found).
- Input-origin reads (raw file fetches): every file cited in `consumers.tsv`.

## Known index gaps encountered (bounds the negative)

1. `nim-graphql`: repo-scoped code search `repo:status-im/nim-graphql toml_serialization` returned 0 although `graphql/test_common.nim` demonstrably imports `pkg/toml_serialization` (raw fetch). The legacy index is incomplete.
2. Quoted-phrase queries (A2, A3, B3) returned 0 despite known-matching content existing (e.g. ImThemes tree). Only the unquoted shapes are trustworthy.
3. Submodule contents (nimbus-eth1's `73529768` copy) are invisible to code search; found via `.gitmodules` + submodule SHA enumeration instead.
