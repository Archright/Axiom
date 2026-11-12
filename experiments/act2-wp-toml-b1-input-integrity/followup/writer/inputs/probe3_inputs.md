# Probe 3 inputs — general round-trip under Toml_v100

Subject: nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9.
Each case is the in-memory `TomlValueRef` root table `{"v": value}` (key cases
use their own key with value int `1`), encoded with `Toml_v100.encode`
(runtimeFlags `{}` = TOML v1.0.0 flavor), decoded with
`Toml_v100.decode(_, TomlValueRef)`, re-encoded, and compared.

String-value cases (input bytes):

| label | input bytes |
|---|---|
| str_plain | `61 62 63` ("abc") |
| str_tab | `61 09 62` |
| str_nl | `61 0A 62` |
| str_cr | `61 0D 62` |
| str_esc | `1B` |
| str_quote | `say "hi"` (with real `22` quotes) |
| str_bs | `61 5C 62` (single backslash) |
| str_apos | `69 74 27 73` ("it's") |
| str_eacute_utf8 | `C3 A9` (é, valid UTF-8) |
| str_cjk | `E6 97 A5 E6 9C AC E8 AA 9E` (日本語) |
| str_emoji | `F0 9F 98 80` (U+1F600) |
| str_del | `7F` |
| str_lone_e9 | `E9` (lone byte, invalid UTF-8) |
| str_lone_ff | `FF` (lone byte, invalid UTF-8) |
| str_empty | (empty) |
| str_ctrl_mix | `61 00 62 1B 63 22 64 5C 65` |

Scalar / structure cases: int `42`, int `-17`, float `3.141592653589793`,
float `1.00000001`, bool `true`, offset date-time
`1979-05-27T07:32:00Z` (TomlDateTime date+time+Z), mixed array `[1,"a",true]`,
nested array `[[1,2],[3,4]]`, nested table `{a:{b:1}}`, inline table `{x:1}`,
array of two tables `{name}` under key `aot`.

Key cases (value = int 1): key_empty `""`, key_dot `a.b`, key_bracket `k[`,
key_space `k␠` (`6B 20`), key_apos `k'`, key_uni `ʎǝʞ` (`C9 8E CA 9E`).

Post-checks (not part of the input set): `==` tolerance demonstrations with
floats `1.0`, `0.99999994`, `0.99999988`, and a `Table` vs `InlineTable`
content-equality check.

Probe source: `probes/probe3_roundtrip.nim`. Emitted documents:
`raw/rt_v100_*.toml`.
