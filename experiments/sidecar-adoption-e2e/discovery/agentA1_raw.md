# Defect-candidate report — nim-stew @ `1853f20bdfeda61331a0b7e02f7aace0e88a0dfe`

`git rev-parse HEAD` returned exactly the expected commit; no difference. Repo was only read; nothing created, modified, or executed.

The only functions in the repository matching shape (a) are the four length-estimator pairs in the `baseN` modules — `(typedesc, int) -> int` with bodies of literals and `*`/`div`/`+` only. Everything else calls helpers, uses template/macro machinery, or takes arrays/objects/strings (full screening list at the end). One caveat applies to all three candidates: the `btype: typedesc[...]` parameter is a compile-time-only discriminator (erased at codegen), so the *runtime* signature is `(int) -> int`; if you count the typedesc parameter as a violation of "takes only int", then no function in this repo satisfies the strict shape.

---

## Candidate 1 — `base36.decodedLength` (strong)

- **Module / symbol**: `stew/base36.nim:57` — `decodedLength*`
- **Signature + body** (quoted exactly):
  ```nim
  func decodedLength*(btype: typedesc[Base36Types], length: int): int =
    ## Return estimated length of decoded value of Base36 encoded value of length
    ## ``length``.
    return (length * 179) div 277
  ```
- **P (closed grammar)**: `result == (length + 4)`
- **Ground citations**:
  - `stew/base58.nim:55-58` — the sibling API with the *identical docstring* implements exactly `result = length + 4` ("estimated length of decoded value of Base58 encoded value of length length").
  - `stew/base36.nim:134-138` — base36's own `decode` hard-requires `payload.len + 4` output bytes (`let payload = instr[1..^1]; let binsz = payload.len + 4; if outbytes.len < binsz: … Overrun`), i.e. the buffer needed to decode an encoded value is `length + 4`.
  - `tests/test_base36.nim:84-85` — the repo's own test pins it: `Base36.decode("k1", decres, decsize) == Overrun` with `decsize == 5` (encoded value with 1 payload char → 5 bytes required).
  - `stew/base36.nim:217` — the module's own string wrapper sizes by `instr.len + 4`, matching the sibling convention, not by `decodedLength`.
  - Repo-wide convention: `decodedLength` is *the* decode-buffer sizer (`tests/test_base64.nim:103`, `tests/test_base32.nim:189`).
- **Suspected concrete input**: `length = 1` → returns `(1*179) div 277 = 0`, but P (grounded by test_base36.nim:84-85 and base58.nim:58) demands `5`. Any caller sizing a base36 decode buffer the way the base32/base64 tests do gets a guaranteed `Overrun` for every non-empty input, since `(L*179) div 277 < L + 4` for all L ≥ 0. The function has **zero callers** in the repo (dead public API), and `base58.decodedLength` was evidently updated to `length + 4` while base36's was left at the generic 256→36 ratio — the inconsistency is the defect.
- **Confidence**: **0.85**. The P failure is arithmetically certain; the only mitigations are the dead-code status and the word "estimated".

## Candidate 2 — `base64.decodedLength`, Pad branch (medium)

- **Module / symbol**: `stew/base64.nim:62` — `decodedLength*`
- **Signature + body**:
  ```nim
  func decodedLength*(btype: typedesc[Base64Types],
                      length: int): int {.inline.} =
    ## Return estimated length of decoded value of Base64 encoded value of length
    ## ``length``.
    when (btype is Base64Pad) or (btype is Base64UrlPad):
      result = ((length + 3 - 1) div 3) * 4
    elif (btype is Base64) or (btype is Base64Url):
      result = (length * 4 + 3 - 1) div 3
  ```
- **P (closed grammar)**: `result == 1` (for input `length = 4`)
- **Ground citations**: `stew/base64.nim:153-155` — on Overrun, `outlen` is "number of bytes required" to store decoded bytes; `stew/base64.nim:165-168` — decode enforces `decodedLength(len(instr))` as exactly that requirement; `tests/test_base64.nim:7` — vector `"f" ↔ "Zg=="` proves a 4-char padded string decodes to **1** byte (test_base64.nim:102-108 asserts the decoded seq equals `plain`, length 1; base64.nim:216-223 writes `k = 1`).
- **Suspected concrete input**: `length = 4` → returns `((4+2) div 3) * 4 = 8`, i.e. decode reports "8 bytes required" for a decode that stores 1 byte; a right-sized caller (1-byte buffer) gets a spurious `Overrun` with a false `outlen`. Same defect in the unpadded branch (`decodedLength(2) = 3` vs the 1 byte `"AA"` decodes to).
- **Confidence**: **0.55**. The failure is certain, but `tests/test_base64.nim:144-145` *enshrines* the inflated value (`decsize == Base64.decodedLength(2)`), so the slack looks intentional and the defect is doc-contract wording vs implementation rather than a functional break.

## Candidate 3 — `base64.encodedLength` (medium-low)

- **Module / symbol**: `stew/base64.nim:56` — `encodedLength*`
- **Signature + body**:
  ```nim
  func encodedLength*(btype: typedesc[Base64Types],
                      length: int): int {.inline.} =
    ## Return estimated length of Base64 encoded value for plain length
    ## ``length``.
    result = (((length + 2) div 3) * 4) + 1
  ```
- **P (closed grammar)**: `result == 4` (for input `length = 1`)
- **Ground citations**: `stew/base64.nim:79-80` — on Overrun, `outlen` is "number of characters required"; `stew/base64.nim:87-88` — encode enforces `encodedLength` as that requirement; `tests/test_base64.nim:7` + `93-99` — encoding 1 byte produces `"Zg=="`, i.e. **4** characters are actually required.
- **Suspected concrete input**: `length = 1` → returns `((1+2) div 3)*4 + 1 = 5`, so encode rejects a correctly-sized 4-char buffer with `Overrun` claiming 5 characters are required. `tests/test_base64.nim:142-143` itself demonstrates the mismatch (`encsize == Base64.encodedLength(1)` = 5 for a 4-char output).
- **Confidence**: **0.5** — same "intentional +1 slack vs 'required' doc wording" caveat as candidate 2.

---

## Screening record (everything else examined, with failure reason)

| Location | Function(s) | Failure reason |
|---|---|---|
| `stew/bitops2.nim:291,304,307,323,340,365,377,391` | `countOnes, countZeros, parity, firstOne, log2trunc, leadingZeros, trailingZeros, nextPow2` | call user-defined helpers (`countOnesNim/Builtin`, `bitsof`, `firstOne`, …) → violates (a); documented identities (`firstOne(x) == trailingZeros(x) + 1`, bitops2.nim:327) contain calls → not expressible in closed grammar |
| `stew/bitops2.nim:36-133` | `nextPow2Nim, firstOneNim, log2truncNim, countOnesNim, parityNim` | array consts (`lookup`), `*`-masks, self-overload calls; popcount/log2 semantics not expressible with only `+`/`==` |
| `stew/bitops2.nim:399,409` | `rotateLeft, rotateRight` | local `const` + `shl/shr`; any documented rotation property needs bitwise ops or calls |
| `stew/bitops2.nim:446-557, 559` | bit set/get family, `getBitsBE` | `var` mutation params, templates, `openArray[byte]` params |
| `stew/endians2.nim:62-76` | `swapBytesNim` (uint16/32/64) | shape (a) OK (pure uint, no calls) but no documented property expressible without `shl/shr`/calls → fails (b) |
| `stew/base32.nim:68,79` | `encodedLength, decodedLength` | shape OK; arithmetic verified **correct** (encoded = 8·⌈L/5⌉ / exact ceil; decoded = ⌊5L/8⌋ exactly) — no defect, no linear P |
| `stew/base58.nim:50,55` | `encodedLength, decodedLength` | shape OK; formulas safe/self-consistent (`1.38 > log₅₈(256)≈1.3655`; decoded = `length+4` matches contract) — no defect |
| `stew/base36.nim:52` | `encodedLength` | shape OK; verified safe (`277/179 = 1.54749 > log₃₆(256) = 1.54741`, floor-monotone, tight at n=179→278) — no defect |
| `stew/base10.nim:21,65`, `stew/leb128.nim:53,59` | `maxLen, encodedLength, len` | return `int8` → violates (a) |
| `stew/enums.nim:91,100` | `contains, checkedEnumAssign` | depend on `enumRangeInt64` macro / `hasHoles` template; enum params |
| `stew/io2.nim:522,704,730,1461` | `setUmask, toPermissions, toInt, checkFileSize` | libc importc call / set[enum] params / returns `IoResult[int]` |
| `stew/interval_set.nim`, `stew/keyed_queue.nim`, `stew/sorted_set*`, `stew/objects.nim`, `stew/bitseqs.nim`, `stew/byteutils.nim`, `stew/shims/*`, `stew/windows/acl.nim`, `stew/arraybuf.nim`, `stew/arrayops.nim`, `stew/ctops.nim` | all | object/ref/openArray/NimNode/string params, or user-defined calls → fail (a) |

No builds, tests, or writes were performed; the working tree was left untouched.