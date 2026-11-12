# Call-site evidence — B-SEC-03 reachability per consumer

Experiment: `act2-wp-toml-b1-input-integrity/bsec` · Date: 2026-10-11 ·
Toolchain: Nim 2.2.10 (`bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef`), nimble
0.22.2, gcc 13.3.0, Linux 6.17.0-42-generic x86_64, `--mm:orc`.

**Subject (READ-ONLY, byte-clean before/after)**:
`status-im/nim-toml-serialization` — local clone HEAD
`4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (2026-09-11), which equals
upstream HEAD (`git ls-remote` verified this run).

**Question answered here**: for each real-world consumer of
nim-toml-serialization — **nph** (`arnetheduck/nph`) and **ImThemes**
(`Patitotective/ImThemes`) — which exact dependency commit does that consumer
build against, in what call form, and is the `TomlHexEscape` gate
(`toml_serialization/lexer.nim` `scanHexEscape`, the B-SEC-03 `\xHH` raw-byte
insert) **ACTIVE** at that revision. Machine-readable twin: `callsite.json`.
Version-string ambiguity analysis: `dep_identity.md`.

---

## 0. The decisive fact (recorded, not re-derived)

`b5b387e6` (2025-09-25, "v0.2.18(#99)") through `4aa8e22` (HEAD, 2026-09-11)
— **17 commits — ALL report `version = "0.2.18"`** in `toml_serialization.nimble`.
The flavor mechanism (`createTomlFlavor`) landed in `c838ca0` ("Add flavor
(#107)") and the `Toml_v110_Flags` binding in `7352976` ("Rename
Toml_v100_Flags to Toml_v110_Flags (#118)") — both AFTER `b5b387e6`. The
version string therefore does NOT identify the commit; the two same-version
commits differ in security-relevant behavior (§3).

**Rule: dependency identity = commit SHA / blob hashes, never the version string.**

---

## 1. Consumer: nph (`arnetheduck/nph`)

| Field | Value |
|---|---|
| Repo | https://github.com/arnetheduck/nph |
| Commit observed | `2cacf6cc28116e4046e0b67a13545af5c4e756bd` (2026-02-16, "Changelog edits") |
| = upstream HEAD | yes — `git ls-remote` → `2cacf6cc…` (this run) |
| Working tree | clean (`git status --porcelain` 0 lines) |
| Dependency declaration | `requires "toml_serialization >= 0.2.18 & < 0.3.0"` (nph.nimble) |
| Lockfile | **none** (`nimble.lock` absent) |
| **Resolved dependency commit** | **`b5b387e6fb2a7cc75d54a269b07cc6218361bd46`** — evidence: (a) the clone's `nimbledeps/pkgs2/toml_serialization-0.2.18-76ae1c2a…/nimblemeta.json` `vcsRevision: b5b387e6…`; (b) all 11 files of that installed copy **byte-identical** to `git show b5b387e6:<path>` blobs (table below); (c) **fresh re-resolution this run**: sandboxed `nimble install toml_serialization` (and `@"0.2.18"`) → installs payload with `vcsRevision b5b387e6…`, because upstream tag **`v0.2.18` → `b5b387e6`** and HEAD is untagged (tags: v0.2.14→`fea85b27`, v0.2.16→`c8dc4527`, v0.2.18→`b5b387e6`; nothing later) |

### Call form

`src/nph.nim:103` (blob `cabcd5c830daa0a5a853a8a6b151066720b214b9`):

```nim
result = Toml.loadFile(configFile, NphConfig)
```

- **Target type**: `NphConfig` — plain `object` (4 fields; `exclude`,
  `extendExclude{.serializedFieldName("extend-exclude")}`,
  `includePatterns{.serializedFieldName("include")}`, `color: Option[bool]`)
  → **typed object decode**, NOT the value tree.
- **Keyed vs un-keyed**: **un-keyed** (two-arg `loadFile` overload at
  `toml_serialization.nim@b5b387e6` → `tomlLoadImpl(filename, T, "",
  TomlCaseSensitive, params)`).
- **Flags passed**: **none** (`params` empty) → `TomlReader.init(stream)`
  with `flags: TomlFlags = {}` default.
- **Flavor symbol**: bare `Toml` — at `b5b387e6` this is the
  `serializationFormat Toml, mimeType = "application/toml"` format symbol;
  `createTomlFlavor` does not exist yet at that revision.
- Config file: default `.nph.toml` (`src/nph.nim:320`); errors are caught in
  `loadConfig` (`src/nph.nim:104-106`) → stderr warning + continue with
  defaults (logged, not silent).
- Imports: `src/nph.nim` imports only `toml_serialization` (line 13).

### `toml_serialization/value_ops` import status

**Not imported anywhere in nph** (grep `value_ops` over `src/`, `tests/`,
`config.nims`: 0 hits) — and `toml_serialization.nim@b5b387e6` imports/
re-exports only `serialization, reader, writer, types, private/utils`, so
`value_ops` is **absent from nph's compiled closure**.

### Per-file blob hashes (toml_serialization @ `b5b387e6` — the copy nph builds against)

| File | git blob | installed-copy sha256 match |
|---|---|---|
| `toml_serialization.nim` | `f2643bb5ac9f1bcaa6598f4cecf91f76f217387f` | identical |
| `toml_serialization.nimble` | `7ac7a0f8ba30916759c946c2ca280661a466f8c1` | identical |
| `toml_serialization/lexer.nim` | `9c337efc6ac5a052348c7fbe0f5510672f7563af` | identical |
| `toml_serialization/reader.nim` | `bf3647796da2504d1f7fb81306e904728c183e3a` | identical |
| `toml_serialization/writer.nim` | `ab3465ebfb1a97feb66767404a290098e3bca95b` | identical |
| `toml_serialization/types.nim` | `8cfae164b93d94c0f684e3c474b12e001f47d5e9` | identical |
| `toml_serialization/value_ops.nim` | `915c19151f9c9b490b9d74be1712ee7d9149596a` | identical |
| `toml_serialization/private/utils.nim` | `ab1d4c55bef324dad99741037943da5a6b2e6e47` | identical |
| `toml_serialization/private/array_reader.nim` | `4991903555bd2dbb81ac1472a77e599e8302d813` | identical |
| `toml_serialization/std/net.nim` | `cc3dfa22a85a6edd0cf25cf8ce30e59a5b67ba00` | identical |
| `toml_serialization/std/uri.nim` | `d85d5aeed0822fa6d9e25984a2f4d27b3e00393f` | identical |

`toml_serialization/format.nim` **does not exist** at `b5b387e6` (git
ls-tree proof); neither do `decoder.nim`, `desc.nim`,
`private/utf8_validate.nim`.

### `TomlHexEscape` activation verdict at the revision nph builds: **NO — NOT ACTIVE**

Static (source at `b5b387e6`):
- `format.nim` does not exist; there is no flavor-runtime-flag merge. The
  only flag source is `TomlReader.init`'s parameter
  (`reader.nim@b5b387e6:42-52`, default `{}`) and `TomlLexer.init`
  (`lexer.nim:150`, default `{}`).
- `scanHexEscape` (`lexer.nim:387`) **rejects when the flag is absent**:
  `lexer.nim:391-392` `if TomlHexEscape notin lex.flags:
  raiseInvalidHex(lex, "not supported by standard, please use
  \`TomlHexEscape\`")`. The raw-byte insert `res.add char(code)` is at
  `lexer.nim:400`, gated behind it.
- The consumer passes no flags at the call site (`nph.nim:103` has no
  params), so `lex.flags == {}` at runtime.

Dynamic (`probes/probe_nph_profile.nim`, built against nph's installed
snapshot, output `raw/probe_nph_profile.stdout.log`):

```
nph_control: OK exclude=@["plain"] bytes=[706C61696E] color=none(bool)
nph_hex_45:  REJECTED TomlFieldReadingError{field=exclude, inner=TomlError}: (1, 18) invalid hex escape, not supported by standard, please use `TomlHexEscape`
nph_hex_80:  REJECTED TomlFieldReadingError{field=exclude, inner=TomlError}: (1, 15) invalid hex escape, not supported by standard, please use `TomlHexEscape`
```

**B-SEC-03 reachability for nph: NOT REACHABLE** at the revision it actually
builds — the gate raises before `scanDigits`/`res.add char(code)`; the
defective insert is unreachable. (Qualifier, recorded honestly: nph has no
lockfile, so its resolution is a snapshot-in-time; if upstream ever tags a
new version inside `>= 0.2.18 & < 0.3.0` with different behavior, this
verdict must be re-evaluated against the new tag's commit. Today's
re-resolution still lands on `b5b387e6`.)

---

## 2. Consumer: ImThemes (`Patitotective/ImThemes`)

| Field | Value |
|---|---|
| Repo | https://github.com/Patitotective/ImThemes |
| Commit observed | `d67592d4746031f47e962176736a976dcc040dc9` (2026-06-28, "Red Oni: colorButtonPosition -> Right according to #59") |
| = upstream HEAD | yes — `git ls-remote` → `d67592d…` (this run) |
| Lockfile | `nimble.lock` (blob `2bc237a6f1145fbe308e48fc37ca547281dd077a`, lock format v2) |
| **Pinned dependency commit** | **`toml_serialization` 0.2.18 @ `b5b387e6fb2a7cc75d54a269b07cc6218361bd46`** — nimble.lock `packages["toml_serialization"]`, content checksum sha1 `76ae1c2af5dd092849b41750ff29217980dc9ca3` |
| Other relevant pins | `niprefs` 0.3.5 @ `30f522ac1888ae2930e833ab6c5d954baf3e8702` (2023-08-23, sha1 `370855d00a8460857d2c67c23d2d6cb90be9423a`); `serialization` 0.4.9 @ `b5193007a49639b21b2b80cd8ef8cbe0df6b0e48`; `faststreams` 0.5.0 @ `ce27581a3e881f782f482cb66dc5b07a02bd615e`; `stew` 0.4.1 @ `e5740014961438610d336cd81706582dbf2c96f0`. `niprefs` is the **only** lock package whose dependencies include `toml_serialization`. |

### Call form

`src/browseview.nim:193` (blob `3d990e0636aff6b42c699660aaa631311e5bb0b9`):

```nim
app.feed = Toml.loadFile(app.downloader.getPath("feed").get(), TomlValueRef)["themes"].getTables()
```

- **Target type**: `TomlValueRef` — **value-tree path, no typed object**; the
  document (downloaded `themes.toml` feed) is parsed into a generic node tree.
- **Keyed vs un-keyed**: un-keyed (2-arg `loadFile` overload); the
  `["themes"]` + `.getTables()` navigation happens after parsing via
  niprefs/nodeutils accessors, not via the keyed decoder.
- **Flags passed**: **none** → `TomlReader.init(stream)` default `flags = {}`.
- **Flavor symbol**: bare `Toml` (obtained through niprefs' re-export:
  `src/niprefs.nim:140` `export toml_serialization except \`$\``).
- `Toml`/`TomlValueRef` reach ImThemes via `import niprefs`
  (`src/browseview.nim:3`).

### `toml_serialization/value_ops` import status

- ImThemes' own sources: **no `value_ops` import** (grep 0 hits).
- But `value_ops` **is compiled into ImThemes' closure** through
  niprefs: `src/niprefs/nodeutils.nim:4` `import toml_serialization/value_ops`.
- Top-level `toml_serialization.nim@b5b387e6` does **not** re-export
  `value_ops` (imports only `serialization, reader, writer, types,
  private/utils`).

### Two-arg accessor `node[name, T]` — **absent from ImThemes' callable dependency graph**

- `value_ops.nim@b5b387e6` **defines** it — `:84`
  `` proc `[]`*(node: TomlValueRef, name: string, T: type): T `` and `:95`
  (index variant) — but nothing reaches it:
  - no module inside toml_serialization@b5b387e6 imports `value_ops`
    (grep over the whole tree: only tests do);
  - the only importer in ImThemes' graph, `niprefs/nodeutils`, **explicitly
    strips it**: `src/niprefs/nodeutils.nim:6`
    `` export value_ops except len, `[]`, contains ``
    and then defines its own single-argument accessors:
    ``:166 proc `[]`*(node: TomlValueRef, name: string): TomlValueRef`` and
    ``:170 proc `[]`*(node: TomlValueRef, index: int): TomlValueRef``;
  - ImThemes sources contain **zero** two-arg accessor calls (grep for
    `["key", Type]` patterns: 0 hits) — all navigation is
    `["key"]` → `.getString()` / `.getTables()` / `.getBool()` etc.

### `TomlHexEscape` activation verdict at the revision ImThemes builds: **NO — NOT ACTIVE**

Static: identical to nph's case — ImThemes builds `toml_serialization` at the
same commit `b5b387e6` (lock-pinned): `format.nim` absent, `TomlReader.init`
default `flags = {}` (`reader.nim@b5b387e6:50-52`), `scanHexEscape` raises
without the flag (`lexer.nim:391-392`), consumer passes no flags
(`browseview.nim:193`).

Dynamic (`probes/probe_imthemes_profile.nim`, built against the **locked
revisions** — niprefs 0.3.5 + toml_serialization b5b387e6 + serialization
0.4.9 + faststreams 0.5.0 + stew 0.4.1; consumption strace-proven in
`raw/strace_imthemes_profile.log`; output
`raw/probe_imthemes_profile.stdout.log`):

```
imthemes_control: OK themes=1 name=[plain] bytes=[706C61696E]
imthemes_hex_45:  REJECTED TomlError: (2, 14) invalid hex escape, not supported by standard, please use `TomlHexEscape`
imthemes_hex_80:  REJECTED TomlError: (2, 11) invalid hex escape, not supported by standard, please use `TomlHexEscape`
```

**B-SEC-03 reachability for ImThemes: NOT REACHABLE** at `b5b387e6`. ImThemes
has a lockfile, so its resolution is stable by construction.

---

## 3. Counterfactual — the same-version commit `4aa8e22` (HEAD): **ACTIVE**

For contrast (NOT what either consumer resolves today), the identical probe
inputs through `4aa8e22`'s default `Toml` flavor
(`probes/probe_head_profile.nim`, `raw/probe_head_profile.stdout.log`):

```
typed/control:      OK exclude=@["plain"] bytes=[706C61696E]
typed/hex_45:       OK exclude=@["JosE"] bytes=[4A6F7345]
typed/hex_80:       OK exclude=@["<0x80>"] bytes=[80]
valuetree/control:  OK rootkind=Table bytes=[706C61696E]
valuetree/hex_45:   OK rootkind=Table bytes=[4A6F73E9]
valuetree/hex_80:   OK rootkind=Table bytes=[80]
```

At `4aa8e22`: `format.nim` exists; `Toml_v110_Flags` (containing
`TomlHexEscape`) is merged into every read by the reader itself
(`toml_serialization/reader.nim:62-64`,
`flags + flavorRuntimeFlags(Flavor)`), so `\xHH` is accepted with **no user
flags**, and `scanHexEscape` inserts the raw byte (`lexer.nim:416-429` at
that revision) — decoded string `"\x80"` is the lone byte `0x80`, invalid
UTF-8; `"Jos\xE9"` yields `4A 6F 73 E9` (invalid UTF-8) instead of
`4A 6F 73 C3 A9`. Verdict at HEAD: **TomlHexEscape ACTIVE — B-SEC-03
REACHABLE through both the typed and the value-tree call forms**.

Two commits with the same declared version ("0.2.18") thus differ in exactly
the security-relevant gating of B-SEC-03: `b5b387e6` = gated OFF by default,
`4aa8e22` = forced ON by default.

---

## 4. Verdict summary

| Consumer | Resolved dep commit | Call form | `TomlHexEscape` active? | B-SEC-03 reachable? |
|---|---|---|---|---|
| nph `2cacf6cc` | **`b5b387e6`** (nimbledeps snapshot, byte-verified; fresh nimble re-resolution today = same) | typed `Toml.loadFile(.nph.toml, NphConfig)`, un-keyed, no flags | **NO** (gate raises; static + dynamic) | **NO — not reachable** |
| ImThemes `d67592d` | **`b5b387e6`** (nimble.lock pin, checksum `76ae1c2a…`) | value-tree `Toml.loadFile(path, TomlValueRef)["themes"]`, un-keyed, no flags | **NO** (gate raises; static + dynamic) | **NO — not reachable** |
| (counterfactual) HEAD `4aa8e22` | untagged — nimble never resolves here | either form | **YES** (runtime flags forced) | **YES — reachable** |

Scope note: this record establishes reachability only. It makes **no severity
assessment** and files **no issue**.

## 5. Artifacts

```
bsec/evidence/
├── callsite.md            ← this file
├── callsite.json          ← machine-readable twin
├── dep_identity.md        ← version-string ambiguity + identity rule
├── probes/
│   ├── probe_nph_profile.nim        (# nim-check: skip)
│   ├── probe_imthemes_profile.nim   (# nim-check: skip)
│   └── probe_head_profile.nim       (# nim-check: skip)
└── raw/
    ├── build_commands.txt           (exact invocations + env)
    ├── probe_nph_profile.compile.log / .stdout.log
    ├── probe_imthemes_profile.compile.log / .stdout.log
    ├── probe_head_profile.compile.log / .stdout.log
    ├── strace_imthemes_profile.log  (dep-consumption proof, locked set)
    └── inputs/*.toml                (12 probe inputs, archived)
```

Binaries and nimcaches live only under `/tmp/bsec_callsite/`. Subject clone
byte-clean after all runs (`git status --porcelain` = 0 lines).
