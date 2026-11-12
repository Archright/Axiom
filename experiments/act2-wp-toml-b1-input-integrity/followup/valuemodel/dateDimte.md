# dateDimte.md — exact blast radius of the `dateDimte` typo (value_ops.nim:32,:36)

Subject: `<workspace>/nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (READ-ONLY, byte-clean before/after — `raw/baseline_clean.txt`, `raw/final_clean.txt`, `raw/subject_untouched.diff` empty).
Fact-finding only: no severity, no CVSS, no issue filed. All errors verbatim from `raw/`.

## 1. The defect

`toml_serialization/value_ops.nim:29-36` (innerValue, per-T instantiated proc, line 14):

```nim
elif T is TomlDate:
  if n.kind == TomlKind.DateTime:
    if n.dateTime.date.isSome:
      result = n.dateDimte.date.get            # line 32 — 'dateDimte' undefined
elif T is TomlTime:
  if n.kind == TomlKind.DateTime:
    if n.dateTime.time.isSome:
      result = n.dateDimte.time.get            # line 36 — 'dateDimte' undefined
```

`grep -c dateDimte` over the whole repo = 2 (both here).

## 2. Which API surfaces are affected

`innerValue` has exactly TWO callers in the entire repo (grep evidence):

| caller | site | affected instantiations |
|---|---|---|
| `proc []*(node: TomlValueRef, name: string, T: type): T` | value_ops.nim:86-87 (inline call at :87) | T=TomlDate → error at :32; T=TomlTime → error at :36 |
| `proc []*(node: TomlValueRef, index: int, T: type): T` | value_ops.nim:97-98 (inline call at :98) | identical — same single innerValue body |

No other accessor routes through innerValue: `len` (:70), untyped `[]` string (:79) and int (:89), `hasKey` (:100), `contains` ×2 (:105,:110), `[]=` (:115), `{}` (:120), `getOrDefault` (:130), `{}=` (:136), `delete` (:146), `copy` (:153-196) never call it. No other module calls innerValue either (`grep -rn innerValue` → only value_ops.nim:14,87,98). The accessors are reachable only via `import toml_serialization/value_ops` (toml_serialization.nim exports desc, reader, writer, types, format, decoder — not value_ops).

Runtime proof for the int-keyed accessor: `probes/q4f_array_typed_tomldate.nim` (`doc["arr"][0, TomlDate]`) fails with the SAME `value_ops.nim(32,19)` error (`raw/q4f_array_typed_tomldate.compile.out`) — the blast radius is the T dimension, not the accessor dimension.

## 3. TomlDateTime is NOT affected

The `T is TomlDateTime` branch (:26-28) reads `n.dateTime` directly and contains no typo:

```nim
elif T is TomlDateTime:
  if n.kind == TomlKind.DateTime:
    result = n.dateTime
```

Runtime evidence (`probes/q4d_tomldatetime_ok.nim`, `raw/q4d_tomldatetime_ok.out`): `doc["dt", TomlDateTime]` compiles and returns full values for all four DateTime variants — Z datetime (date+time+zone all Some), offset datetime `-05:00` (zone Some, positiveShift=false hourShift=5), date-only (date Some, time None), time-only (date None, time Some). `probes/q2r_tomldatetime.nim` additionally shows a mismatching Int kind yields an all-None TomlDateTime. The dateDimte typo is confined to the TomlDate/TomlTime extraction branches; TomlDateTime extraction works.

## 4. Direct typed decode is NOT affected (reader path)

`probes/q4e_direct_decode.nim` (`raw/q4e_direct_decode.out`):

```
Toml.decode("d = 1979-05-27", TomlDate, "d")        -> (year: 1979, month: 5, day: 27)
Toml.decode("t = 07:32:00", TomlTime, "t")          -> (hour: 7, minute: 32, second: 0, subsecond: 0)
Toml.decode("dt = 1979-05-27T07:32:00Z", TomlDateTime, "dt") -> full value incl. zone
```

All three compile and run — the decoder/reader path never instantiates innerValue.

## 5. Verbatim compile errors (pristine subject)

`doc["d", TomlDate]` — `probes/q4a_accessor_tomldate.nim`, `raw/q4a_accessor_tomldate.compile.out` (COMPILE_EXIT=1):

```
probes/q4a_accessor_tomldate.nim(15, 12) template/generic instantiation of `[]` from here
toml_serialization/value_ops.nim(87, 13) template/generic instantiation of `innerValue` from here
toml_serialization/value_ops.nim(32, 19) Error: undeclared field: 'dateDimte' for type types.TomlValueRef [type declared in <workspace>/nim-toml-serialization/toml_serialization/types.nim(106, 3)]
```

`doc["t", TomlTime]` — `probes/q4b_accessor_tomltime.nim`, `raw/q4b_accessor_tomltime.compile.out` (COMPILE_EXIT=1): identical except the instantiation chain starts at the probe's :12 and the error is at `value_ops.nim(36, 19)`.

Both-in-one-file (`probes/q4c_both_in_one.nim`, `raw/q4c_both_in_one.compile.out`): Nim reports ONLY the :32 error and stops — one dateDimte diagnostic per compilation; the :36 error surfaces only in a dedicated compile.

## 6. Repairing the typo is NOT sufficient (second, independent defect)

The removed repro driver's stage 2 patched a /tmp-ONLY copy (`sed s/dateDimte/dateTime/g`; diff of exactly two tokens in `raw/q4_patched_copy.diff`; subject untouched — `raw/subject_untouched.diff` empty). The same probes against the patched copy (COMPILE_EXIT=1):

```
/tmp/valuemodel_build/patched_subject/toml_serialization/value_ops.nim(32, 33) Error: type mismatch
Expression: get(n.dateTime.date)
  [1] n.dateTime.date: Option[types.TomlDate]

Expected one of (first mismatch at [position]):
[1] template get(T: typedesc[tuple]; i: static int): untyped
```

and the mirror at `(36, 33)` for `get(n.dateTime.time)` (`raw/q4b_accessor_tomltime.compile.patched.out`). Cause: `isSome`/`get` on `Option` need `std/options` in scope; `value_ops.nim:10-12` imports only `std/[tables, typetraits, strutils], ./types, ./private/utils`, and `types.nim` imports `std/options` (:11) without re-exporting it (its export list is `errors` only, :16-17). The only visible `get` candidate is the tuple-indexing template. So the TomlDate/TomlTime accessor rows are unreachable at compile time EITHER WAY — by the typo in the pristine tree, and by Option-scope after a minimal typo fix.

## 7. Blast radius summary (factual, no severity)

- Affected: `node[k, TomlDate]` and `node[k, TomlTime]` (and `node[i, TomlDate/Time]`) — compile-time failure, on any receiver.
- Unaffected: `TomlDateTime` typed access (works), direct `Toml.decode` of TomlDate/TomlTime/TomlDateTime (works), every other accessor and every other T (see innervalue.tsv — several of those fail to compile for reasons unrelated to dateDimte).
- The reader/writer/decoder machinery never instantiates innerValue; only the two typed `[]` accessors do.
