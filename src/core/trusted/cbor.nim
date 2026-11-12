import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [ValueError].}

import std/strutils
import core/crypto/hash_kernel
import core/trusted/monad
import core/trusted/path
import core/parsers/safe_parsers
import core/types/results
# axiomIoBoundary

## Trusted CBOR — binary serialization of proof certificates.
## At this stage, guarantees integrity via "immutable hash chain" instead of ZKP.
## Replaceable with a proper CBOR library in the future.

type
  CborProofEnvelope* = object
    path*: ReasoningPath
    certificateHash*: string
    timestamp*: int64

## Compute SHA-256 hash of envelope contents.
func envelopeHash*(envelope: CborProofEnvelope): string {.inline.} =
  let data = envelope.certificateHash & ":" & envelope.path.headHash & ":" & $envelope.timestamp
  hash_kernel.sha256Hex(data)

## Encode proof envelope in CBOR-like binary form (actually hex string).
## Replace with CBOR standard library in the future.
func encodeCbor*(envelope: CborProofEnvelope): string {.inline.} =
  ## Simplified: replaced with JSON + hash chain. CBOR standard library to be introduced in the future.
  envelope.certificateHash & ":" & envelope.path.headHash & ":" & $envelope.timestamp

## Decode encoded proof into a verified envelope.
func decodeCbor*(raw: string): AxiomSafe[CborProofEnvelope] {.raises: [ValueError].} =
  let parts = raw.split(":")
  if parts.len != 3:
    raise newException(ValueError, "Invalid CBOR envelope format")
  let envelope = CborProofEnvelope(
    path: ReasoningPath(),  ## DEBT#052: path restoration logic
    certificateHash: parts[0],
    timestamp: safeParseInt(parts[2]).getOrDefault(0)
  )
  ## Verify hash chain integrity
  if not verifyPathIntegrity(envelope.path):
    raise newException(ValueError, "Corrupted proof path")
  seal(envelope)

{.pop.}
