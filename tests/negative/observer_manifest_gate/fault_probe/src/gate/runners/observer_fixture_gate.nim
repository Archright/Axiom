## Observer fixture runner — healthy-tree fixture for the observer-verdict
## golden/fixture tests (tests/negative/observer_manifest_gate/). Never
## compiled by the repository build; the manifest-consistency gate reads it
## as text only. Carries the documented direct-run contract
## (`when isMainModule`) that the gate's manual-stage check (Check 10)
## requires, and is registered by the sibling manifest.d entry
## observer-fixture-gate.json so Check 6 finds its SSOT.

proc runObserverFixture(): int =
  ## Fixture run contract: a healthy fixture tree validates trivially.
  0

when isMainModule:
  quit(runObserverFixture())
