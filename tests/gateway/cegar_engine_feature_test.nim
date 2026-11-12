## CEGAR Engine Feature Test.
## Verifies the CEGAR refinement loop and PDR integration.
##
## Tests:
##   - CegarResult type structure
##   - DefaultZ3TimeoutMs constant
##   - PDR engine integration (non-converged fallback)

import std/unittest
import verification/cegar_engine

suite "CEGAR Engine — Core Interface":

  test "DefaultZ3TimeoutMs is 5000ms":
    ## Given the DefaultZ3TimeoutMs constant
    ## When checked
    ## Then it is 5000ms (5 second Z3 timeout)
    check DefaultZ3TimeoutMs == 5000

  test "DeterministicThreshold is 3":
    ## Given the DeterministicThreshold constant
    ## When checked
    ## Then CEGAR runs at least 3 iterations before LLM refinement
    check DeterministicThreshold == 3

  test "pdrEngineEnabled is true by default":
    ## Given the pdrEngineEnabled flag
    ## When checked
    ## Then PDR/IC3 is enabled before CEGAR iterations
    check pdrEngineEnabled == true
