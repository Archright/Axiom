# serde_json v1.0.154 — registry pre-warm + charon dry-run discovery inventory

Date: 2026-10-31. Throwaway copy under `/tmp/axexp/`; original subject clone (`<workspace>/json`) untouched (HEAD re-verified, status clean after all steps). No `bin/ax prove` run. No git mutations.

## 1. Copy identity (step 1)

- Source: `<workspace>/json` → Copy: `/tmp/axexp/serde_json_prewarm` (`cp -a`)
- Copy `git rev-parse HEAD`: `8c535a260ce561eaab4111aafc29038eb9f77ff3` (matches expected)
- Copy `git status --porcelain`: empty (clean)
- Original re-verified after all steps: HEAD `8c535a260ce561eaab4111aafc29038eb9f77ff3`, status clean.

## 2. Toolchain pins (step 3 pin check)

| Tool | Version |
|---|---|
| charon | `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)` — matches pin |
| cargo | 1.95.0 (f2d3ce0bd 2026-03-21) |
| rustc | 1.95.0 (59807616e 2026-04-14) |

## 3. cargo fetch / registry pre-warm (step 2)

- Command: `cd /tmp/axexp/serde_json_prewarm && cargo fetch` — **exit 0, wall 2.12s**
- Output verbatim (first line): `Locking 46 packages to latest compatible versions`
- serde_json v1.0.154 downloaded into the local cargo registry during this fetch (was absent before; only 1.0.142/149/150 present).
- Generated `Cargo.lock` path: `/tmp/axexp/serde_json_prewarm/Cargo.lock` (copy preserved at `/tmp/axexp/Cargo.lock.pinned`)
- `sha256sum Cargo.lock` = `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4`

### Lock dependency version table (47 lock entries; `serde_json 1.0.154` itself appears twice: the workspace member as `local`, plus a registry copy pulled by dev-deps)

Direct deps of subject:

| Package | Version |
|---|---|
| itoa | 1.0.18 |
| memchr | 2.8.3 |
| serde_core | 1.0.229 |
| serde | 1.0.229 (uses serde_core 1.0.229) |
| zmij | 1.0.23 |

Other lock entries (dev/build/transitive): ar_archive_writer 0.5.3, automod 1.0.17, cc 1.10.0, cfg-if 1.0.5, dissimilar 1.0.11, equivalent 1.0.3, find-msvc-tools 0.1.15, foldhash 0.2.0, glob 0.3.4, hashbrown 0.17.1, indexmap 2.14.2, indoc 2.0.8, libc 0.2.191, object 0.39.1, proc-macro2 1.0.107, psm 0.1.32, quote 1.0.47, ref-cast 1.0.27, ref-cast-impl 1.0.27, rustversion 1.0.23, serde_bytes 0.11.19, serde_derive 1.0.229, serde_spanned 1.1.2, serde_stacker 0.1.14, shlex 2.0.1, stacker 0.1.25, syn 2.0.119, syn 3.0.9, target-tuple 1.0.2, termcolor 1.4.1, toml 1.1.8+spec-1.1.0, toml_datetime 1.1.2+spec-1.1.0, toml_parser 1.1.5+spec-1.1.0, toml_writer 1.1.3+spec-1.1.0, trybuild 1.0.122, unicode-ident 1.0.27, winapi-util 0.1.11, windows-link 0.2.1, windows-sys 0.61.2, winnow 1.0.4.

## 4. Timed charon extraction (step 3)

Command (exactly as the lane runs it):

```
cd /tmp/axexp/serde_json_prewarm && charon cargo --dest-file /tmp/axexp/subject.llbc -- --target-dir /tmp/axexp/charon-target
```

- **Exit code 0. Wall time 5.86s** (`/usr/bin/time -f`); max RSS 338,328 KB (~330 MB). Fresh `/tmp/axexp/charon-target` (first build of all deps there). Budget 120s → **24.6x under measured; no ToolchainFailure.**
- Output `/tmp/axexp/subject.llbc` = 27,695,318 bytes; embedded `charon_version: "0.1.281"`, `has_errors: false`.
- LLBC-embedded options of record: `ullbc: false` (structured llbc), `no_dedup_serialized_ast: false` (**hash-consed dedup ON** — relevant for consumers), `monomorphize: false`, `extract_opaque_bodies: false`, target `x86_64-unknown-linux-gnu`, pointer size 8, little-endian.
- Verbatim log tail:
```
   Compiling serde_core v1.0.229
   Compiling zmij v1.0.23
   Compiling serde_json v1.0.154 (/tmp/axexp/serde_json_prewarm)
   Compiling memchr v2.8.3
   Compiling itoa v1.0.18
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 5.71s
```

## 5. LLBC inventory (step 4)

Top-level: `{"charon_version", "translated", "has_errors"}`; all items under `translated`.

| Collection | Count |
|---|---|
| fun_decls | 2134 total = 296 `null` + 675 `Opaque` + 1 `Intrinsic` + **1162 Structured (with bodies)** |
| type_decls | 240 |
| trait_decls | 96 |
| trait_impls | 606 |
| global_decls | 382 |
| ordered_decls | 2491 |
| embedded source files | 151 (serde_json 15, core 100, alloc 20, serde_core 11, zmij 2, itoa 1, memchr 2) |
| structured fun_decls by origin | is_local=true 1157, is_local=false 5 |

Fact: deps (memchr/itoa/zmij/serde_core/core/alloc) appear as spans + opaque decls; only serde_json bodies are Structured (1157 local), consistent with `extract_opaque_bodies: false`.

### Encoding notes (for future LLBC consumers)

- Names: `item_meta.name` = list of segments `{"Ident": [name, disambiguator]}` / `{"Impl": {"Trait": id} | {"Ty": ...}}` / `{"Builtin": [{"Tuple": n}, disamb]}`, joined with `::`.
- Types/spans/consts are hash-consed: first occurrence `{"Value": [id, payload]}`, later `{"Deduplicated": id}`. Scalar types are e.g. `{"Scalar": {"Integer": {"Unsigned": "U8"}}}`, bool is `{"Scalar": "Bool"}`; unit is `{"Builtin": [{"Tuple": 0}, ...]}`. A scan resolving Deduplicated type ids from Value occurrences leaves 475 ids unresolved in type contexts (≤3 of the type rejections below may be such pool artifacts).
- Statement kinds observed across all 1162 structured bodies: StorageLive 5637, Assign 3599, StorageDead 3433, Call 1320, Return 1161, Drop 951, Switch 353, Borrowck 209, PlaceMention 39, Loop 22, Assert 19. (No bare Goto/SwitchInt/Continue — structured output.)
- Assign rvalues observed: Ref 1392, Use 1235, Aggregate 516, Discriminant 301, UnaryOp 100, BinaryOp 52, Repeat 3. BinaryOp ops: Lt 16, Eq 12, AddChecked 7, Le 5, BitOr 3, SubChecked 3, Ge 2, ShlWrap 1, ShrWrap 1, BitAnd 1, DivUB 1. Operands: Move 669, Copy 537, Const 133.

### In-grammar candidate scan (strict)

Grammar applied (per task): signature params + return ONLY u8/u32/bool (exact scalars); body statements only StorageLive/StorageDead/Assign/Return/Abort-equivalent (Panic), with Assign rvalues only Use or BinaryOp(AddChecked/Eq); reject Switch/SwitchInt/Call/Loop/Goto and any other kind/rvalue.

Result: **13 candidates** (not zero). Rejection histogram over the 1162 structured decls:

- `signature_types`: 1148 — first offending type kind: Ref 669, Adt 423, Scalar-other (e.g. u64/usize/char) 26, TypeVar 21, Array 6, other 3
- `Switch`: 1
- no decl was rejected at statement level for Call/Loop/Goto/rvalue kinds (the type filter is the binding constraint)
- supplementary: 78 decls have all-scalar params (returns disqualify them); 0 fail only on a `()` return.

Candidates (all zero-param consts; body shape `StorageLive → Assign(Use(Const)) → Return`):

| # | Name | Ret | Source line | Body |
|---|---|---|---|---|
| 1 | `serde_json::ser::BB` | u8 | `const BB: u8 = b'b'; // \x08` — src/ser.rs:2135 | SL→A→R |
| 2 | `serde_json::ser::TT` | u8 | `const TT: u8 = b't'; // \x09` — src/ser.rs:2136 | SL→A→R |
| 3 | `serde_json::ser::NN` | u8 | `const NN: u8 = b'n'; // \x0A` — src/ser.rs:2137 | SL→A→R |
| 4 | `serde_json::ser::FF` | u8 | `const FF: u8 = b'f'; // \x0C` — src/ser.rs:2138 | SL→A→R |
| 5 | `serde_json::ser::RR` | u8 | `const RR: u8 = b'r'; // \x0D` — src/ser.rs:2139 | SL→A→R |
| 6 | `serde_json::ser::QU` | u8 | `const QU: u8 = b'"'; // \x22` — src/ser.rs:2140 | SL→A→R |
| 7 | `serde_json::ser::BS` | u8 | `const BS: u8 = b'\\'; // \x5C` — src/ser.rs:2141 | SL→A→R |
| 8 | `serde_json::ser::UU` | u8 | `const UU: u8 = b'u';` — src/ser.rs:2142 | SL→A→R |
| 9 | `serde_json::ser::__` | u8 | `const __: u8 = 0;` — src/ser.rs:2143 | SL→A→R |
| 10 | `serde_json::read::<impl serde_json::read>::should_early_return_if_failed` | bool | `const should_early_return_if_failed: bool = true;` — src/read.rs:426 | SL→A→R |
| 11 | same name (2nd impl) | bool | `= false;` — src/read.rs:692 | SL→A→R |
| 12 | same name (3rd impl) | bool | `= false;` — src/read.rs:784 | SL→A→R |
| 13 | same name (4th impl) | bool | `= R::should_early_return_if_failed;` — src/read.rs:857 | SL→A→R |

Notes: source lines extracted from the LLBC's embedded file contents via each decl's `item_meta.span` (file_id + beg line); all 13 verified verbatim against embedded sources. All 13 are non-`pub` const items (read.rs ones are `public: true` in attr_info — trait-impl-associated consts). None is a `fn` with u8/u32/bool parameters; the strict grammar admits only consts in this subject. Full machine-readable detail: `/tmp/axexp/scan_results.json`.

### Example crate-qualified fun_decl names (20 local, 1 external)

serde_json::de::from_trait, serde_json::de::from_reader, serde_json::de::from_slice, serde_json::de::from_str, serde_json::error::make_error, serde_json::error::parse_line_col, serde_json::error::starts_with_digit, serde_json::ser::key_must_be_a_string, serde_json::ser::float_key_must_be_finite, serde_json::ser::format_escaped_str, serde_json::ser::format_escaped_str_contents, serde_json::ser::to_writer, serde_json::ser::to_writer_pretty, serde_json::ser::to_vec, serde_json::ser::to_vec_pretty, serde_json::ser::to_string, serde_json::ser::to_string_pretty, serde_json::ser::indent, serde_json::value::parse_index, serde_json::value::to_value; external: core::ptr::drop_glue.

## 6. Preserved artifacts (step 5)

| Path | sha256 |
|---|---|
| `/tmp/axexp/subject.llbc` (27,695,318 B) | `f6eff161420fe8fefc4b2e7c5986c8fad5f3b3050cb12dc33b2881d59566f569` |
| `/tmp/axexp/serde_json_prewarm/Cargo.lock` (also `/tmp/axexp/Cargo.lock.pinned`) | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` |
| `/tmp/axexp/scan_results.json` (full scan output) | `6dacb9cfb99b815809c1f59b11b5fdf21564dd1a101f0c056b562b757363edca` |
| `/tmp/axexp/charon_run.log` | `b1a51d8540b2dfed62e0c7bffe6c838fe538bdfb02c05b67febc8d713468a6aa` |
| `/tmp/axexp/charon_time.txt` | `b57789693985dd790c09e25f372d84e1a83a9ba427a050f938957a1c0510d56d` |

Also present: `/tmp/axexp/scan_llbc2.py` (scanner, reproducible), `/tmp/axexp/serde_json_prewarm/` (throwaway copy incl. warmed registry side effects), `/tmp/axexp/charon-target/`.

## 7. Verbatim failures

None. `cargo fetch` exit 0; charon exit 0; scanner exit 0. (During scanner development two intermediate scripts crashed on encoding edge cases — null fun_decl entries, string body variants, BinaryOp dict ops — all fixed in the final `scan_llbc2.py`; final run exit 0.)
