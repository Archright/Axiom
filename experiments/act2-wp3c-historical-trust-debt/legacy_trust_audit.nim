##
## legacy_trust_audit.nim
##
## EXPERIMENT-ONLY TOOL — NOT CANONICAL EXECUTION PATH — NOT PRODUCTION API.
##
## Purpose (WP3-c, Historical Trust-Artifact Integrity):
##   Build an execution-derived, deterministic, immutable INVENTORY of the
##   historical trust journal records under data/trusted/journal/ without
##   modifying any of those records.
##
## This tool does NOT:
##   - mutate journal files,
##   - read or write any product-internal module (no import of src/**),
##   - assert which historical records are "true" or "false",
##   - promote any record to any current trust status.
##
## It ONLY classifies the historical records (by kind / solver invocation /
## claim format) and records, for each, an immutable sha256 of its original
## bytes plus a `revalidationStatus` of "legacy-unverified". The final
## manifest carries a `manifestDigest` over the canonical JSON bytes.
##
## Determinism contract:
##   - Records are processed in byte-order sorted by canonical journal path
##     (relative POSIX path "data/trusted/journal/<sha>.json").
##   - Field order in emitted objects is fixed; no timestamps; no filesystem
##     metadata is read.
##   - Running twice on identical input yields byte-identical manifest
##     output and an identical manifestDigest.
##
## Usage:
##   nim c -r <Axiom>/experiments/act2-wp3c-historical-trust-debt/legacy_trust_audit.nim \
##     -- <AxiomRoot> <outManifestPath>
##
##   AxiomRoot should be the Axiom repository root; the journal is read from
##   <AxiomRoot>/data/trusted/journal.
##

import std/[os, json, strutils, algorithm]

{.warning[UnusedImport]: off.}
{.push warning[Deprecated]: off.}

# ---------------------------------------------------------------
# Inline SHA-256 (pure stdlib, deterministic).
#
# The Nim toolchain in this environment ships only std/sha1 (SHA-1). To keep
# the experiment tool stdlib-only and free of product or third-party imports,
# SHA-256 is implemented directly here. The implementation is the canonical
# FIPS 180-4 algorithm; it is deterministic and byte-exact, which is all the
# manifest digest requires.
# ---------------------------------------------------------------
const
  K256 = [
    0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32,
    0x3956c25b'u32, 0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32,
    0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32,
    0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32,
    0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32,
    0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
    0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32,
    0xc6e00bf3'u32, 0xd5a79147'u32, 0x06ca6351'u32, 0x14292967'u32,
    0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32,
    0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
    0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32,
    0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
    0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32,
    0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32, 0x682e6ff3'u32,
    0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32,
    0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32]

proc rotr(x: uint32, n: uint32): uint32 {.inline.} =
  (x shr n) or (x shl (32'u32 - n))

proc sha256(data: string): string =
  ## Return lowercase hex SHA-256 of `data`. Operates on raw bytes.
  var msg = data
  let bitLen = uint64(msg.len) * 8'u64
  msg.add(char(0x80))
  while msg.len mod 64 != 56:
    msg.add(char(0x00))
  for i in countdown(7, 0):
    msg.add(char((bitLen shr (8 * i)) and 0xFF'u64))

  var h = [0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32,
           0x510e527f'u32, 0x9b05688c'u32, 0x1f83d9ab'u32, 0x5be0cd19'u32]

  var w: array[64, uint32]
  var i = 0
  while i < msg.len:
    for t in 0 ..< 16:
      let o = i + t * 4
      w[t] = (uint32(msg[o]) shl 24) or (uint32(msg[o+1]) shl 16) or
             (uint32(msg[o+2]) shl 8) or uint32(msg[o+3])
    for t in 16 ..< 64:
      let s0 = rotr(w[t-15], 7) xor rotr(w[t-15], 18) xor (w[t-15] shr 3)
      let s1 = rotr(w[t-2], 17) xor rotr(w[t-2], 19) xor (w[t-2] shr 10)
      w[t] = w[t-16] + s0 + w[t-7] + s1
    var a = h[0]; var b = h[1]; var c = h[2]; var d = h[3]
    var e = h[4]; var f = h[5]; var g = h[6]; var hh = h[7]
    for t in 0 ..< 64:
      let S1 = rotr(e, 6) xor rotr(e, 11) xor rotr(e, 25)
      let ch = (e and f) xor ((not e) and g)
      let temp1 = hh + S1 + ch + K256[t] + w[t]
      let S0 = rotr(a, 2) xor rotr(a, 13) xor rotr(a, 22)
      let maj = (a and b) xor (a and c) xor (b and c)
      let temp2 = S0 + maj
      hh = g; g = f; f = e; e = d + temp1
      d = c; c = b; b = a; a = temp1 + temp2
    h[0] += a; h[1] += b; h[2] += c; h[3] += d
    h[4] += e; h[5] += f; h[6] += g; h[7] += hh
    i += 64

  result = ""
  for x in h:
    result.add(toHex((x shr 24) and 0xFF'u32, 2).toLowerAscii)
    result.add(toHex((x shr 16) and 0xFF'u32, 2).toLowerAscii)
    result.add(toHex((x shr 8) and 0xFF'u32, 2).toLowerAscii)
    result.add(toHex(x and 0xFF'u32, 2).toLowerAscii)

{.pop.}

proc classifyClaimFormat(claim: string): string =
  ## Classify the historical claim format by probing parsed JSON shape.
  ## This is a *classification label* only; it does not assert verification.
  var obj: JsonNode
  try:
    obj = parseJson(claim)
  except JsonParsingError:
    return "unparseable"
  if obj.kind == JObject:
    if obj.hasKey("entries"): return "entries[]"          # vault-manifest
    if obj.hasKey("graphSnapshot"): return "graphSnapshot"
    if obj.hasKey("certificates") or obj.hasKey("certificate"): return "certificate"
    return "other"
  elif obj.kind == JArray:
    return "array"
  return "other"

proc sha256Hex(data: string): string =
  ## Convenience wrapper returning lowercase hex SHA-256 of `data`.
  result = sha256(data)

# ----
# Main
# ----
if paramCount() < 2:
  quit("usage: legacy_trust_audit <AxiomRoot> <outManifestPath>", 1)

let axiomRoot = paramStr(1)
let outPath = paramStr(2)
let journalDir = axiomRoot / "data" / "trusted" / "journal"

if not dirExists(journalDir):
  quit("journal dir not found: " & journalDir, 1)

var files: seq[string] = @[]
for kind, path in walkDir(journalDir):
  if kind == pcFile and path.endsWith(".json"):
    files.add(extractFilename(path))
files.sort()  # byte-order deterministic

var records: seq[JsonNode] = @[]
for name in files:
  let absPath = journalDir / name
  let raw = readFile(absPath)
  let rec = parseJson(raw)
  let kind = if rec.hasKey("kind"): rec["kind"].getStr("") else: ""
  let solver = if rec.hasKey("solverInvocation"): rec["solverInvocation"].getStr("") else: ""
  let claim = if rec.hasKey("claim"): rec["claim"].getStr("") else: ""
  let fmt = classifyClaimFormat(claim)

  var o = newJObject()
  # Fixed key order for determinism.
  o["journalPath"] = %("data/trusted/journal/" & name)
  o["originalSha256"] = %sha256Hex(raw)
  o["historicalKind"] = %kind
  o["historicalSolverInvocation"] = %solver
  o["historicalClaimFormat"] = %fmt
  o["revalidationStatus"] = %"legacy-unverified"
  records.add(o)

var body = newJObject()
body["schema"] = %"act2-wp3c/legacy-trust-audit/v1"
body["journalDir"] = %("data/trusted/journal")
body["recordCount"] = %records.len
body["classificationPartial"] = %"true"
var entriesArr = newJArray()
for r in records: entriesArr.add(r)
body["entries"] = entriesArr

# manifestDigest = sha256 of the canonical JSON bytes (fixed order).
let bodyBytes = $body
let digest = sha256Hex(bodyBytes)
body["manifestDigest"] = %digest

writeFile(outPath, $body)
echo "written: " & outPath
echo "records: " & $records.len
echo "manifestDigest: " & digest

quit(0)
