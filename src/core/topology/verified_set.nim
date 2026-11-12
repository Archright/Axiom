import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## VerifiedSet — Dense bitset over interned NodeId handles.
##
## Uses a seq[uint64] instead of std/packedsets so every operation can be
## a func/noSideEffect and the contract stays compatible with Axiom's
## static-effect discipline.

import std/bitops
import core/topology/symbol_interning

type
  VerifiedSet* = object
    bits: seq[uint64]

func initVerifiedSet*(initialCapacityInNodes: int = 0): VerifiedSet =
  ## Create an empty set. The hint is only an optimisation; incl() auto-grows.
  if initialCapacityInNodes > 0:
    let words = (initialCapacityInNodes + 63) div 64
    result.bits = newSeq[uint64](words)
  else:
    result.bits = @[]

func incl*(s: var VerifiedSet; id: NodeId) =
  ## Insert a NodeId, growing the backing seq if the handle exceeds the
  ## current capacity.
  let uid = uint32(id)
  let idx = int(uid div 64'u32)
  if idx >= s.bits.len:
    s.bits.setLen(idx + 1)
  s.bits[idx] = s.bits[idx] or (1'u64 shl int(uid mod 64'u32))

func contains*(s: VerifiedSet; id: NodeId): bool {.inline.} =
  ## O(1) membership test. Forced inline because it is called inside the
  ## queue-slicing hot loop.
  let uid = uint32(id)
  let idx = int(uid div 64'u32)
  if idx >= s.bits.len:
    return false
  result = (s.bits[idx] and (1'u64 shl int(uid mod 64'u32))) != 0'u64

func isEmpty*(s: VerifiedSet): bool =
  for word in s.bits:
    if word != 0'u64:
      return false
  true

func popcount*(s: VerifiedSet): int {.noSideEffect.} =
  ## Number of set bits. O(number of backing words).
  for word in s.bits:
    result += popcount(word)

func fromVerifiedNodeIds*(ids: seq[NodeId]): VerifiedSet =
  result = initVerifiedSet(ids.len)
  for id in ids:
    result.incl(id)

func digestBits*(s: VerifiedSet): seq[uint64] {.inline, raises: [].} =
  ## Expose raw bitset words for deterministic digest computation.
  ## Does not alter VerifiedSet semantics.
  s.bits

{.pop.}
