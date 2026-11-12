import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## RequestId — Planning-domain identity for request derivation (no self-certification)
##
## See: canonical_execution_semantics.md §Appendix C (RequestId vs ExecutionIdentity)
##
## Rule: no hash → canonical serialization via stdlib JSON only.

import std/[json, strutils, algorithm, options]

type
  RequestId* = distinct string

## Canonical construction helper: fields must be provided in the exact order expected by the derived request.
## This ensures deterministic RequestId from the same input fields.

func makeRequestId*(fields: openArray[string]): RequestId {.raises: [].} =
  ## Deterministic construction from fields in the order they appear in the request definition.
  ## No hashing applied; fields are serialized canonically via toJson.
  result = RequestId(fields.join("||"))

func toString*(id: RequestId): string {.raises: [].} =
  string(id)

## JSON round-trip — deterministic via canonical JSON keys (alphabetical).

func toJson*(id: RequestId): JsonNode {.raises: [].} =
  result = %id.toString()

func fromJson*(node: JsonNode): Option[RequestId] {.raises: [].} =
  if node.kind != JString:
    return none(RequestId)
  some(RequestId(node.getStr()))

# ---------------------------------------------------------------------------
# Canonical ordering helpers
# ---------------------------------------------------------------------------

func `$`*(id: RequestId): string {.inline.} = string(id)

func `==`*(a, b: RequestId): bool {.inline.} = string(a) == string(b)

func `<`*(a, b: RequestId): bool {.inline.} = string(a) < string(b)

func `<=`*(a, b: RequestId): bool {.inline.} = string(a) <= string(b)

func `>`*(a, b: RequestId): bool {.inline.} = string(a) > string(b)

func `>=`*(a, b: RequestId): bool {.inline.} = string(a) >= string(b)

{.pop.}