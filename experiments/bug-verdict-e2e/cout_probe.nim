# nim-check: skip
# Standalone subject probe: imports stew/base36 from the OUT-OF-TREE READ-ONLY
# subject clone (Zero-Footprint — the subject is never vendored into this repo),
# compiled and run with an explicit --path to the pinned clone; it cannot
# resolve that import in repo context by design. Integrity is verified by
# executing it against the pinned subject (see
# docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md, link-3 record).
import stew/base36
import std/[strutils, sequtils]

# C_out ground-truth probe — evidence points for s="kzz" family (S0)
# Subject: nim-stew @ 1853f20bdfeda61331a0b7e02f7aace0e88a0dfe

proc hexOf(buf: openArray[byte], n: int): string =
  var parts: seq[string]
  for i in 0..<n: parts.add(toHex(int(buf[i]), 2))
  parts.join(" ")

proc probe(s: string) =
  var buf: array[16, byte]
  for i in 0..<16: buf[i] = 0xEE'u8
  var outlen = 0
  let st = decode(Base36Lc, s, buf.toOpenArray(0, buf.len-1), outlen)
  echo "input=", s, " L=", s.len, " need=", s.len + 3,
       " status=", $st, " outlen=", outlen,
       " bytes=", hexOf(buf, outlen),
       " dl=", decodedLength(Base36Lc, s.len)

echo "=== point vectors ==="
probe("kzz")     # expect Success outlen=2 [05 0F], dl(3)=1
probe("k00")     # expect Success outlen=2 [00 00], dl(3)=1 (minimal witness)
probe("kzzzz")   # expect Success outlen=3 [19 A0 FF], dl(5)=3 (equality)
probe("k")       # expect Success outlen=0, dl(1)=0
probe("k73")     # boundary non-violator: 255 -> 1 byte, dl(3)=1
probe("k74")     # boundary violator: 256 -> 2 bytes, dl(3)=1

echo "=== D3 sweep: s='k'+xy over Sigma^2 ==="
const Sigma = "0123456789abcdefghijklmnopqrstuvwxyz"
var viol, ok, z0v, z0ok, z1v, z2v = 0
for x in Sigma:
  for y in Sigma:
    let s = "k" & x & y
    var buf: array[8, byte]
    var outlen = 0
    let st = decode(Base36Lc, s, buf.toOpenArray(0, 7), outlen)
    doAssert st == Base36Status.Success
    let zc = (if x == '0': 1 else: 0) + (if x == '0' and y == '0': 1 else: 0)
    if outlen > decodedLength(Base36Lc, 3):
      inc viol
      if zc == 0: inc z0v
      elif zc == 1: inc z1v
      else: inc z2v
    else:
      inc ok
      if zc == 0: inc z0ok
echo "candidates=1296 viol=", viol, " ok=", ok
echo "zcount0: viol=", z0v, " ok=", z0ok, " zcount1: viol=", z1v, " zcount2: viol=", z2v
