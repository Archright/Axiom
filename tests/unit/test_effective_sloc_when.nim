import std/[unittest, options, sets, strutils]
import compiler/[ast, idents]
import core/results
import core/sloc_policy
import core/ast_kernel
import tests/sloc/golden_helpers

suite "evalWhenConditionAST - Tier1 pure constant evaluation":
  test "true identifier → some(true)":
    let src = "when true: discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    check whenStmt.kind == nkWhenStmt
    let cond = whenCond(whenStmt)
    check cond.kind == nkIdent
    check cond.ident.s == "true"
    let result = evalWhenConditionAST(cond)
    check result.isSome()
    check result.get() == true

  test "false identifier → some(false)":
    let src = "when false: discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let result = evalWhenConditionAST(cond)
    check result.isSome()
    check result.get() == false

  test "1 == 1 → some(true)":
    let src = "when 1 == 1: discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let result = evalWhenConditionAST(cond)
    check result.isSome()
    check result.get() == true

  test "1 != 2 → some(true)":
    let src = "when 1 != 2: discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let result = evalWhenConditionAST(cond)
    check result.isSome()
    check result.get() == true

  test "1 == 2 → some(false)":
    let src = "when 1 == 2: discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let result = evalWhenConditionAST(cond)
    check result.isSome()
    check result.get() == false

  test "defined(android) → none (not Tier1)":
    let src = "when defined(android): discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let result = evalWhenConditionAST(cond)
    check result.isNone()

  test "unknown expression → none":
    let src = "when someUnknownExpr: discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let result = evalWhenConditionAST(cond)
    check result.isNone()

suite "evalWhenConditionCtx - Tier2 declarative context evaluation":
  test "defined(posix) in knownDefined → some(true)":
    var ctx = WhenContext()
    ctx.defines.knownDefined.incl("posix")
    let src = "when defined(posix): discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let result = evalWhenConditionCtx(cond, ctx)
    check result.isSome()
    check result.get() == true

  test "defined(windows) in knownUndefined → some(false)":
    var ctx = WhenContext()
    ctx.defines.knownUndefined.incl("windows")
    let src = "when defined(windows): discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let result = evalWhenConditionCtx(cond, ctx)
    check result.isSome()
    check result.get() == false

  test "defined(android) not in either set → none (Unknown)":
    var ctx = WhenContext()
    ctx.defines.knownDefined.incl("posix")
    let src = "when defined(android): discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let result = evalWhenConditionCtx(cond, ctx)
    check result.isNone()

  test "defined(x) with no context → none (Unknown)":
    let ctx = WhenContext()
    let src = "when defined(x): discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let result = evalWhenConditionCtx(cond, ctx)
    check result.isNone()

  test "non-defined call → none":
    var ctx = WhenContext()
    ctx.defines.knownDefined.incl("posix")
    let src = "when foo(): discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let result = evalWhenConditionCtx(cond, ctx)
    check result.isNone()

suite "evalWhen - combined Tier1 → Tier2 → Unknown":
  test "when true → whenTrue":
    let src = "when true: discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let ctx = WhenContext()
    check evalWhen(cond, ctx) == whenTrue

  test "when false → whenFalse":
    let src = "when false: discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let ctx = WhenContext()
    check evalWhen(cond, ctx) == whenFalse

  test "when 1==1 → whenTrue":
    let src = "when 1 == 1: discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    let ctx = WhenContext()
    check evalWhen(cond, ctx) == whenTrue

  test "when defined(posix) with posix in knownDefined → whenTrue":
    var ctx = WhenContext()
    ctx.defines.knownDefined.incl("posix")
    let src = "when defined(posix): discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    check evalWhen(cond, ctx) == whenTrue

  test "when defined(android) with no context → whenUnknown":
    let ctx = WhenContext()
    let src = "when defined(android): discard"
    let node = parseSrc(src)
    let whenStmt = node[0]
    let cond = whenCond(whenStmt)
    check evalWhen(cond, ctx) == whenUnknown

suite "effectiveSloc(ctx) integration — when branches":
  test "when true: active branch only, effectiveSloc=Ok(2)":
    let src = "when true:\n  discard"
    let res = effectiveSlocOf(src, WhenContext())
    check res.isOk()
    check res.get() == 2

  test "when false: branch excluded, effectiveSloc=Ok(0)":
    let src = "when false:\n  discard"
    let res = effectiveSlocOf(src, WhenContext())
    check res.isOk()
    check res.get() == 0

  test "when defined(posix) knownDefined: effectiveSloc=Ok(2)":
    var ctx = WhenContext()
    ctx.defines.knownDefined.incl("posix")
    let src = "when defined(posix):\n  discard"
    let res = effectiveSlocOf(src, ctx)
    check res.isOk()
    check res.get() == 2

  test "when defined(posix) knownUndefined: effectiveSloc=Ok(0)":
    var ctx = WhenContext()
    ctx.defines.knownUndefined.incl("posix")
    let src = "when defined(posix):\n  discard"
    let res = effectiveSlocOf(src, ctx)
    check res.isOk()
    check res.get() == 0

  test "when defined(posix) Unknown: effectiveSloc=Err(urMissingSemanticContext)":
    let ctx = WhenContext()
    let src = "when defined(posix):\n  discard"
    let res = effectiveSlocOf(src, ctx)
    check res.isErr()
    check res.error == urMissingSemanticContext

  test "when sizeof(int)==8: type-dependent, effectiveSloc=Err(urMissingSemanticContext)":
    let src = "when sizeof(int) == 8:\n  discard"
    let res = effectiveSlocOf(src, WhenContext())
    check res.isErr()
    check res.error == urMissingSemanticContext

  test "when true/false both-branch: when true branch active → effectiveSloc=Ok(2)":
    let src = "when true:\n  discard\nelse:\n  discard"
    let res = effectiveSlocOf(src, WhenContext())
    check res.isOk()
    check res.get() == 2

  test "when true/false both-branch: when false branch active → effectiveSloc=Ok(1)":
    let src = "when false:\n  discard\nelse:\n  discard"
    let res = effectiveSlocOf(src, WhenContext())
    check res.isOk()
    check res.get() == 1

  test "sourceSloc counts all syntactic when branches (both-branch)":
    let src = "when true:\n  discard\nelse:\n  discard"
    check sourceSlocOf(src) == 4

  test "sourceSloc counts proc declaration + body":
    let src = "proc f() =\n  result = 1"
    check sourceSlocOf(src) == 2

  test "effectiveSloc with simple source (no when)":
    let ctx = WhenContext()
    let src = "proc f() =\n  result = 1"
    let res = effectiveSlocOf(src, ctx)
    check res.isOk()
    check res.get() == 2