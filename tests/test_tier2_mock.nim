import std/[unittest, strutils, os, options]
import core/ir/ir_types
import ../src/core/verifier/legislator

proc mockClaudeProvider(prompt: string): string =
  if "induction" in prompt.toLowerAscii():
    return "```lean\nby\n  intro\n  induction x <;> simp [*]\n```"
  return "by simp [*]"

suite "Tier 2 LLM Engine & Parser Test":
  setup:
    gLLMCallImpl = proc(provider: LLMProvider, prompt: string, timeoutSec: int): string =
      return mockClaudeProvider(prompt)

  teardown:
    gLLMCallImpl = nil

  test "extractTacticBlock cleans Markdown fences correctly":
    let rawResponse = "```lean\nby\n  intro\n  induction x <;> simp [*]\n```"
    let cleaned = extractTacticBlock(rawResponse)
    check cleaned == "by\n  intro\n  induction x <;> simp [*]"

  test "extractTacticBlock handles plain text":
    let rawResponse = "by simp [*]"
    let cleaned = extractTacticBlock(rawResponse)
    check cleaned == "by simp [*]"

  test "Full Tier 2 Loop with Mock Provider":
    let ir = AxiomIRNode(name: "testInduction" & $getCurrentProcessId())
    let result = callLeanstralWithTimeout(ir)

    check result.isSome
    check result.get().contains("induction")
