@legacy
Feature: ASI SSOT — TUI reads fresh proof state
  ax report (TUI) computes ASI from ax_proof_state.json in O(1),
  eliminating stale cache discrepancies permanently.

  @deprecated
  Scenario: TUI ASI matches proof state
    Given ax_proof_state.json has verified=1592, unattempted=147
    When ax report is called without --calculate-asi
    Then TUI header shows ASI matching verified/total ratio

  Scenario: Cache delete does not affect TUI
    Given asi_cache.json is deleted
    When ax report is called
    Then TUI still shows correct ASI from proof state

  Scenario: Zero verified shows ASI 0.0000
    Given proof state has 0 verified entries
    When ax report is called
    Then TUI shows ASI 0.0000

  Scenario: ax report state-file branch emits machine-readable lines
    Given a proof state file exists with entries
    When ax report is called without --json
    Then logLines contain proofStatusMatrix and status=symbol= aligned rows
    And logLines contain stateFile= absolute path

  Scenario: ax report assigns global IDs for inspect/trace consistency
    Given a proof state file has attempted entries
    When ax report is called
    Then attempted entries have sequential id=#NN values
    And unattempted entries have no id field

  Scenario: renderReportStdoutLines respects emitJson contract
    Given an AxCommandCliResult with emitJson=true and outputJson set
    When renderReportStdoutLines is called
    Then it returns outputJson only
    Given an AxCommandCliResult with emitJson=false and logLines set
    When renderReportStdoutLines is called
    Then it returns logLines only

  @deprecated
  Scenario: runReportCli with srcRootOverride isolates source graph for ASI calculation
    Given a temporary certificate directory with a stale fingerprint
    And a temporary source directory with the matching source file
    When runReportCli is called with --calculate-asi and srcRootOverride
    Then the report must reflect the isolated source graph
    And ASI must not be diluted by the full project source tree
