# Lean char→UTF-8 byte-expansion quirk (ByteArray building)

Status: documented 2026-10-06 (discovered while closing the base36 sizing
binding extraction-agreement slice; fix in `proofs/IR/ReferenceExtractor.lean`).

## 1. Symptom

The Lean reference extractor (`proofs/IR/ReferenceExtractor.lean`, `RefEncoder`)
produced an IR wire that was NOT byte-equal to the Nim extractor's for one
specific literal class: integers with a byte ≥ 0x80 in the low byte AND all
other bytes ≤ 0x7F. Observed: `intLit 179` encoded as three 8-byte slots
`[1][46018][0]` instead of two `[1][179]` — `46018 = 0xB3C2` is exactly the
UTF-8 byte pair `C2 B3` (U+00B3 = "³", codepoint 179) read little-endian.
`intLit 1` and `intLit 277` matched by coincidence (every byte ≤ 0x7F).

## 2. Root Cause

```lean
private def b1 (b : UInt8) : ByteArray :=
  (String.singleton (Char.ofUInt8 b)).toUTF8   -- WRONG for b ≥ 0x80
```

`Char.ofUInt8 b` is the Unicode codepoint with scalar value `b` (U+00B3 for
179). `String.singleton` makes a one-CHAR string, and `String.toUTF8` encodes
CHARS, not bytes: every char ≥ U+0080 expands to a 2-byte UTF-8 sequence (≥
U+0800 → 3 bytes). So `b1 0xB3` returned the 2-byte array `#[0xC2, 0xB3]`,
inflating the i64 slot by one byte and shifting the 8-byte alignment of the
whole downstream wire (putTag's alignment padding then grows the node from 2
to 3 slots).

General rule: **`String` is a char sequence, not a byte sequence.** Any
`Char.ofUInt8` → `String` → `.toUTF8` chain is a byte-preserving roundtrip
ONLY for bytes 0x00–0x7F. The silent corruption window is exactly the
high-byte cases that also look "almost right" in slot dumps, which makes this
class of bug easy to miss with ASCII fixtures.

## 3. Correct pattern

Build bytes directly on the ByteArray — never round-trip through a Unicode
char:

```lean
private def b1 (b : UInt8) : ByteArray :=
  ByteArray.empty.push b
```

## 4. Latent related asymmetry (out of the certified subset, not fixed here)

The decoders (`readString` in `ReferenceExtractor.lean` / `AxiomIRExpr.lean`)
map each byte to a char via `Char.ofUInt8` and re-encode with `toUTF8`. For
non-ASCII subject identifiers this decode→encode roundtrip expands bytes the
same way (byte 0xB3 decodes to char U+00B3, re-encodes as `C2 B3`). The
certified subset's fixtures/identifiers are ASCII, so no current gate path
reaches it; any future non-ASCII subject support must decode UTF-8 properly
(e.g. via a byte-level UTF-8 decoder) before re-encoding.
