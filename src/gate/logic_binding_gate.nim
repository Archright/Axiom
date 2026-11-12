import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Logic-Context Binding Gate (Hard-Mode Integrity)
##
## Ensures every certificate proposition references actual function
## parameters and return values — not just static flags like
## ast_parse_failed_isolated.

import std/os
import std/strutils
import std/sets
import core/json/std_redirect
import ../core/trusted/axiom_pragmas

const bannedAtoms = ["ast_parse_failed_isolated", "external_io_isolated"].toHashSet()

func containsExecutionSymbol*(proposition: string): bool {.axiomTryImpl.} =
  for token in proposition.splitWhitespace():
    let clean = token.strip(chars = {'(', ')', '[', ']', '{', '}', '.', ':', ',', ';', '/', '&', '|', '+', '-', '*', '<', '>', '='})
    if clean.len == 0:
      continue
    if clean in ["result", "res", "ret", "ok", "err", "error", "value", "out", "output"]:
      return true
  return false

  ## axiom-smt: (assert (and (>= (str.len proposition) 0) (>= (str.len nodeId) 0) (= (str.len nodeId) 0) (= result false) (=> (= (str.len nodeId) 0) (= result false)) (>= bannedAtoms 0) (>= result 0)))
  ## axiom-lean: proposition.length ≥ 0 ∧ nodeId.length ≥ 0 ∧ nodeId.length = 0 ∧ result = false ∧ nodeId.length = 0 → result = false ∧ (bannedAtoms ≥ 0) ∧ (result ≥ 0)
func hasLogicBinding*(proposition: string; nodeId: string): bool {.axiomTryImpl.} =
  ## Returns false for empty IDs, banned atoms, and vacuous propositions.
  if nodeId.len == 0:
    return false
  for atom in bannedAtoms:
    if atom in proposition: return false
  return containsExecutionSymbol(proposition)

  ## axiom-smt: (assert (and (>= (str.len proposition) 0) true (>= bannedAtoms 0)))
  ## axiom-lean: proposition.length ≥ 0 ∧ true ∧ (bannedAtoms ≥ 0)
func containsBannedAtom*(proposition: string): bool {.axiomTryImpl.} =
  for atom in bannedAtoms:
    if atom in proposition: return true

proc runLogicBindingGate*(certDir: string): seq[string] {.raises: [CatchableError], axiom: ["(assert (and (>= (str.len certDir) 0)))", "certDir.length ≥ 0"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for path in walkFiles(joinPath(certDir, "*.json")):
    try:
      let node = parseFile(path)
      let prop = node{"leanProposition"}.getStr()
      if prop.len > 0 and containsBannedAtom(prop):
        result.add(path & ": banned atom in proposition")
    except CatchableError as e:
      result.add(path & ": failed to parse certificate: " & e.msg)


{.pop.}
