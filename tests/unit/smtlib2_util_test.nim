import std/unittest
import core/encoding/smtlib2_util

suite "smtlib2_util certified exemptions":
  test "vacuous primitive hint marks function certified exempt":
    let source = """
# @axiom-hint: lean="true" smt="vacuous_primitive"
func cryptographicBoundary*(digest: string): string =
  digest
"""
    check isCertifiedExemptFunctionSource(source, "cryptographicBoundary")

  test "axiom pure pragma marks function certified exempt":
    let source = """
{.push axiomPure.}
func dfsBoundary*(node: int): int =
  node
"""
    check isCertifiedExemptFunctionSource(source, "dfsBoundary")
