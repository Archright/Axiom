# Probe 1 inputs — the `\e` escape (writer.nim:148)

Subject: nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9.
All inputs are in-memory Nim values (no input .toml files); the probe encodes
them under BOTH flavors (`Toml_v100`, runtimeFlags `{}` = TOML v1.0.0; default
`Toml`, runtimeFlags `Toml_v110_Flags` = TOML v1.1.0 flags) and records the
exact emitted bytes.

| case | input (Nim) | exact bytes |
|---|---|---|
| value | `TomlValueRef` table `{"esc": String}` with `stringVal = "\x1b" & "ABC"` | key `esc` (3 bytes `65 73 63`), value bytes `1B 41 42 43` |
| object | `type Obj = object s: string` with `s = "\x1b" & "ABC"` | field name `s`, value bytes `1B 41 42 43` |
| ctrl sweep | table `{"ctrl": String}` with `stringVal` = bytes `00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F 7F 80 FF` (34 bytes; 0x80/0xFF are NOT valid UTF-8) | as listed |

Probe source: `probes/probe1_esc.nim`. Emitted documents: `raw/esc_*.toml`.
