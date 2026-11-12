@legacy
﻿
  Scenario: Deterministic unsat proof via injectContradiction
    Given an orchestration request with injectContradiction true
    When the proof is executed
    Then it should return verified without invoking the solver

