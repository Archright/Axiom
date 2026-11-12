import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## vault_types.nim — SSOT for vault index types.
## Extracted from domain_types.nim (Phase B-4).

import std/tables

type
  VaultIndexEntry* = object
    fileName*: string
    modulePath*: string
    functionName*: string
    fingerprint*: string
    status*: string
    trusted*: bool
    sourceMtime*: int64
    certMtime*: int64
    proofTimeMs*: int64
    axiomCount*: int
    solverEngine*: string

  VaultIndex* = object
    version*: int
    lastVerifiedAt*: int64
    entries*: Table[string, VaultIndexEntry]
    byFileName*: Table[string, string]

{.pop.}
