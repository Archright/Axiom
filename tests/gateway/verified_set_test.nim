## Verified Set Tests — Dense bitset masking for verified topology nodes.
##
## Verifies basic VerifiedSet operations and auto-growth behavior.

import std/unittest
import core/topology/symbol_interning
import core/topology/verified_set

suite "VerifiedSet":

  test "empty set contains no nodes":
    let s = initVerifiedSet()
    var pool = initInternPool()
    let id = internNode(pool, "src/mod.nim::fn")
    check not s.contains(id)
    check s.isEmpty()

  test "included node is contained":
    var pool = initInternPool()
    let id = internNode(pool, "src/mod.nim::fn")
    var s = initVerifiedSet()
    s.incl(id)
    check s.contains(id)
    check not s.isEmpty()

  test "auto-grown set spans many nodes":
    var pool = initInternPool()
    var s = initVerifiedSet(4)
    for i in 0 ..< 200:
      let id = internNode(pool, "src/mod.nim::fn" & $i)
      s.incl(id)
    for i in 0 ..< 200:
      let id = internNode(pool, "src/mod.nim::fn" & $i)
      check s.contains(id)
    let missing = internNode(pool, "src/mod.nim::missing")
    check not s.contains(missing)

  test "fromVerifiedNodeIds builds a set":
    var pool = initInternPool()
    var ids: seq[NodeId] = @[]
    for i in 0 ..< 5:
      ids.add(internNode(pool, "src/mod.nim::fn" & $i))
    let s = fromVerifiedNodeIds(ids)
    for id in ids:
      check s.contains(id)

  test "popcount returns the number of set bits":
    var pool = initInternPool()
    var s = initVerifiedSet()
    check s.popcount() == 0
    s.incl(internNode(pool, "src/mod.nim::a"))
    check s.popcount() == 1
    s.incl(internNode(pool, "src/mod.nim::b"))
    s.incl(internNode(pool, "src/mod.nim::c"))
    check s.popcount() == 3
    # Re-including an existing ID does not inflate the count.
    s.incl(internNode(pool, "src/mod.nim::b"))
    check s.popcount() == 3
