{.push raises: [CatchableError].}

## formal_text_diff_feature_test.nim — Gateway test for formal_text_diff
##
## Tests the FSM-based diff classification engine.

import std/[unittest, strutils]
import core/utils/formal_text_diff

suite "Formal Text Diff Classification":
  test "Whitespace-only changes classified as ckWhitespace":
    let diff = "+   \n-  \n+  "
    check classifyChange(diff) == ckWhitespace

  test "Single-line comment changes classified as ckComment":
    let diff = "+# This is a comment\n-# Old comment"
    check classifyChange(diff) == ckComment

  test "Multi-line comment changes classified as ckComment":
    let diff = "+#[\n+This is a\n+multi-line comment\n+]#"
    check classifyChange(diff) == ckComment

  test "Nested multi-line comments handled correctly":
    let diff = "+#[\n+outer #[ inner ]# comment\n+]#"
    check classifyChange(diff) == ckComment

  test "Pragma-only changes classified as ckPragma":
    let diff = "+{.push raises: [].}\n-{.push raises: [CatchableError].}"
    check classifyChange(diff) == ckPragma

  test "Logic changes classified as ckLogic":
    let diff = "+proc foo(): int =\n+  result = 42"
    check classifyChange(diff) == ckLogic

  test "Mixed pragma and logic defaults to ckLogic":
    let diff = "+{.push raises: [].}\n+proc bar() = discard"
    check classifyChange(diff) == ckLogic

  test "Empty diff classified as ckWhitespace":
    let diff = ""
    check classifyChange(diff) == ckWhitespace

  test "Context lines (no +/-) are ignored":
    let diff = " context line\n+proc foo() = discard"
    check classifyChange(diff) == ckLogic

{.pop.}
