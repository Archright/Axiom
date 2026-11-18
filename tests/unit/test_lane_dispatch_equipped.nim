## Lane dispatch equipped disclosure — `ax capability` authority unit tests
## (byo_agent_proposition_contract.md §11 A13; BYOA 5.1 review defect fix).
##
## Measured here (the committed config/spec catalog is the fixture — the
## engine is the SSOT, the CLI only projects):
##   1. Distribution: exactly 7 EQUIPPED entries + SPEC-LIBP2P-VARINT-RT as
##      the sole NOT_EQUIPPED entry.
##   2. All 7 equipped lanes are flipped adapter arms: the beta-composition
##      (base36 sizing relational, capBetaComposition) and term-splice
##      (base32 rem, capTermSplice) entries have flipped adapters
##      (capabilityAdapterFor some) and ARE equipped through them
##      (laneDispatchEquipped true) — the legacy overlay/remOverlay cascade
##      in prepareProofRun is removed, so dispatch is adapter-only.
##   3. The divergence set between capabilityAdapterFor and
##      laneDispatchEquipped is EMPTY — every entry's verdicts agree
##      (equipped ⇔ adapter present).

import std/[options, unittest]
import ../../src/core/results
import ../../src/cli/axiom_engine
import ../../src/cli/external_subject_registry

proc committedCatalog(): ExternalSubjectRegistry =
  let regRes = loadExternalSubjectRegistry()
  if regRes.isErr:
    raise newException(ValueError, "committed catalog unavailable: " & regRes.error)
  regRes.get()

suite "lane dispatch equipped disclosure — flipped adapters are dispatch truth":
  test "committed catalog: 7 EQUIPPED + SPEC-LIBP2P-VARINT-RT sole NOT_EQUIPPED":
    let reg = committedCatalog()
    var equipped = 0
    var notEquipped: seq[string] = @[]
    for entry in reg.entries:
      if laneDispatchEquipped(entry):
        inc equipped
      else:
        notEquipped.add(entry.specId)
    check equipped == 7
    check notEquipped == @["SPEC-LIBP2P-VARINT-RT"]

  test "flipped adapter arms: adapter some, laneDispatchEquipped true":
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
      check capabilityAdapterFor(entry).isSome
      check laneDispatchEquipped(entry)

  test "adapter vs dispatch-truth divergence is empty":
    let reg = committedCatalog()
    var diverged: seq[string] = @[]
    for entry in reg.entries:
      if laneDispatchEquipped(entry) != capabilityAdapterFor(entry).isSome:
        diverged.add(entry.specRelPath)
    check diverged.len == 0
