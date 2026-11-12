## Architecture Config Gate — Business Scenario Tests
##
## Verifies the Config-as-Code architecture enforcement gate:
##   1. YAML config loads and parses with 4 required rules
##   2. Layer isolation detects core importing cli (violation)
##   3. Layer isolation passes for valid core imports (no violation)
##   4. SSOT mutation detects cert.status outside certificate_manager
##   5. SSOT mutation passes inside certificate_manager.nim

import std/[unittest, os, json, strutils]
import gate/runners/architecture_config_gate

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc makeMinimalConfig(): JsonNode =
  ## Create a minimal config for isolated tests.
  %*{"rules": {
    "layer-isolation": {
      "severity": "error",
      "source": "src/core",
      "forbidden": ["src/cli", "src/ui"],
      "exempt": []
    },
    "domain-to-infra": {
      "severity": "error",
      "source": "src/core",
      "forbidden": ["src/verification"],
      "exempt": ["persona_context_init"]
    },
    "srp-import-prefix": {
      "severity": "warn",
      "max_prefixes": 3,
      "scan_roots": ["src/core"]
    },
    "ssot-mutation": {
      "severity": "error",
      "patterns": ["cert.status =", "cert.reason ="],
      "exempt_files": ["certificate_manager.nim"]
    }
  }}

proc makeTmpRepo(): string =
  ## Create a temporary repo-like directory structure.
  let tmpDir = getTempDir() / "axiom_arch_config_gate_test_" & $getCurrentProcessId()
  createDir(tmpDir / "src" / "core")
  createDir(tmpDir / "src" / "cli")
  result = tmpDir

proc cleanupTmpRepo(dir: string) =
  ## Remove temporary directory tree.
  try:
    for kind, path in walkDir(dir, relative = false):
      case kind
      of pcFile, pcLinkToFile: removeFile(path)
      of pcDir, pcLinkToDir: removeDir(path)
      else: discard
    removeDir(dir)
  except CatchableError:
    discard

# ---------------------------------------------------------------------------
# Test Suite
# ---------------------------------------------------------------------------

suite "Architecture Config Gate — Config Loading":

  test "JSON config file exists at expected path":
    check fileExists("src/gate/configs/architecture_rules.json")

  test "JSON config parses and contains 4 rules":
    let content = readFile("src/gate/configs/architecture_rules.json")
    let config = parseJson(content)
    check config.hasKey("rules")
    let rules = config["rules"]
    check rules.len >= 4
    check rules.hasKey("layer-isolation")
    check rules.hasKey("domain-to-infra")
    check rules.hasKey("srp-import-prefix")
    check rules.hasKey("ssot-mutation")

  test "layer-isolation rule has severity error and forbidden list":
    let content = readFile("src/gate/configs/architecture_rules.json")
    let config = parseJson(content)
    let rule = config["rules"]["layer-isolation"]
    check rule{"severity"}.getStr() == "error"
    check rule{"source"}.getStr() == "src/core"
    check rule{"forbidden"}.len >= 2

  test "ssot-mutation rule has patterns and exempt_files":
    let content = readFile("src/gate/configs/architecture_rules.json")
    let config = parseJson(content)
    let rule = config["rules"]["ssot-mutation"]
    check rule{"severity"}.getStr() == "error"
    check rule{"patterns"}.len >= 2
    check rule{"exempt_files"}.len >= 1

suite "Architecture Config Gate — Layer Isolation":

  test "detects core importing cli (violation)":
    let tmpRoot = makeTmpRepo()
    defer: cleanupTmpRepo(tmpRoot)

    writeFile(tmpRoot / "src" / "core" / "bad_module.nim",
      "import cli/main\n\necho \"hello\"")

    let config = makeMinimalConfig()
    let violations = checkLayerIsolation(tmpRoot, config)
    check violations.len > 0
    check violations[0].ruleId == "layer-isolation"
    check violations[0].severity == "error"
    check "bad_module.nim" in violations[0].filePath

  test "passes for valid core-to-core imports":
    let tmpRoot = makeTmpRepo()
    defer: cleanupTmpRepo(tmpRoot)

    writeFile(tmpRoot / "src" / "core" / "good_module.nim",
      "import core/types/domain_types\n\necho \"hello\"")

    let config = makeMinimalConfig()
    let violations = checkLayerIsolation(tmpRoot, config)
    check violations.len == 0

  test "detects core importing ui (violation)":
    let tmpRoot = makeTmpRepo()
    defer: cleanupTmpRepo(tmpRoot)

    writeFile(tmpRoot / "src" / "core" / "ui_dep.nim",
      "import ui/reporter\n\necho \"hello\"")

    let config = makeMinimalConfig()
    let violations = checkLayerIsolation(tmpRoot, config)
    check violations.len > 0
    check violations[0].ruleId == "layer-isolation"

  test "exempts files matching exempt pattern":
    let tmpRoot = makeTmpRepo()
    defer: cleanupTmpRepo(tmpRoot)

    writeFile(tmpRoot / "src" / "core" / "persona_context_init.nim",
      "import cli/main\n\necho \"init\"")

    # Config must include the exempt entry for this test
    let config = %*{"rules": {
      "layer-isolation": {
        "severity": "error",
        "source": "src/core",
        "forbidden": ["src/cli", "src/ui"],
        "exempt": ["persona_context_init"]
      }
    }}
    let violations = checkLayerIsolation(tmpRoot, config)
    check violations.len == 0

suite "Architecture Config Gate — SSOT Mutation":

  test "detects cert.status outside certificate_manager (violation)":
    let tmpRoot = makeTmpRepo()
    defer: cleanupTmpRepo(tmpRoot)

    writeFile(tmpRoot / "src" / "core" / "analyzer.nim",
      "proc updateStatus(cert: Certificate) =\n  cert.status = Valid\n  echo \"done\"")

    let config = makeMinimalConfig()
    let violations = checkSsotMutation(tmpRoot, config)
    check violations.len > 0
    check violations[0].ruleId == "ssot-mutation"
    check violations[0].severity == "error"
    check "cert.status =" in violations[0].message

  test "passes inside certificate_manager.nim":
    let tmpRoot = makeTmpRepo()
    defer: cleanupTmpRepo(tmpRoot)

    writeFile(tmpRoot / "src" / "core" / "certificate_manager.nim",
      "proc setStatus(cert: Certificate) =\n  cert.status = Valid\n  cert.reason = \"ok\"")

    let config = makeMinimalConfig()
    let violations = checkSsotMutation(tmpRoot, config)
    check violations.len == 0

  test "detects cert.reason outside certificate_manager (violation)":
    let tmpRoot = makeTmpRepo()
    defer: cleanupTmpRepo(tmpRoot)

    writeFile(tmpRoot / "src" / "core" / "reporter.nim",
      "proc report(cert: Certificate) =\n  cert.reason = \"test\"")

    let config = makeMinimalConfig()
    let violations = checkSsotMutation(tmpRoot, config)
    check violations.len > 0
    check violations[0].ruleId == "ssot-mutation"

suite "Architecture Config Gate — Import Extraction":

  test "extracts single-line imports":
    let content = "import core/bmc/foo\n"
    let imports = extractImports(content)
    check imports.len == 1
    check imports[0].path == "core/bmc/foo"

  test "extracts from-import":
    let content = "from core/types/bar import Baz\n"
    let imports = extractImports(content)
    check imports.len == 1
    check imports[0].path == "core/types/bar"

  test "extracts multi-line imports":
    let content = "import\n  core/bmc/foo,\n  core/solver/bar\n"
    let imports = extractImports(content)
    check imports.len == 2

  test "skips std and pkg imports":
    let content = "import std/os\nimport pkg/checksums/sha256\nimport core/types/foo\n"
    let imports = extractImports(content)
    check imports.len == 1
    check imports[0].path == "core/types/foo"

  test "skips comments and blank lines":
    let content = "# This is a comment\nimport core/bmc/foo\n\n# Another comment\n"
    let imports = extractImports(content)
    check imports.len == 1

suite "Architecture Config Gate — Domain Prefix":

  test "extracts domain prefix from multi-segment path":
    check getDomainPrefix("core/bmc/foo") == "bmc"
    check getDomainPrefix("core/solver/bar") == "solver"
    check getDomainPrefix("cli/topology") == "topology"

  test "handles single-segment path":
    check getDomainPrefix("core") == "core"
