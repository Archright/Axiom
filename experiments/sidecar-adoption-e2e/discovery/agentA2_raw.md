The sweep is complete — the pool of shape-(a) functions is now fully mapped. I have everything needed for the final report.

# nim-stew read-only defect-candidate probe — final report

**Commit check:** `git rev-parse HEAD` = `1853f20bdfeda61331a0b7e02f7aace0e88a0dfe` — **matches** the expected commit exactly; tree is clean. Nothing was created/modified/deleted; no builds or tests were run (only `git rev-parse`, `ls`, `grep`/Read/Grep of repo files).

**Honest bottom line:** three candidates satisfy the shape exactly (all in `stew/endians2.nim`, plus one near-exact in `stew/bitops2.nim`). However, hand-verification suggests each P **actually holds** on a mainstream C backend — the suspicion in each case is structural (untested widths, backend/codegen seams, generic-instantiation fragility), so defect confidence is low. They are delivered as mechanically checkable propositions for a prover, with the full screened-out list below.

---

## Candidate 1 — `swapBytesNim(x: uint16)` (purest shape match)

- **Module:** `stew/endians2.nim` (private func, lines 62–63)
- **Signature + body (verbatim):**
  ```nim
  func swapBytesNim(x: uint16): uint16 = (x shl 8) or (x shr 8)
  ```
- **Shape (a):** exact — params/return pure `uint16`; body is only literals, the identifier `x`, and boolean/bitwise operators; zero calls (no proc/template/conversion/`sizeof`), no const, no cast, no if/case, no string/seq/object/float.
- **P (closed grammar):** for input `x = 291` (0x0123): **`result == 8961`** (0x2301).
- **Ground citations:** `stew/endians2.nim:80-81` — docstring: *"Reverse the bytes within an integer, such that the most significant byte changes place with the least significant one"*. Byte-level semantics pinned by `tests/test_endians2.nim:15` (`0x0123'u16.toBytesBE == [0x01, 0x23]`) and `:21`/`:27`/`:34` (toBytesLE/fromBytes round-trips exercise the swap for uint16 on little-endian machines). Module contract at `stew/endians2.nim:7-9`.
- **Suspected input:** `x = 256` (0x0100), expected `result == 1`. The formula depends on `shl` on `uint16` wrapping at 16 bits (Nim keeps the operand width; C-style integer promotion would leak `0x0100` from the `shl 8` lane into the OR, yielding 257). Notably this overload has **zero direct `swapBytes` assertions anywhere in the repo** (only transitive byte-array tests), so a width-promotion regression (e.g., JS/other backend codegen) would be invisible to the suite.
- **Confidence:** shape fit high; that P fails — low (~5%). Hand-computation confirms P holds on a width-correct backend.

## Candidate 2 — `swapBytesNim(x: uint32)` (direct test grounding)

- **Module:** `stew/endians2.nim` (lines 65–68)
- **Signature + body (verbatim):**
  ```nim
  func swapBytesNim(x: uint32): uint32 =
    let v = (x shl 16) or (x shr 16)

    ((v shl 8) and 0xff00ff00'u32) or ((v shr 8) and 0x00ff00ff'u32)
  ```
- **Shape (a):** exact — same as candidate 1; hex literals are literals; `let` + operators only.
- **P (closed grammar):** for input `x = 19088743` (0x01234567): **`result == 1732584193`** (0x67452301).
- **Ground citations:** `stew/endians2.nim:84` — docstring example `doAssert swapBytes(0x01234567'u32) == 0x67452301`; `tests/test_endians2.nim:40` — `doAssert 0x01234567'u32.swapBytes() == 0x67452301` (direct).
- **Suspected input:** `x = 4278255360` (0xFF00FF00), expected `result == 16711935` (0x00FF00FF). This uses the nonstandard **shift-before-mask** form (`(v shl 8) and 0xff00ff00` instead of the canonical `(v and 0xff00ff00) shl 8`); correctness requires the two OR lanes' discarded bytes to be exactly complementary for *every* input — at this input both lanes contribute to the result simultaneously, the maximal-tension case. Also the first stage reproduces `x` verbatim for halfword-palindromic inputs, so all discriminating work falls on stage two.
- **Confidence:** shape fit high; that P fails — very low (~2%). Hand-verified on 0x01234567, 0x80008000, 0xFF00FF00 — lane coverage is exact, so the proposition should hold.

## Candidate 3 — `rotateLeft` (near-exact shape; distinct failure mode)

- **Module:** `stew/bitops2.nim` (lines 399–407)
- **Signature + body (verbatim):**
  ```nim
  func rotateLeft*(v: SomeUnsignedInt, amount: SomeInteger):
      SomeUnsignedInt {.inline.} =
    ## Left-rotate bits in an unsigned value
    # using this form instead of the one below should handle any value
    # out of range as well as negative values.
    # taken from: https://en.wikipedia.org/wiki/Circular_shift#Implementing_circular_shifts
    const mask = 8 * sizeof(v) - 1
    let amount = int(amount and mask)
    (v shl amount) or (v shr ( (-amount) and mask))
  ```
- **Shape (a):** near-exact, with two disclosed gray areas: a *function-local* `const` (the ban is module-level const references — this is a literal-defined local), and compiler-magic `sizeof` + built-in `int()` conversion (not user-defined calls). No user-defined proc/func/template is called; instantiable with pure `uint`/`int` params and pure `uint` return.
- **P (closed grammar):** for `v = 65`, `amount = -2147483648`: **`result == 65`** (rotation by INT32_MIN ≡ 0 mod 8 must be the identity).
- **Ground citations:** `stew/bitops2.nim:402-403` — comment explicitly claims the form *"should handle any value out of range as well as negative values"* (plus the cited circular-shift reference at `:404`); `tests/test_bitops2.nim:63,65` ground the semantics for in-range amounts (`rotateLeft(0b01000001'u8, 2) == 0b00000101`).
- **Suspected input:** `v = 65`, `amount = -2147483648`. The repo has **zero tests with negative or out-of-range `amount`** (only `2` at test lines 63/65), and the "any negative value" claim silently rests on two assumptions: (1) `amount and mask` accepts a mixed-width operand — for instantiations where `amount`'s type is narrower than `int` (e.g. `int8`/`uint16`, which `SomeInteger` admits) this is plausibly a compile-time type mismatch at `bitops2.nim:406`, and (2) two's-complement semantics of `and` on negatives. If either assumption breaks, the documented "any value" claim fails; concretely `rotateLeft(65'u8, 2'i8)` is suspected not to even typecheck.
- **Confidence:** shape fit high (with gray areas disclosed); that P fails at the given value on a mainstream C backend — low. Hand-trace: `-2147483648 and 7 = 0` → identity → P holds; the residual risk is the instantiation/portability seam, not the arithmetic.

---

## Screening table — everything else examined and why it fails shape (a)

| Location | Symbol(s) | Failure reason |
|---|---|---|
| bitops2.nim:291, 304, 307, 323, 340, 365, 377, 391, 409, 471 | `countOnes`, `countZeros`, `parity`, `firstOne`, `log2trunc`, `leadingZeros`, `trailingZeros`, `nextPow2`, `rotateRight`, `changeBitBE` | call user-defined funcs/templates (`countOnesNim`, `log2truncNim`, `bitsof`, `firstOne`, `changeBit`, …) |
| bitops2.nim:36 | `nextPow2Nim` | `when bitsof(x)` calls the user-defined `bitsof` template (line 29) |
| bitops2.nim:52–71 | `firstOneNim` ×3 | local `const lookup` array table + `cast`; u8/u16 and u64 overloads call `firstOneNim(uint32)` |
| bitops2.nim:73–102 | `log2truncNim` ×2 | local `const lookup` array tables |
| bitops2.nim:104–120, 122–133 | `countOnesNim`, `parityNim` | use `cast[int](uint(...))` + type conversions — beyond the "only literals/identifiers/operators/if-case" body grammar (otherwise compliant) |
| bitops2.nim:153–289 | `*Builtin` family | wrap `importc`/declared procs or call user-defined helpers; `checkedScan` template |
| bitops2.nim:420–557 | `getBit`/`setBit`/… family | templates or `var` array/byte-indexed params; `getBitBE` calls `mostSignificantBit` |
| endians2.nim:79–185 | `swapBytes`, `toBytes`, `fromBytes`, `toBE/LE`… | arrays/openArray params, `copyMem`, or call `swapBytes` |
| leb128.nim:53 | `Leb128.len` | **module-level const** `lengths` (line 41) + calls `log2trunc` — double disqualifier |
| base10.nim:21,65; base32.nim:68,79; base36.nim:52,57; base58.nim:50,55 | `maxLen`, `encodedLength`, `decodedLength` | return `int8` (not `int`), `typedesc`/enum-typed params |
| enums.nim:91,100 | `contains`, `checkedEnumAssign` | enum types, macro calls, `cast[E]` |
| objects.nim:83,91 | `isZeroMemory`, `isDefaultValue` | generic object params, `cast`/`addr` |
| keyed_queue.nim, sorted_set*.nim, interval_set.nim, io2.nim, windows/acl.nim, bitseqs.nim, arrayops.nim, byteutils.nim, ctops.nim, shims/* | all remaining `int`/`bool`-returning funcs | object/seq/openArray/string/set params or `importc` syscall wrappers |

**Side finding (not shape-eligible, but the repo's one real doc inconsistency):** the documented identity `firstOne(x) == trailingZeros(x) + 1` (`stew/bitops2.nim:327`) is false at `x = 0` by the same file's own specs — `firstOne(0) == 0` (`:325`, test `tests/test_bitops2.nim:26`) while `trailingZeros(0) == bitsof(x)` (`:379`, test `:68`), giving `0 == width + 1`. Both functions fail shape (a) (they call helpers), so it cannot be delivered as a candidate, but it is a genuine grounded-P violation if shape constraints are ever relaxed.