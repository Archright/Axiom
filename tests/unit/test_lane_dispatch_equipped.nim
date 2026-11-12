## Lane dispatch equipped disclosure — `ax capability` authority unit tests
## (byo_agent_proposition_contract.md §11 A13; BYOA 5.1 review defect fix).
##
## Measured here (the committed config/spec catalog is the fixture — the
## engine is the SSOT, the CLI only projects):
##   1. Distribution: exactly 6 EQUIPPED entries + SPEC-LIBP2P-VARINT-RT as
##      the sole NOT_EQUIPPED entry.
##   2. Legacy chain arms are dispatch truth though unflipped: the
##      beta-composition (base36 sizing relational) and term-splice (base32
##      rem) entries have NO flipped adapter (capabilityAdapterFor none) yet
##      ARE equipped through their legacy chain arm (laneDispatchEquipped
##      true) — the pre-flip cascade in prepareProofRun dispatches them.
##   3. The divergence set between capabilityAdapterFor and
##      laneDispatchEquipped is EXACTLY those two registry identities —
##      no other entry's verdicts may differ.

import std/[options, unittest]
import ../../src/core/results
import ../../src/cli/axiom_engine
import ../../src/cli/external_subject_registry

proc committedCatalog(): ExternalSubjectRegistry =
  let regRes = loadExternalSubjectRegistry()
  if regRes.isErr:
    raise newException(ValueError, "committed catalog unavailable: " & regRes.error)
  regRes.get()

suite "lane dispatch equipped disclosure — legacy chain arms are dispatch truth":
  test "committed catalog: 6 EQUIPPED + SPEC-LIBP2P-VARINT-RT sole NOT_EQUIPPED":
    let reg = committedCatalog()
    var equipped = 0
    var notEquipped: seq[string] = @[]
    for entry in reg.entries:
      if laneDispatchEquipped(entry):
        inc equipped
      else:
        notEquipped.add(entry.specId)
    check equipped == 6
    check notEquipped == @["SPEC-LIBP2P-VARINT-RT"]

  test "legacy chain arms: adapter none, laneDispatchEquipped true":
    let reg = committedCatalog()
    for relPath in [base36RelationalRegistryEntryRelPath,
                    base32RemRegistryEntryRelPath]:
      var entryOpt = none(RegistryEntry)
      for entry in reg.entries:
        if entry.specRelPath == relPath:
          entryOpt = some(entry)
          break
      check entryOpt.isSome
      let entry = entryOpt.get
      check capabilityAdapterFor(entry).isNone
      check laneDispatchEquipped(entry)

  test "adapter vs dispatch-truth divergence is exactly the two legacy relPaths":
    let reg = committedCatalog()
    var diverged: seq[string] = @[]
    for entry in reg.entries:
      if laneDispatchEquipped(entry) != capabilityAdapterFor(entry).isSome:
        diverged.add(entry.specRelPath)
    check diverged == @["base36_sizing_relational_spec.json",
                        "nim_stew_base32_rem_spec.json"]
