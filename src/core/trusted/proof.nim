import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [ValueError].}

import core/crypto/hash_kernel
import core/trusted/monad
import core/trusted/path
import core/trusted/cbor
# axiomIoBoundary

## Proof Verification — cryptographic verification and composition of individual certificates.
## Guarantees integrity via SHA-256 hash chain.

type
  ProofCertificate* = object
    nodeId*: string
    envelope*: CborProofEnvelope
    merkleRoot*: string

## Compute SHA-256 Merkle root for certificate.
func computeMerkleRoot*(cert: ProofCertificate): string {.inline.} =
  let data = cert.envelope.path.headHash & cert.nodeId
  hash_kernel.sha256Hex(data)

## Verify integrity of a single certificate.
func verifyProof*(cert: ProofCertificate): bool {.inline.} =
  ## 1. Verify path integrity
  if not verifyPathIntegrity(cert.envelope.path):
    return false
  ## 2. Verify SHA-256 hash chain matches merkleRoot
  let computedRoot = computeMerkleRoot(cert)
  computedRoot == cert.merkleRoot

## Compose multiple certificates via logical AND.
func composeProof*(certs: seq[ProofCertificate]): bool {.inline.} =
  for cert in certs:
    if not verifyProof(cert):
      return false
  true

## Seal the verified certificate as AxiomSafe.
func sealProof*(cert: ProofCertificate): AxiomSafe[ProofCertificate] {.inline.} =
  if not verifyProof(cert):
    raise newException(ValueError, "Cannot seal invalid proof")
  seal(cert)

{.pop.}
