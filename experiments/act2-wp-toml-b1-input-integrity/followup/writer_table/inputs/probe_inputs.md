# Probe inputs — WRITER-TABLE task (deterministic input definitions)

Subject: `nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`
(READ-ONLY clone; imported via `--path` only). Nim 2.2.10,
`--mm:orc --skipUserCfg --skipParentCfg --skipProjCfg`, neutral cwd `/tmp`,
binaries in `/tmp/wt_build` only.

Flavors (both exercised for every case):

| name in tables | definition |
|---|---|
| `v100` | `Toml_v100` — pre-declared in `toml_serialization.nim:26-30`: `createTomlFlavor(Toml_v100, automaticObjectSerialization = true, automaticPrimitivesSerialization = true, runtimeFlags = {}, version = TomlVersion_v100)` |
| `v110` | default `Toml` — `flavorRuntimeFlags = {TomlInlineTableNewline, TomlInlineTableTrailingComma, TomlHexEscape, TomlHourMinute, TomlStrictComma}`, `flavorTomlVersion = (1,1,0)` (`format.nim:26-41`) |

## Task 1 — string escape sweep (`probe_esc_sweep.nim`)

For each `b` in `0..255`: input is the single-byte Nim string `$chr(b)`
(Nim strings are byte arrays; `chr(b)` is the raw byte). Value document:

```
TomlValueRef(kind: TomlKind.Table, tableVal: TomlTableRef.new)
root.tableVal[]["v"] = TomlValueRef(kind: TomlKind.String, stringVal: <1-byte string>)
```

Emitted document shape (writer.nim:225-234 `writeKeyValue`): `"  v=" & token & "\n"`
(two-space indent, unspaced `=`, trailing LF). One file per case:
`raw/esc_<flavor>/b<HH>.toml` (HH = uppercase hex of `b`).

Note: the writer emits **only basic strings** (`writer.nim:131-164` has no
literal-string emission path), so the `emitted_literal` column of
`escapes.tsv` records the same basic-string token for every byte.

## Task 2 — key sweep (`probe_key_sweep.nim`)

Single-char keys: for each `b` in `0..255`, document
`root.tableVal[][chr(b)] = Int 7` → emitted `"  " & keyToken & "=7\n"`.
Files: `raw/keys_<flavor>/b<HH>.toml`.

Multi-char keys (identical construction, both flavors), files
`raw/keys_<flavor>/mc_<slug>.toml`:

| slug | Nim literal | key bytes |
|---|---|---|
| dot | `"a.b"` | 61 2E 62 |
| space | `"a b"` | 61 20 62 |
| dquote | `"a\"b"` | 61 22 62 |
| squote | `"a'b"` | 61 27 62 |
| hash | `"a#b"` | 61 23 62 |
| lbrack | `"a[b"` | 61 5B 62 |
| rbrack | `"a]b"` | 61 5D 62 |
| eq | `"a=b"` | 61 3D 62 |
| lbrace | `"a{b"` | 61 7B 62 |
| rbrace | `"a}b"` | 61 7D 62 |
| comma | `"a,b"` | 61 2C 62 |
| newline | `"a\nb"` | 61 0A 62 |
| eacute | `"\xC3\xA9"` | C3 A9 |
| uni | `"\xC9\x8E\xCA\x9E"` | C9 8E CA 9E |
| lone_e9 | `"\xE9"` | E9 |

## Task 3 — round-trip

Same-flavor re-parse of every emitted document
(`Flavor.decode(bytes, TomlValueRef)`); verdicts compare decoded value/key
bytes against the input bytes with Nim string `==` (exact byte comparison).
`tomllib` cross-check: `probes/oracle_tomllib.py` parses every file in
`raw/` with Python 3.12 `tomllib` (v1.0.0-only oracle).

## Task 4 — preservation

Derived from the Task 1 sweep: input byte hex vs decoded value hex,
same-flavor encode→decode. Categories: `byte_preserving` (decoded bytes ==
input byte), `value_preserving_only` (decoded bytes are the UTF-8 encoding
of the code point the writer's `runes()` pass produced from the raw byte —
bytes differ, scalar survives), `lossy` (decoded is `EF BF BD`, U+FFFD).

## Task 5 — `==` semantics (`probe_eq_semantics.nim`)

`TomlValueRef` values constructed directly:

- floats: `1.0`, `1.00000001`, `1.0000001`, `1.000001`, `1.00000005`,
  `0.99999994`, `0.99999988`, `NaN`, `Inf`, `-Inf`, `0.0`, `-0.0`, `1e-30`
- `Table{k: Int 1}` vs `InlineTable{k: Int 1}` (and value-differing variant)
- nested: `Table{k: Table{x: Float 1.0}}` vs `InlineTable{k: InlineTable{x: Float 1.0}}`
- kind mismatch: `Int 1` vs `Float 1.0`; round-trip case: encode
  `{v: Float 1.00000001}` → decode → compare against `Float 1.0`.
