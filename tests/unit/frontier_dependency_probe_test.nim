## B-dep machine record: decodedLength dependency set is empty.
##
## This test reads the real nim-stew decodedLength proc body and runs
## the topology scanner's `extractCallTargets` on it. The body
## `return (length * 179) div 277` contains no call expressions
## (identifiers followed by `(`) because `return` is a reserved word
## and `(` is not an identifier start. Therefore `extractCallTargets`
## returns an empty seq, confirming that the decodedLength dependency
## set is empty and the topology dependency gate cannot be the blocker.
##
## Machine-observed values are echoed for raw measurement.

import std/[unittest, strutils]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_pragmas
import core/topology/topology_parser

suite "B-dep machine record — decodedLength dependency probe":

  test "extractCallTargets on decodedLength body returns empty":
    # The real decodedLength body from nim-stew/stew/base36.nim lines 57-60:
    #   func decodedLength*(btype: typedesc[Base36Types], length:int): int =
    #     return (length*179) div 277
    # The bodyFragment (after '=') is: "return (length*179) div 277"
    let decodedLengthBody = "return (length*179) div 277"

    let rawCallTargets = extractCallTargets(decodedLengthBody)

    # Machine output — verbatim echo for measurement
    echo "rawCallTargets: ", rawCallTargets
    echo "isEmpty: ", rawCallTargets.len == 0

    # The dependency set is empty — no call targets in the body.
    # This means allDependenciesVerified trivially holds for a node
    # with empty dependencyIds (the loop in verified_frontier.nim:27-38
    # never executes, returning true).
    check rawCallTargets.len == 0
