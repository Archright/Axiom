import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/algorithm
import std/json
import std/strutils
import core/trusted/axiom_pragmas_lite
import core/crypto/hash_kernel
import core/results
import ed25519

## Certificate attestation — deterministic Ed25519 signature anchor.
##
## Every certificate written by the canonical writer carries an `attestation`
## block binding the certificate payload (all fields EXCEPT the attestation
## block itself) to an Ed25519 signature. The signature is computed over the
## RFC 8785 canonical JSON string of the payload, so field order in the source
## object can never change the attested bytes.
##
## ⚠️ HONESTY NOTE — this is a *tamper-evidence / consistency anchor*, NOT a
## confidentiality root. The keypair derives from a PUBLIC in-source seed
## (`AttestationDomainSeed`); anyone can re-derive it. What it provides:
##   • a stable identity for the Axiom attestation key across all certificates
##     (publicKeyId is content-addressed from the public key itself);
##   • cross-tool detection of a payload that does not round-trip through the
##     canonical serializer (writers/verifiers in other languages can re-check
##     the signature without sharing any secret);
##   • immunity of the attested bytes to key-roll confusion.
## Any claim that this key protects against an adversary who controls the
## source tree is FALSE theater and must not be made.
##
## Verification policy: an ABSENT attestation block passes (legacy certificates
## predate attestation); a PRESENT but invalid attestation fails closed.

# ---------------------------------------------------------------------------
# RFC 8785 canonical serializer (self-contained)
# ---------------------------------------------------------------------------
# The signed certificate payload is canonicalized exactly per RFC 8785. This
# serializer previously lived in verification/canonical_json.nim; the
# infrastructure layer cannot import from verification/ (layer enforcement),
# so it lives here and is mirrored byte-identically in
# tools/readiness_evaluator.nim. Keep the mirrors byte-identical — the
# step-⑧ gate and the evaluator both canonicalize through this exact code.
# Defined BEFORE the signing/verifying procs below (Nim has no forward
# references).

proc utf16UnitsOf(s: string): seq[uint16] =
  ## RFC 8785 property-name ordering compares UTF-16 code units.
  result = @[]
  var i = 0
  let n = s.len
  while i < n:
    let b0 = s[i].uint8
    if b0 < 0x80:
      result.add(b0.uint16)
      inc i
    elif (b0 and 0xE0) == 0xC0:
      let cp = ((b0 and 0x1F).uint32 shl 6) or (s[i+1].uint8 and 0x3F).uint32
      result.add(cp.uint16)
      i += 2
    elif (b0 and 0xF0) == 0xE0:
      let cp = ((b0 and 0x0F).uint32 shl 12) or
               ((s[i+1].uint8 and 0x3F).uint32 shl 6) or
               ((s[i+2].uint8 and 0x3F).uint32)
      result.add(cp.uint16)
      i += 3
    else: # 4-byte → surrogate pair (two UTF-16 code units)
      let cp = ((b0 and 0x07).uint32 shl 18) or
               ((s[i+1].uint8 and 0x3F).uint32 shl 12) or
               ((s[i+2].uint8 and 0x3F).uint32 shl 6) or
               ((s[i+3].uint8 and 0x3F).uint32)
      let v = cp - 0x10000'u32
      result.add(((v shr 10) + 0xD800).uint16)
      result.add(((v and 0x3FF) + 0xDC00).uint16)
      i += 4

proc cmpUtf16(a, b: string): int {.raises: [].} =
  let ua = utf16UnitsOf(a)
  let ub = utf16UnitsOf(b)
  let m = min(ua.len, ub.len)
  for i in 0 ..< m:
    if ua[i] < ub[i]: return -1
    if ua[i] > ub[i]: return 1
  if ua.len < ub.len: return -1
  if ua.len > ub.len: return 1
  0

proc escapeRfc8785(s: string): string =
  ## Minimal canonical string escaping per RFC 8785 (lowercase \uXXXX).
  result = "\""
  for ch in s:
    case ch
    of '"':  result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\b': result.add("\\b")
    of '\f': result.add("\\f")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else:
      let b = uint8(ch)
      if b < 0x20:
        result.add("\\u" & toHex(b, 2).toLowerAscii)
      else:
        result.add(ch)
  result.add("\"")

proc formatRfc8785Number(f: float): string =
  ## ES6 §7.1.12.1 number serialization (RFC 8785 requirement).
  if f == 0.0:
    return "0"
  let neg = f < 0
  let absF = abs(f)
  var repr: string
  if absF >= 1.0e21 or (absF > 0.0 and absF < 1.0e-6):
    var exp = 0
    var mant = absF
    while mant >= 10.0:
      mant /= 10.0
      inc exp
    while mant < 1.0:
      mant *= 10.0
      dec exp
    var mantStr = formatFloat(mant, ffDecimal, 17)
    if '.' in mantStr:
      mantStr = mantStr.strip(chars = {'0'}, trailing = true)
      if mantStr.endsWith("."):
        mantStr.setLen(mantStr.len - 1)
    let eSign = if exp >= 0: "+" else: "-"
    repr = mantStr & "e" & eSign & $abs(exp)
  else:
    var s = formatFloat(absF, ffDecimal, 17)
    if '.' in s:
      s = s.strip(chars = {'0'}, trailing = true)
      if s.endsWith("."):
        s.setLen(s.len - 1)
    repr = s
  if neg: "-" & repr else: repr

proc appendRfc8785(outB: var string; node: JsonNode) {.raises: [].} =
  case node.kind
  of JNull:
    outB.add("null")
  of JBool:
    outB.add(if node.getBool(): "true" else: "false")
  of JInt:
    outB.add($node.getInt())
  of JFloat:
    outB.add(formatRfc8785Number(node.getFloat()))
  of JString:
    outB.add(escapeRfc8785(node.getStr()))
  of JArray:
    outB.add('[')
    var first = true
    for e in node:
      if not first: outB.add(',')
      first = false
      appendRfc8785(outB, e)
    outB.add(']')
  of JObject:
    outB.add('{')
    var kvs: seq[(string, JsonNode)] = @[]
    for k, v in node.pairs:
      kvs.add((k, v))
    kvs.sort(cmp = proc(a, b: (string, JsonNode)): int = cmpUtf16(a[0], b[0]))
    for i, kv in kvs:
      if i > 0: outB.add(',')
      outB.add(escapeRfc8785(kv[0]))
      outB.add(':')
      appendRfc8785(outB, kv[1])
    outB.add('}')

proc canonicalJsonString*(node: JsonNode): string {.raises: [].} =
  ## RFC 8785 canonical JSON string (no trailing newline).
  ## Public wrapper so downstream gate/verifier code can canonicalize
  ## certificate payloads without importing the (verification-layer) old
  ## serializer.
  if node == nil:
    return "null"
  result = ""
  appendRfc8785(result, node)

const
  AttestationDomainSeed* = "axiom-attestation-v1-sha256"
    ## Domain-separation seed for the deterministic keypair. PUBLIC by design:
    ## the signature is a consistency anchor, not a secret-based authenticator.

  AxiomAttestationAlgorithm* = "Ed25519"
    ## Algorithm identifier recorded in the attestation block.

  AxiomAttestationPublicKeyHex* =
    "7e37ae83490895229c2b300a7862766ccb5d7c0840905527a414faa750af754e"
    ## Hex-encoded Ed25519 public key derived from sha256(AttestationDomainSeed).
    ## Pinned as a constant so the verifier NEVER derives a key at runtime from
    ## whatever source it is handed — the trusted key is this literal.

  AxiomAttestationPublicKeyId* = "sha256:" & sha256Hex(AxiomAttestationPublicKeyHex)
    ## Content-addressed key identifier: "sha256:" + SHA-256 of the key bytes
    ## (hex string). Computed at compile time from the pinned key literal, so
    ## the id can never drift from the key.

type
  AttestedSignature* = object
    publicKeyId*: string   ## must equal AxiomAttestationPublicKeyId
    signature*: string     ## 128-char lowercase hex Ed25519 signature

func hexNibble(c: char): byte {.raises: [].} =
  case c
  of '0'..'9': byte(ord(c) - ord('0'))
  of 'a'..'f': byte(ord(c) - ord('a') + 10)
  of 'A'..'F': byte(ord(c) - ord('A') + 10)
  else: 0

func hexToBytes(hex: string, targetLen: static int): array[targetLen, byte] {.raises: [].} =
  ## Hex string → fixed-size byte array. Invalid/nibble-odd input decodes to
  ## 0x00 bytes (verification will fail on a mismatch anyway).
  let byteLen = min(targetLen, hex.len div 2)
  for i in 0..<byteLen:
    result[i] = byte((hexNibble(hex[i * 2]) shl 4) or hexNibble(hex[i * 2 + 1]))

func keyPairForAttestation(): KeyPair {.raises: [CatchableError].} =
  ## Deterministic keypair: seed = SHA-256(AttestationDomainSeed) → 32 bytes.
  ## Every call re-derives the same key (Ed25519 key derivation is
  ## deterministic; RFC 8032). No randomness, no side effects.
  createKeypair(hexToBytes(sha256Hex(AttestationDomainSeed), 32))

func stripAttestation(certNode: JsonNode): JsonNode {.raises: [].} =
  ## The attested payload: every certificate field EXCEPT the attestation
  ## block. Key-order-independent — signing/verifying both go through the
  ## RFC 8785 canonical serializer, so object key order never matters.
  result = newJObject()
  if certNode.isNil or certNode.kind != JObject:
    return result
  for k, v in certNode.pairs:
    if k != "attestation":
      result[k] = v

proc signCertificatePayload*(certNode: JsonNode): Result[AttestedSignature, string] {.raises: [], axiomDecision(id = "DECISION-0662", reason = "Deterministic Ed25519 attestation over the canonical certificate payload; a signing failure must prevent emitting an unattested/half-attested certificate (writer treats sign failure as hard error)", adr = "docs/adr/0016-r4-promotion-eligibility.md", introduced = "v33").} =
  ## Deterministic Ed25519 signature over canonical JSON of the payload
  ## (certNode minus the attestation block). Same input → same signature.
  try:
    let payload = stripAttestation(certNode)
    let canonical = canonicalJsonString(payload)
    let kp = keyPairForAttestation()
    let sig = sign(canonical, kp)
    var sigHex = ""
    for b in sig:
      sigHex.add(toHex(byte(b), 2).toLowerAscii())
    ok(AttestedSignature(publicKeyId: AxiomAttestationPublicKeyId, signature: sigHex))
  except CatchableError as e:
    err("attestation: signing failed: " & e.msg)

proc verifyCertificateAttestation*(certNode: JsonNode): Result[void, string] {.raises: [], axiomDecision(id = "DECISION-0663", reason = "Fail-closed attestation verification: absent block passes for legacy certs, present-but-invalid fails the trust-closure stage; prevents re-signed payloads and key-roll confusion", adr = "docs/adr/0016-r4-promotion-eligibility.md", introduced = "v33").} =
  ## Verify a certificate's attestation block.
  ##
  ##   • attestation ABSENT                  → ok (legacy certificates)
  ##   • attestation present and valid       → ok
  ##   • attestation present but invalid     → err (fail closed)
  ##
  ## Algorithm, key id, signature length, and the Ed25519 signature itself are
  ## all checked; a wrong-key or re-signed unsigned payload is rejected.
  try:
    if certNode.isNil or certNode.kind != JObject:
      return err("attestation: certificate is not a JSON object")
    let att = certNode.getOrDefault("attestation")
    if att.isNil or att.kind != JObject:
      return Result[void, string](ok: true)  # legacy certificate — no attestation to verify
    if att.getOrDefault("algorithm").getStr("") != AxiomAttestationAlgorithm:
      return err("attestation: unsupported algorithm '" &
        att.getOrDefault("algorithm").getStr("") & "' (expected '" &
        AxiomAttestationAlgorithm & "')")
    if att.getOrDefault("publicKeyId").getStr("") != AxiomAttestationPublicKeyId:
      return err("attestation: publicKeyId mismatch")
    let sigHex = att.getOrDefault("signature").getStr("")
    if sigHex.len != 128:
      return err("attestation: malformed signature length " & $sigHex.len)
    let payload = stripAttestation(certNode)
    let canonical = canonicalJsonString(payload)
    let sig = hexToBytes(sigHex, 64)
    let pub = hexToBytes(AxiomAttestationPublicKeyHex, 32)
    if not verify(canonical, sig, pub):
      return err("attestation: Ed25519 signature verification failed")
    Result[void, string](ok: true)
  except CatchableError as e:
    err("attestation: verification raised: " & e.msg)

{.pop.}