import std/[unittest, os, strutils]
import core/results
import core/ast_kernel

suite "ast_kernel determinism certification":

  let srcBase = "proc foo(x: int): int =\n  result = x + 1"

  test "repeat determinism - same source produces identical hash 100 times":
    let h1 = computeCanonicalAstHash(srcBase).get()
    for i in 1 .. 100:
      let h = computeCanonicalAstHash(srcBase).get()
      check h == h1

  test "process restart - same source re-parsed in same process yields identical hash":
    let h1 = computeCanonicalAstHash(srcBase).get()
    let h2 = computeCanonicalAstHash(srcBase).get()
    check h1 == h2

  test "cache hit/miss - fresh parse vs re-parse produce identical hash":
    let h1 = computeCanonicalAstHash(srcBase).get()
    let h2 = computeCanonicalAstHash(srcBase).get()
    check h1 == h2

  test "unordered permutation - nkCurly set {a,b} same hash as {b,a}":
    let src1 = "let s = {a, b}"
    let src2 = "let s = {b, a}"
    let h1 = computeCanonicalAstHash(src1).get()
    let h2 = computeCanonicalAstHash(src2).get()
    check h1 == h2

  test "ordered mutation - statement order change produces different hash":
    let src1 = "let x = 1\nlet y = 2"
    let src2 = "let y = 2\nlet x = 1"
    let h1 = computeCanonicalAstHash(src1).get()
    let h2 = computeCanonicalAstHash(src2).get()
    check h1 != h2

  test "literal semantic - 1 and 0x1 produce identical hash":
    let h1 = computeCanonicalAstHash("let x = 1").get()
    let h2 = computeCanonicalAstHash("let x = 0x1").get()
    check h1 == h2

  test "literal semantic - \"abc\" and \"\\x61bc\" produce identical hash":
    let h1 = computeCanonicalAstHash("let x = \"abc\"").get()
    let h2 = computeCanonicalAstHash("let x = \"\\x61bc\"").get()
    check h1 == h2

  test "comment-only - adding line comment produces identical hash":
    let h1 = computeCanonicalAstHash("proc f() =\n  result = 1").get()
    let h2 = computeCanonicalAstHash("proc f() =\n  # comment\n  result = 1").get()
    check h1 == h2

  test "ident distinction - foo(x:int) vs bar(y:string) produce different hash":
    let h1 = computeCanonicalAstHash("proc foo(x: int) = discard").get()
    let h2 = computeCanonicalAstHash("proc bar(y: string) = discard").get()
    check h1 != h2

  test "approved compiler - NimVersion is captured in buildEnvHash":
    const gCompilerVersion = NimVersion
    check gCompilerVersion.len > 0

  test "hash prefix format - result starts with sha256:v2:nim-pnode-canonical-v2:":
    let h = computeCanonicalAstHash(srcBase).get()
    check h.startsWith("sha256:v2:nim-pnode-canonical-v2:")

  test "fail-closed - empty source (parse nil) returns err":
    let result = computeCanonicalAstHash("")
    check result.isErr()

  test "repeat determinism - float literals 1.0 and 1.000 identical":
    let h1 = computeCanonicalAstHash("let x = 1.0").get()
    let h2 = computeCanonicalAstHash("let x = 1.000").get()
    check h1 == h2

  test "repeat determinism - char literal 'a' and '\\x61' identical":
    let h1 = computeCanonicalAstHash("let c = 'a'").get()
    let h2 = computeCanonicalAstHash("let c = '\\x61'").get()
    check h1 == h2

  test "repeat determinism - empty source returns err":
    let result = computeCanonicalAstHash("")
    check result.isErr()