# nim-check: skip — out-of-tree probe: imports toml_serialization from the READ-ONLY subject clone via --path (Zero-Footprint); cannot resolve that import in repo context by design.
# Differential-verification probe A (DFA): drives the READ-ONLY subject's
# public UTF-8 validator API (toml_serialization/private/utf8_validate.nim)
# from OUTSIDE the subject repo (Zero-Footprint: subject clone is never
# modified; compiled in /tmp with an explicit --path to the pinned clone).
# Subject: nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9
#
# Emits verdict bitmaps (MSB-first, one bit per sequence) for three exactly
# defined enumeration ranges, twice: once via the batch entry point
# `validateUTF8` and once via the incremental object API
# (`UTF8Validator.clear/push/valid`) so the two entry points are compared
# bit-for-bit, and runs the chunking-equivalence test (arbitrary splits of
# every sequence across push calls must reproduce the single-shot verdict).

import std/[os, strutils]
import toml_serialization/private/utf8_validate

const OUTDIR = "/tmp/utf8diff/out"

type BitWriter = object
  f: File
  acc: uint8
  nbits: int
  count: int64

var statSeqs: int64 = 0
var statPrefixChecks: int64 = 0
var statCompChecks: int64 = 0

proc openW(bw: var BitWriter, path: string) =
  bw.f = open(path, fmWrite)
  bw.acc = 0
  bw.nbits = 0
  bw.count = 0

proc emit(bw: var BitWriter, ok: bool) =
  bw.acc = (bw.acc shl 1) or uint8(ord(ok))
  inc bw.nbits
  if bw.nbits == 8:
    discard bw.f.writeBuffer(addr bw.acc, 1)
    bw.acc = 0
    bw.nbits = 0
  inc bw.count

proc closeW(bw: var BitWriter) =
  if bw.nbits != 0:
    # pad low bits with 0 (all our ranges are whole bytes, so unused)
    while bw.nbits != 8:
      bw.acc = (bw.acc shl 1)
      inc bw.nbits
    discard bw.f.writeBuffer(addr bw.acc, 1)
  bw.f.close()

var mismatches: int = 0
var firstMism: seq[string] = @[]

proc hexOf(buf: openArray[char], n: int): string =
  result = ""
  for i in 0 ..< n:
    result.add toHex(ord(buf[i]), 2)
    if i != n - 1: result.add " "

proc noteMism(buf: openArray[char], n: int, batch, incr: bool) =
  inc mismatches
  if firstMism.len < 20:
    firstMism.add "seq=[" & hexOf(buf, n) & "] batch=" & $batch & " incremental=" & $incr

proc check(buf: openArray[char], n: int, bw1: var BitWriter, bw2: var BitWriter) =
  let single = validateUTF8(buf.toOpenArray(0, n - 1))
  inc statSeqs
  var v: UTF8Validator
  v.clear()
  var finalObj = false
  for k in 0 ..< n:
    v.push(buf[k])
    let pv = v.valid()
    # split-point check: validity observed after a push at any boundary must
    # equal the standalone validity of the prefix consumed so far
    let pref = validateUTF8(buf.toOpenArray(0, k))
    inc statPrefixChecks
    if pv != pref:
      noteMism(buf.toOpenArray(0, k), k + 1, pref, pv)
    finalObj = pv
  if finalObj != single:
    noteMism(buf, n, single, finalObj)
  # literal all-compositions execution: every way to split the n bytes into
  # consecutive chunks (2^(n-1) compositions) is run through one validator;
  # push is per-byte, so compositions are mechanically identical push streams,
  # and the test verifies that empirically
  for m in 0 ..< (1 shl (n - 1)):
    var w: UTF8Validator
    w.clear()
    for k in 0 ..< n:
      w.push(buf[k])
      if k < n - 1 and (m and (1 shl k)) != 0:
        discard w.valid() # observe state at the chunk boundary
    inc statCompChecks
    if w.valid() != single:
      noteMism(buf, n, single, w.valid())
  bw1.emit(single)
  bw2.emit(finalObj)

proc sanity() =
  doAssert validateUTF8("a")                == true,  "sanity U+0061"
  doAssert validateUTF8("\xC3\xA9")         == true,  "sanity U+00E9"
  doAssert validateUTF8("\xF0\x9F\x98\x80") == true,  "sanity U+1F600"
  doAssert validateUTF8("\x80")             == false, "sanity lone cont"
  doAssert validateUTF8("\xC0\x80")         == false, "sanity overlong 2B"
  doAssert validateUTF8("\xED\xA0\x80")     == false, "sanity surrogate"
  doAssert validateUTF8("\xF4\x90\x80\x80") == false, "sanity >U+10FFFF"
  doAssert validateUTF8("\xF0\x80\x80\x80") == false, "sanity overlong 4B"
  doAssert validateUTF8("\xF0\xA0\x80\x80") == true,  "sanity U+20000"
  block:
    var v: UTF8Validator
    doAssert v.valid(), "fresh validator must be valid (state 0)"
    v.push('\xF0')
    doAssert(not v.valid(), "partial sequence must not be valid")
    v.clear()
    doAssert v.valid(), "clear() must restore ACCEPT"
    v.push('\xF0')
    v.push('\x9F')
    v.push('\x98')
    doAssert(not v.valid(), "3/4 bytes of U+1F600 must not be valid")
    v.push('\x80')
    doAssert v.valid(), "completed U+1F600 must be valid"

proc ranges() =
  createDir(OUTDIR)
  var bw1, bw2: BitWriter
  bw1.openW(OUTDIR & "/r123_batch.bin")
  bw2.openW(OUTDIR & "/r123_obj.bin")
  var buf: array[3, char]
  for b in 0 .. 255:                      # R1: len 1 (256)
    buf[0] = char(b)
    check(buf.toOpenArray(0, 0), 1, bw1, bw2)
  for b1 in 0 .. 255:                     # R2: len 2 (65,536)
    buf[0] = char(b1)
    for b2 in 0 .. 255:
      buf[1] = char(b2)
      check(buf.toOpenArray(0, 1), 2, bw1, bw2)
  for b1 in 0 .. 255:                     # R3: len 3 (16,777,216)
    buf[0] = char(b1)
    for b2 in 0 .. 255:
      buf[1] = char(b2)
      for b3 in 0 .. 255:
        buf[2] = char(b3)
        check(buf.toOpenArray(0, 2), 3, bw1, bw2)
  bw1.closeW()
  bw2.closeW()

  bw1.openW(OUTDIR & "/r4f0f4_batch.bin")
  bw2.openW(OUTDIR & "/r4f0f4_obj.bin")
  var buf4: array[4, char]
  for b1 in 0xF0 .. 0xF4:                 # R4: len 4, leads F0..F4 (83,886,080)
    buf4[0] = char(b1)
    for b2 in 0 .. 255:
      buf4[1] = char(b2)
      for b3 in 0 .. 255:
        buf4[2] = char(b3)
        for b4 in 0 .. 255:
          buf4[3] = char(b4)
          check(buf4.toOpenArray(0, 3), 4, bw1, bw2)
  bw1.closeW()
  bw2.closeW()

  bw1.openW(OUTDIR & "/r5wrong_batch.bin")
  bw2.openW(OUTDIR & "/r5wrong_obj.bin")
  # R5: len 4 with any lead outside F0..F4 (251 leads); per lead:
  #   sweep b2 (b3=80 b4=80), sweep b3 (b2=80 b4=BF), sweep b4 (b2=BF b3=80),
  #   and the 8 corners b2,b3,b4 in {80,BF}  -> 776 sequences per lead
  for b1 in 0 .. 255:
    if b1 >= 0xF0 and b1 <= 0xF4: continue
    buf4[0] = char(b1)
    for b2 in 0 .. 255:
      buf4[1] = char(b2); buf4[2] = char(0x80); buf4[3] = char(0x80)
      check(buf4.toOpenArray(0, 3), 4, bw1, bw2)
    buf4[1] = char(0x80)
    for b3 in 0 .. 255:
      buf4[2] = char(b3); buf4[3] = char(0xBF)
      check(buf4.toOpenArray(0, 3), 4, bw1, bw2)
    buf4[2] = char(0x80)
    for b4 in 0 .. 255:
      buf4[1] = char(0xBF); buf4[3] = char(b4)
      check(buf4.toOpenArray(0, 3), 4, bw1, bw2)
    for b2 in [0x80'u, 0xBF'u]:
      for b3 in [0x80'u, 0xBF'u]:
        for b4 in [0x80'u, 0xBF'u]:
          buf4[1] = char(b2); buf4[2] = char(b3); buf4[3] = char(b4)
          check(buf4.toOpenArray(0, 3), 4, bw1, bw2)
  bw1.closeW()
  bw2.closeW()

proc main() =
  sanity()
  ranges()
  echo "sanity: OK"
  echo "sequences exercised: ", statSeqs
  echo "prefix split-point checks: ", statPrefixChecks
  echo "chunk-composition executions: ", statCompChecks
  echo "chunking/incremental vs batch mismatches: ", mismatches
  for m in firstMism: echo "  MISMATCH ", m
  echo "ranges written to ", OUTDIR

main()
