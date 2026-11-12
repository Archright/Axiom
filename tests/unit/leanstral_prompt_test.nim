import std/unittest
import std/strutils
import verification/leanstral_prompt

suite "buildLeanstralPrompt contract":
  test "includes function name in prompt":
    let ctx = LeanstralPromptContext(
      modulePath: "src/test.nim",
      functionName: "withdraw",
      sourceContext: "proc withdraw(): int = 1",
    )
    let prompt = buildLeanstralPrompt(ctx)
    check prompt.contains("withdraw")

  test "includes source code in prompt":
    let ctx = LeanstralPromptContext(
      modulePath: "src/test.nim",
      functionName: "foo",
      sourceContext: "proc foo(): int = 42",
    )
    let prompt = buildLeanstralPrompt(ctx)
    check prompt.contains("foo")
    check prompt.contains("42")
