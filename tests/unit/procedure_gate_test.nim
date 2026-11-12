import std/unittest
import core/io/file_utils

proc parseCommitType(commitMsg: string): string =
  let colonIdx = commitMsg.find(':')
  if colonIdx < 0:
    return ""
  let commitTypeRaw = commitMsg.substr(0, colonIdx - 1)
  let parenIdx = commitTypeRaw.find('(')
  result = if parenIdx >= 0: commitTypeRaw.substr(0, parenIdx - 1) else: commitTypeRaw

suite "Procedure gate 4-step integrity predicates":
  test "isFeatureEvidenceFile matches ONLY tests/features/*.feature":
    check isFeatureEvidenceFile("tests/features/vacuity_ban.feature") == true
    check isFeatureEvidenceFile("tests/gateway/demo_feature_test.nim") == false
    check isFeatureEvidenceFile("src/core/gateway.nim") == false

  test "isBddEvidence matches tests/features/steps only":
    check isBddEvidence("tests/features/steps/common.nim") == true
    check isBddEvidence("tests/features/workflow_integrity.feature") == false
    check isBddEvidence("tests/features/vacuity_ban.feature") == false

  test "isTestEvidence matches tests/gateway and tests/unit only":
    check isTestEvidence("tests/gateway/gateway_pipeline_test.nim") == true
    check isTestEvidence("tests/unit/procedure_gate_test.nim") == true
    check isTestEvidence("tests/features/steps/common.nim") == false
    check isTestEvidence("src/cli/procedure_gate.nim") == false

  test "isHistoryFile matches docs/history":
    check isHistoryFile("docs/history/2026_05_refactoring.md") == true
    check isHistoryFile("AGENTS.md") == false
    check isHistoryFile("docs/spec/bmc_core.md") == false

  test "isImplementationFile matches nim, lean, smt2":
    check isImplementationFile("src/core/gateway.nim") == true
    check isImplementationFile("src/semantic_proofs/theorem.lean") == true
    check isImplementationFile("docs/spec/bmc_core.md") == false

suite "Commit type parsing":
  test "parseCommitType extracts type from conventional commits":
    check parseCommitType("feat: add feature") == "feat"
    check parseCommitType("fix: bug fix") == "fix"
    check parseCommitType("docs: update readme") == "docs"

  test "parseCommitType strips scope parentheses":
    check parseCommitType("refactor(build): optimize cache") == "refactor"
    check parseCommitType("feat(cli): new command") == "feat"
    check parseCommitType("fix(gate): repair hook") == "fix"

  test "parseCommitType returns empty for merge commits":
    check parseCommitType("Merge branch 'core' into main") == ""
    check parseCommitType("Merge pull request #123") == ""

  test "parseCommitType returns empty for non-conventional messages":
    check parseCommitType("update files") == ""
    check parseCommitType("WIP") == ""

when defined(axiomHeavyTest):
  discard ## DEBT#052: Integration test placeholder — exercises evaluateProcedureGate end-to-end.
