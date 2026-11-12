# NIMTRY TEST FIXTURE — intentionally violates SoC (Separation of Concerns)
#
# This fixture simulates a module in `src/core/` (Domain layer) that imports
# from `src/cli/` and `src/gate/` (forbidden layers). According to the policy:
#   layer_edges.core = []  (core layer cannot import from any other layer)
#
# NOTE: The layer check (`soc-layer-imports`) requires the file path to
# match a policy layer pattern (`src/core/`, `src/cli/`, etc.). A fixture
# in `tests/unit/nimtry_fixtures/` does not match any layer pattern.
#
# To verify, copy this file to `src/core/` and run:
#   cp tests/unit/nimtry_fixtures/soc_violation.nim src/core/soc_violation_fixture.nim
#   bin/nimtry src/core/soc_violation_fixture.nim
# Expected: 3 violations of [SoC] [soc-layer-imports]
# All imports below are real modules from forbidden layers (cli/, gate/)
# that resolve during nim check but violate core's empty layer_edges.

import cli/axiom_engine
import cli/wf_semantic
import gate/gate_list

proc dummyCoreFn*(): int =
  ## Dummy function; the violation is the import itself.
  result = 42
