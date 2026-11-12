import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/strutils
import core/vault/vault_manager_spec

func computeVerificationFingerprint*(irHash: string; leanProposition: string): string =
  ## Legacy fingerprint: hashes ONLY (irHash, leanProposition).
  ## Kept intact for backward compatibility — existing certs are NOT retroactively re-promoted.
  if irHash.len == 0:
    return ""
  let cleanProp = leanProposition.strip().replace("\r\n", "\n")
  result = computeSourceFingerprint(irHash & "\n" & cleanProp)

func computeCertificateIdentity*(identityFields: seq[string]): string {.raises: [].} =
  ## Canonical Certificate Identity: deterministic SHA-256 over an ordered list
  ## of provenance components joined with "\n". Binds the full provenance chain
  ## (source/spec/IR/SMT/translation/solver/proof/schema).
  ## Returns empty string if the list is empty (fail-closed).
  if identityFields.len == 0:
    return ""
  result = computeSourceFingerprint(identityFields.join("\n"))

{.pop.}
