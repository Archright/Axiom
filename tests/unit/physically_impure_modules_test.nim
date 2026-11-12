import std/unittest
import std/strutils
import std/os

suite "physically impure modules registry":
  test "gateway is registered as physically impure in core":
    let content = readFile(getCurrentDir() / "src" / "core" / ".physically_impure_modules")
    check content.contains("gateway")

  test "json_utils is registered as physically impure in core":
    let content = readFile(getCurrentDir() / "src" / "core" / ".physically_impure_modules")
    check content.contains("json_utils")

  test "ast_extractor is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("ast_extractor")

  test "analyzer is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("analyzer")

  test "dependency_analyzer is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("dependency_analyzer")

  test "gate_registry is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("gate_registry")

  test "gate_rules is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("gate_rules")

  test "healing_orchestrator is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("healing_orchestrator")

  test "discovery_error is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("discovery_error")

  test "integrity_guard is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("integrity_guard")

  test "lean_lsp is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("lean_lsp")

  test "leanstral_gateway is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("leanstral_gateway")

  test "leanstral_prompt is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("leanstral_prompt")

  test "pipeline_core_runner is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("pipeline_core_runner")

  test "pipeline_lean_spec_inference is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("pipeline_lean_spec_inference")

  test "pipeline_negative_scan is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("pipeline_negative_scan")

  test "proof_summarizer is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("proof_summarizer")

  test "proof_synthesis_engine is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("proof_synthesis_engine")

  test "static_rules is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("static_rules")

  test "thought_dashboard is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("thought_dashboard")

  test "translation_validator is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("translation_validator")

  test "universal_pipeline is registered as physically impure in verification":
    let content = readFile(getCurrentDir() / "src" / "verification" / ".physically_impure_modules")
    check content.contains("universal_pipeline")
