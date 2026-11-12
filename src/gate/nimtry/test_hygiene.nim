import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Test hygiene checks — detects standalone entry-point blocks in test files.
##
## Test files should use the standard test runner infrastructure rather than
## inline standalone entry-point blocks. Whitelisted runner/orchestrator files
## are exempt because they legitimately need standalone execution.

import std/os
import std/strutils
import gate/nimtry/nimtry_registry
import std/sets
import gate/architecture_ast_facts
import gate/rule_patterns
import core/gate/architecture_policy
import core/utils/file_utils
import core/trusted/axiom_pragmas

const
  ## Files that legitimately use standalone entry-point blocks in tests/.
  ## These are runner/orchestrator/fuzz infrastructure, not individual test files.
  whitelistedFiles = toHashSet([
    "tests/gateway/all_gateway_runner.nim",
    "tests/unit/unit_test_orchestrator.nim",
    "tests/fuzz/fuzz_gate.nim",
    "tests/fuzz/generate_fuzz_input.nim",
  ])

  ## Directory prefixes exempt from hygiene checks.
  ## Auto-generated test files (traced back to .feature files per §0.7)
  ## legitimately use standalone entry-point blocks for execution.
  whitelistedDirPrefixes = [
    # "tests/generated/" removed in Phase 0 purge (DEBT_REGISTRY §Purge protocol)
    "tests/generated_code_dump/",
  ]

proc checkWhenIsMainModuleInTests*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan tests/ for standalone entry-point blocks outside the whitelist.
  ## This is a source-text scan since allFacts only covers src/ files.
  let repoRoot = try: getCurrentDir() except OSError: "."
  var testDirs: seq[string] = @[]
  for subdir in ["tests/unit", "tests/gateway", "tests/performance", "tests/fuzz",
                 "tests/negative", "tests/integration", "tests/examples",
                 "tests/reproduction", "tests/generated_code_dump"]:
    if dirExists(repoRoot / subdir):
      testDirs.add(repoRoot / subdir)

  for testDir in testDirs:
    try:
      for path in walkDirRec(testDir):
        if not path.endsWith(".nim"):
          continue
        # Normalize to repo-relative path for whitelist matching
        var relPath = path
        let prefix = repoRoot.replace("\\", "/") & "/"
        if relPath.startsWith(prefix):
          relPath = relPath[prefix.len .. ^1]
        relPath = relPath.replace("\\", "/")

        # Skip whitelisted runner/orchestrator files
        if whitelistedFiles.contains(relPath):
          continue

        # Skip whitelisted directory prefixes (auto-generated tests, §0.7)
        var skipDir = false
        for prefix in whitelistedDirPrefixes:
          if relPath.startsWith(prefix):
            skipDir = true
            break
        if skipDir:
          continue

        let content = try: readFileSafe(path) except CatchableError: continue
        let lines = content.splitLines()
        for i, line in lines:
          if ("when " & "isMainModule") in line.strip():
            result.add(ArchitectureViolationArtifact(
              rule: "HYGIENE-when-isMainModule-in-test",
              detail: relPath & ":" & $(i + 1) &
                " 'when " & "isMainModule' in test file. " &
                "Use the standard test runner infrastructure instead. " &
                "Whitelisted runners: all_gateway_runner.nim, unit_test_orchestrator.nim, fuzz_gate.nim, generate_fuzz_input.nim",
              files: @[relPath],
              severity: "warning",
            ))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

proc registerHygieneQueries*(queries: var seq[NimtryQuery]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # HYGIENE: standalone entry-point blocks in test files (test_hygiene.nim)
  queries.add(NimtryQuery(
    name: "hygiene-when-isMainModule-in-test",
    rule: "HYGIENE",
    severity: "warning",
    taxonomy: structural,
    checker: checkWhenIsMainModuleInTests
  ))

  # SAFETY: Tautological assertions — check true/false violates §0.8

{.pop.}
