import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Capability CLI — `ax capability`: the machine-readable capability
## disclosure surface (byo_agent_proposition_contract.md §11). The output is
## a runtime PROJECTION of the committed catalog (config/spec — the single
## spec-document authority) + the engine's dispatch truth
## (`laneDispatchEquipped` — flipped adapter path or legacy chain arm path);
## this command never decides a capability, it discloses one. It requires no
## subject and no AXIOM_STATE_DIR — a pure catalog+engine query.
##
## Output: {"axiomVersion": <axiomVersionWithPrefix>, "capabilities": [
##   {"specId": …, "status": "EQUIPPED" | "NOT_EQUIPPED",
##    "laneClass": <capability spelling>, "specRelPath": <registry identity>}]}

import std/[json, options]
import cli/axiom_engine
import cli/cli_outcome
import cli/external_subject_registry
import cli/version
import core/axiom_pragmas
import core/results

proc runCapabilityCli*(args: seq[string]): int {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for arg in args:
    if arg != "--json":
      stderr.writeLine("[AXIOM] ax capability: unknown argument \"" & arg &
        "\" — usage: ax capability [--json]")
      return exitCode(CliOutcome.INVALID_INPUT)
  let catalogRes = loadExternalSubjectRegistry()
  if catalogRes.isErr():
    stderr.writeLine("[AXIOM] ax capability: committed catalog unavailable " &
      "(fail-closed): " & catalogRes.error)
    return exitCode(CliOutcome.INTERNAL_ERROR)
  var capabilities = newJArray()
  for entry in catalogRes.get.entries:
    capabilities.add(%*{
      "specId": entry.specId,
      "status": (if laneDispatchEquipped(entry): "EQUIPPED"
                 else: "NOT_EQUIPPED"),
      "laneClass": $entry.capability,
      "specRelPath": entry.specRelPath})
  let disclosure = %*{
    "axiomVersion": axiomVersionWithPrefix,
    "capabilities": capabilities}
  echo $disclosure
  return exitCode(CliOutcome.SUCCESS)
{.pop.}
