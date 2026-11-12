import std/unittest
import std/sets
import std/tables
import core/types/domain_types
import verification/dependency_analyzer

suite "collectDependencies contract":
  test "filters out empty and self-references":
    let cert = FunctionCertificate(
      functionName: "foo",
      calls: @["bar", "", "foo", "baz"]
    )
    let deps = collectDependencies(cert)
    check deps == @["bar", "baz"]

  test "deduplicates repeated calls":
    let cert = FunctionCertificate(
      functionName: "foo",
      calls: @["bar", "bar", "baz", "baz"]
    )
    let deps = collectDependencies(cert)
    check deps == @["bar", "baz"]

  test "empty calls returns empty":
    let cert = FunctionCertificate(functionName: "foo")
    let deps = collectDependencies(cert)
    check deps.len == 0

suite "normalizeDependencyName contract":
  test "empty dep returns empty":
    let moduleFns = toHashSet(["foo"])
    check normalizeDependencyName("", "mod", moduleFns) == ""

  test "already qualified name is preserved":
    let moduleFns = toHashSet(["foo"])
    check normalizeDependencyName("mod.foo", "mod", moduleFns) == "mod.foo"

  test "unqualified local function gets module prefix":
    let moduleFns = toHashSet(["foo", "bar"])
    check normalizeDependencyName("foo", "mod", moduleFns) == "mod.foo"

  test "unqualified external function stays bare":
    let moduleFns = toHashSet(["foo"])
    check normalizeDependencyName("bar", "mod", moduleFns) == "bar"

suite "buildReverseDependencies contract":
  test "builds correct reverse index":
    let certs = @[
      FunctionCertificate(functionName: "a", calls: @["b", "c"]),
      FunctionCertificate(functionName: "b", calls: @["c"]),
      FunctionCertificate(functionName: "c", calls: @[])
    ]
    let rev = buildReverseDependencies(certs)
    check rev["b"] == @[0]
    check rev["c"] == @[0, 1]

  test "missing callee has no reverse deps":
    let certs = @[
      FunctionCertificate(functionName: "a", calls: @[])
    ]
    let rev = buildReverseDependencies(certs)
    check not rev.hasKey("b")

suite "detectCyclicFunctions contract":
  test "detects simple cycle a->b->a":
    let certs = @[
      FunctionCertificate(functionName: "a", calls: @["b"]),
      FunctionCertificate(functionName: "b", calls: @["a"])
    ]
    let cycles = detectCyclicFunctions(certs)
    check "a" in cycles
    check "b" in cycles

  test "self-cycles are filtered by collectDependencies and ignored":
    let certs = @[
      FunctionCertificate(functionName: "a", calls: @["a"])
    ]
    let cycles = detectCyclicFunctions(certs)
    check "a" notin cycles

  test "acyclic graph returns empty":
    let certs = @[
      FunctionCertificate(functionName: "a", calls: @["b"]),
      FunctionCertificate(functionName: "b", calls: @["c"]),
      FunctionCertificate(functionName: "c", calls: @[])
    ]
    let cycles = detectCyclicFunctions(certs)
    check cycles.len == 0

  test "disconnected cycle in larger graph":
    let certs = @[
      FunctionCertificate(functionName: "a", calls: @["b"]),
      FunctionCertificate(functionName: "b", calls: @["a"]),
      FunctionCertificate(functionName: "c", calls: @["d"]),
      FunctionCertificate(functionName: "d", calls: @[])
    ]
    let cycles = detectCyclicFunctions(certs)
    check "a" in cycles
    check "b" in cycles
    check "c" notin cycles
    check "d" notin cycles

suite "detectArchitecturalCyclicFunctions contract":
  test "ignores same-module mutual recursion":
    let certs = @[
      FunctionCertificate(modulePath: FilePath("core/json_scan.nim"), functionName: "skipJsonValue", calls: @["json_scan.skipJsonArray"]),
      FunctionCertificate(modulePath: FilePath("core/json_scan.nim"), functionName: "skipJsonArray", calls: @["json_scan.skipJsonValue"])
    ]
    let cycles = detectArchitecturalCyclicFunctions(certs)
    check cycles.len == 0

  test "detects cross-module certificate dependency cycles":
    let certs = @[
      FunctionCertificate(modulePath: FilePath("core/a.nim"), functionName: "alpha", calls: @["b.beta"]),
      FunctionCertificate(modulePath: FilePath("core/b.nim"), functionName: "beta", calls: @["a.alpha"])
    ]
    let cycles = detectArchitecturalCyclicFunctions(certs)
    check "alpha" in cycles
    check "beta" in cycles
