import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Static Type Manifest Registry — const lookup for external module types.
## Bypasses Nim compiler's getTypeImpl limitations for imported case objects.

import std/tables
import core/trusted/axiom_ir

type
  ExternalTypeSpec* = object
    kind*: IRTypeKind
    tags*: seq[string]
    ordinals*: seq[int64]
    tagBitWidth*: int  ## bits for tag extraction (default 8)

const externalTypeManifest*: Table[string, ExternalTypeSpec] = {
  "VaultLoadError": ExternalTypeSpec(
    kind: irtVariant,
    tags: @["vaultLoadInvalidAxiom", "vaultLoadStorageFailure"],
    ordinals: @[0'i64, 1]
  ),
  "VaultLoadErrorKind": ExternalTypeSpec(
    kind: irtEnum,
    tags: @["vaultLoadInvalidAxiom", "vaultLoadStorageFailure"],
    ordinals: @[0'i64, 1]
  ),
  "AxiomInvalidError": ExternalTypeSpec(
    kind: irtEnum,
    tags: @["axiomInvalidFingerprintMismatch"],
    ordinals: @[0'i64]
  ),
  "AxiomError": ExternalTypeSpec(
    kind: irtBitVec64,
    tags: @[],
    ordinals: @[]
  ),
}.toTable

func lookupExternalType*(typeName: string): ExternalTypeSpec {.inline.} =
  ## Look up a type name in the static manifest.
  ## Returns spec with irtBitVec64 if not found (default fallback).
  externalTypeManifest.getOrDefault(typeName, ExternalTypeSpec(kind: irtBitVec64))

{.pop.}
