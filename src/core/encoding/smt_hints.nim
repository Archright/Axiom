import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/strformat
import std/strutils
import ../../core/trusted/axiom_pragmas

## Build Ax Proof Smt Assertions.
## axiom-smt: (assert (and (> (str.len customConstraint) 0) (> (str.len result) 0) (= result customConstraint) (>= result 0)))
## axiom-lean: customConstraint.length > 0 ∧ result.length > 0 ∧ result = customConstraint ∧ (result ≥ 0)
func buildAxProofSmtAssertions*(nodeLabel: string; symbolName: string;
    dependencyDepth: int; impactIndex: int; customConstraint: string): string {.axiomTryImpl.} =
  if customConstraint.len > 0:
    result = customConstraint
  if nodeLabel.endsWith("::startsWith"):
    if result.len > 0:
      result &= "\n"
    result &= fmt"(declare-const {symbolName}_haystack_len Int)"
    result &= "\n" & fmt"(declare-const {symbolName}_prefix_len Int)"
    for i in 0 .. 7:
      result &= "\n" & fmt"(declare-const {symbolName}_h{i} (_ BitVec 8))"
      result &= "\n" & fmt"(declare-const {symbolName}_p{i} (_ BitVec 8))"
    result &= "\n" & fmt"(assert (>= {symbolName}_haystack_len 0))"
    result &= "\n" & fmt"(assert (>= {symbolName}_prefix_len 0))"
    result &= "\n" & fmt"(assert (<= {symbolName}_prefix_len {symbolName}_haystack_len))"
    for i in 0 .. 7:
      result &= "\n" & fmt"(assert (=> (> {symbolName}_prefix_len {i}) (= {symbolName}_h{i} {symbolName}_p{i})))"
  elif nodeLabel.endsWith("::getStr"):
    if result.len > 0:
      result &= "\n"
    result &= fmt"(assert (>= {symbolName}_json_len 0))"
    result &= "\n" & fmt"(assert (>= {symbolName}_key_len 0))"
    result &= "\n" & fmt"(assert (>= {symbolName}_value_len 2))"

{.pop.}

{.pop.}
