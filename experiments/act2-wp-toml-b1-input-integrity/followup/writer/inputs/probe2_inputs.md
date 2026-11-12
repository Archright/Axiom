# Probe 2 inputs — key escaping (writer.nim writeKey, lines 166-181)

Subject: nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9.
All inputs are in-memory `TomlValueRef` values; each key is `k` + one probed
character. Three write paths are exercised per character:

1. **kv** — top-level table `{ "k<c>" = 7 }` (key/value line).
2. **hdr** — nested table `{ "t<c>" = { inner = 1 } }` (exercises the nested
   write path; the writer renders it as a dotted key, not a `[header]`).
3. **inl** — inline-table member `{ t = { "i<c>" = 7 } }`.

Probed characters: `[` `]` `=` `{` `}` `,` (space) plus reference cases
`.` `"` `#` `'`, plain `k`/`ka`.

| probed key (bytes after `k`) | byte |
|---|---|
| `k[` | `6B 5B` |
| `k]` | `6B 5D` |
| `k=` | `6B 3D` |
| `k{` | `6B 7B` |
| `k}` | `6B 7D` |
| `k,` | `6B 2C` |
| `k ` | `6B 20` |
| `k.` / `k"` / `k#` / `k'` / `ka` / `k` | references |

Probe source: `probes/probe2_keys.nim`. Emitted documents: `raw/key_*.toml`
(file-name suffix is the hex of the key bytes).
