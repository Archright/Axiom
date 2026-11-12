Feature: Topology CLI — topology analysis and verification queue generation
  As the Integrity Engine,
  I want a CLI module that scans source files and builds a topology analysis,
  So that the verification pipeline can prioritize nodes by structural importance.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: computeTopologyNodeDepths returns correct depths
    Given a SorterState with nodes A, B, C where C depends on B and B depends on A
    When I call computeTopologyNodeDepths
    Then node A has depth 0
    And node B has depth 1
    And node C has depth 2

  Scenario: topologyImpactIndex weights transitive dependents highest
    Given a TopologyNodeMetric with transitiveDependentCount 10 dependentCount 5 centralityScore 3 couplingScore 2
    When I call topologyImpactIndex
    Then the result is 70

  Scenario: axProofStatusValue maps verified status
    Given AxProofStatus is axProofVerified
    When I call axProofStatusValue
    Then the result string is "verified"

  Scenario: axProofStatusValue maps counter example found
    Given AxProofStatus is axProofCounterExampleFound
    When I call axProofStatusValue
    Then the result string is "counter_example_found"

  Scenario: axProofStatusValue maps timed out
    Given AxProofStatus is axProofTimedOut
    When I call axProofStatusValue
    Then the result string is "timed_out"

  Scenario: mapAxProofStatus maps orchestration verified to axProofVerified
    Given OrchestrationNodeStatus is orchestrationVerified
    When I call mapAxProofStatus
    Then the result is axProofVerified

  Scenario: mapAxProofStatus maps proof failed to counter example found
    Given OrchestrationNodeStatus is orchestrationProofFailed
    When I call mapAxProofStatus
    Then the result is axProofCounterExampleFound

  Scenario: mapSemanticProofStatus maps verified response
    Given a SemanticPayloadVerificationResponse with verified true
    When I call mapSemanticProofStatus
    Then the result is axProofVerified

  Scenario: mapSemanticProofStatus maps SAT response to counter example
    Given a SemanticPayloadVerificationResponse with status "sat"
    When I call mapSemanticProofStatus
    Then the result is axProofCounterExampleFound

  Scenario: computeSmartQueueLimit scales with processor count
    When I call computeSmartQueueLimit with plannedNodeCount 100 and processorCount 4
    Then the result is 8

  Scenario: computeSmartQueueLimit returns 1 for zero nodes
    When I call computeSmartQueueLimit with plannedNodeCount 0 and processorCount 4
    Then the result is 1

  Scenario: computeSmartQueueLimit caps at plannedNodeCount
    When I call computeSmartQueueLimit with plannedNodeCount 5 and processorCount 4
    Then the result is 5

  Scenario: computeSmartDiagnosisDepth scales with processor count
    When I call computeSmartDiagnosisDepth with repairTargetCount 20 and processorCount 4
    Then the result is 4

  Scenario: computeSmartDiagnosisDepth returns 1 for zero targets
    When I call computeSmartDiagnosisDepth with repairTargetCount 0 and processorCount 4
    Then the result is 1

  Scenario: collectTopologySourceFiles excludes build and nimcache directories
    Given a temporary source root with files in src/ and nimcache/ and build/
    When I call collectTopologySourceFiles
    Then only files under src/ are returned
    And the result is sorted deterministically

  Scenario: analyzeTopologySourceRoot returns error for missing directory
    When I call analyzeTopologySourceRoot for "/nonexistent/path"
    Then the result is an error

  Scenario: jsonFromTopologyAnalysis contains summary and queue entries
    Given a TopologyAnalysis with 3 verification nodes and 1 structural bottleneck
    When I call jsonFromTopologyAnalysis
    Then the JSON has a "summary" key
    And the JSON has a "verificationQueue" key
    And the JSON has a "structuralBottlenecks" key

  Scenario: renderVerifyTopologySummaryLines shows bottleneck info
    Given a TopologyAnalysis with 2 structural bottlenecks
    When I call renderVerifyTopologySummaryLines
    Then the first line is "Topology Scan: Complete"
    And one line contains "Structural Bottlenecks"
