import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/trusted/semantic_profile
import core/crypto/hash_kernel

func profileIdentityFor*(profileName: string): string =
  if profileName == "v1":
    SemanticProfileV1Hash
  else:
    ""

func resolvedConfigDigest*(profileIdentity, scopeLockHash: string): string =
  sha256Hex(profileIdentity & scopeLockHash)

{.pop.}