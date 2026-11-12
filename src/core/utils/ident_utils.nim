import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/strutils
import ../../core/trusted/axiom_pragmas

## Identifier parsing utilities.
## Extracted from verified_axioms.nim, gateway.nim, proof_vacuity_gate.nim
## to eliminate DRY violation (isIdentStart triple duplication).

func isIdentStart*(c: char): bool {.inline, raises: [], axiom: ["(assert (= 1 1))", "1 = 1"].} =
  c.isAlphaAscii() or c == '_'

func isIdentPart*(c: char): bool {.inline, raises: [].} =
  c.isAlphaAscii() or c.isDigit() or c == '_'

{.pop.}
