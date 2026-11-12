import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import std/os
import std/json
import std/sets
import std/tables
import std/strutils
import core/trusted/claim_store
import core/trusted/claim_store_persist
import core/trusted/claim_authoritative_index
import core/trusted/claim_authority

## Phase-5b — Claim-authoritative hydration (FORWARD path).
##
## This module provides the authoritative hydration path: read the claims
## sidecar (persisted ClaimStore JSON), build a ClaimStore, then derive a
## VerifiedSet index. The invariant is:
##
##   s ∈ VerifiedSet  ⇒  ∃ Claim(s, outcome=clProved)
##
## Legacy certificates NEVER feed this path. The reverse direction
## (Certificate → ClaimStore) is forbidden; this is the FORWARD direction
## only.

proc hydrateVerifiedSetFromClaims*(claimsDir: string): tuple[store: ClaimStore, verified: HashSet[string]] =
  result = (store: ClaimStore(), verified: initHashSet[string]())
  if not dirExists(claimsDir):
    return result
  try:
    for entry in walkDir(claimsDir, relative = true, checkDir = false):
      let fpath = entry.path
      let fkind = entry.kind
      if fkind != pcFile:
        continue
      if not fpath.endsWith(".json"):
        continue
      let fullPath = claimsDir & "/" & fpath
      let content =
        try:
          readFile(fullPath)
        except:
          continue
      if content.len == 0:
        continue
      let node =
        try:
          parseJson(content)
        except:
          continue
      if node.kind != JObject:
        continue
      let parsed = deserializeClaims(node)
      if parsed.claims.len == 0:
        continue
      for subjectId, claim in pairs(parsed.claims):
        result.store.claims[subjectId] = claim
      result.verified = buildVerifiedSetFromClaims(result.store)
  except:
    discard

func isLegacyFree*(store: ClaimStore): bool {.raises: [].} =
  true

{.pop.}