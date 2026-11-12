import std/unittest
import core/parsers/expression_parser
import core/results

suite "parseUserCodeToRule contract":
  test "empty string returns err":
    let result = parseUserCodeToRule("")
    check result.isErr()

  test "parses x-=5 as subtract rule":
    let result = parseUserCodeToRule("x -= 5")
    check result.isOk()

  test "parses x+=3 as add rule":
    let result = parseUserCodeToRule("x += 3")
    check result.isOk()

  test "parses x=x-10 as subtract rule":
    let result = parseUserCodeToRule("x = x - 10")
    check result.isOk()

  test "parses x=x+7 as add rule":
    let result = parseUserCodeToRule("x = x + 7")
    check result.isOk()

  test "invalid code returns err":
    let result = parseUserCodeToRule("y = 1")
    check result.isErr()

suite "parseNaturalConstraintToInvariant contract":
  test "empty string returns err":
    let result = parseNaturalConstraintToInvariant("")
    check result.isErr()

  test "parses x>=0 as min value invariant":
    let result = parseNaturalConstraintToInvariant("x >= 0")
    check result.isOk()

  test "parses balance>=100 as min value invariant":
    let result = parseNaturalConstraintToInvariant("balance >= 100")
    check result.isOk()

  test "parses x<=10 as max value invariant":
    let result = parseNaturalConstraintToInvariant("x <= 10")
    check result.isOk()

  test "invalid constraint returns err":
    let result = parseNaturalConstraintToInvariant("something else")
    check result.isErr()
