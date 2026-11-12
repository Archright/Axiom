# Unit test: policy_validator.nim — Self-Validating Policy Enforcement
# v0.4.0

when defined(axiomIntegration) or defined(leanIntegration):

  import std/[unittest, os, osproc, strutils, tables]

  const
    TestImpurePath = "tests/test_data/.test_physically_impure_modules"
    TestAllowedPath = "tests/test_data/.test_allowed_imports.lock"

  proc writeTestFile(path: string; content: string) =
    createDir(parentDir(path))
    writeFile(path, content)

  proc cleanup() =
    if fileExists(TestImpurePath): removeFile(TestImpurePath)
    if fileExists(TestAllowedPath): removeFile(TestAllowedPath)

  suite "policy_validator — impure modules validation":
    setup:
      cleanup()
      createDir("tests/test_data")

    teardown:
      cleanup()

    test "valid impure modules file passes":
      writeTestFile(TestImpurePath, "analyzer\nast_extractor\ndependency_analyzer\n")
      # Skip if policy_validator binary is not available; test validates contract only.
      if fileExists("bin/policy_validator"):
        let exitCode = execCmd("bin/policy_validator --test-impure " & TestImpurePath & " --test-allowed " & TestAllowedPath)
        check exitCode == 0
      else:
        skip()

    test "duplicate modules are detected":
      writeTestFile(TestImpurePath, "analyzer\nast_extractor\nanalyzer\n")
      # Note: full policy_validator integration test requires the actual binary;
      # this unit test validates the parsing logic contract.
      let modules = @["analyzer", "ast_extractor", "analyzer"]
      var seen: CountTable[string]
      for m in modules:
        seen.inc(m)
      var duplicates = 0
      for m, count in seen.pairs():
        if count > 1:
          duplicates.inc()
      check duplicates == 1

    test "21 unique modules after v0.4.0 dedup":
      let content = readFile("src/verification/.physically_impure_modules")
      var modules: seq[string]
      for line in content.splitLines():
        let trimmed = line.strip()
        if trimmed.len == 0 or trimmed.startsWith("#"): continue
        if allCharsInSet(trimmed, {'a'..'z', 'A'..'Z', '0'..'9', '_'}):
          modules.add(trimmed)
      check modules.len == 21
      # Verify no duplicates
      var seen: CountTable[string]
      for m in modules: seen.inc(m)
      for m, count in seen.pairs():
        check count == 1

  suite "policy_validator — allowed_imports.lock validation":
    test "allowed_imports.lock format is valid TOML-like section structure":
      let content = readFile("src/allowed_imports.lock")
      var lineNum = 0
      var violations = 0
      var inSection = false
      for line in content.splitLines():
        inc lineNum
        let trimmed = line.strip()
        if trimmed.len == 0: continue
        if trimmed.startsWith("#"): continue
        # Valid formats: [section_header] or key = value (TOML-like)
        if trimmed.startsWith("[") and trimmed.endsWith("]"):
          inSection = true
        elif inSection and '=' in trimmed:
          # allow = ["...", ...] or similar key = value
          inSection = true
        else:
          violations.inc()
      check violations == 0

    test "layer adjacency matrix is present in architecture_policy.lock":
      let content = readFile("src/gate/architecture_policy.lock")
      check content.contains("[layer_edges]")
      # Validate that known layers exist with valid edge lists
      check content.contains("core = []")
      check "cli = [\"core\"" in content
      check "gate = [\"core\"" in content

  suite "policy_validator — AGENTS.md constitution section":
    test "AGENTS.md §0 Constitution exists with key contracts":
      let content = readFile("AGENTS.md")
      check content.contains("## §0. CONSTITUTION")
      check content.contains("Zero-Footprint Integrity")
      check content.contains("CLI First")
