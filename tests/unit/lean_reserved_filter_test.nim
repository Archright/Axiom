import std/unittest
import core/judge/the_judge_eval

suite "Lean Reserved Identifier Filter":
  test "import is filtered to v_import":
    check sanitizeLeanIdentifierName("import") == "v_import"

  test "open is filtered":
    check sanitizeLeanIdentifierName("open") == "v_open"

  test "return is filtered":
    check sanitizeLeanIdentifierName("return") == "v_return"

  test "Std is filtered":
    check sanitizeLeanIdentifierName("Std") == "v_Std"

  test "ordinary name passes through":
    check sanitizeLeanIdentifierName("my_func") == "my_func"

  test "from is filtered":
    check sanitizeLeanIdentifierName("from") == "v_from"

  test "for is filtered":
    check sanitizeLeanIdentifierName("for") == "v_for"

  test "in is filtered":
    check sanitizeLeanIdentifierName("in") == "v_in"
