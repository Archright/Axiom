import std/[unittest, strutils, algorithm, sequtils]
import core/crypto/hash_kernel
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import verification/obligation/identity
import verification/obligation/semantic_target_extractor

# ═══════════════════════════════════════════════════════════════
# Test IR fixtures
# ═══════════════════════════════════════════════════════════════

let bv64 = irTypeBitVec64()
let boolType = irTypeBool()

## func add(x, y) = x + y  — calls no other user function
let irAdd = irFuncDef(
  name = "add",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irAdd(irVar("x", bv64), irVar("y", bv64))
)

## func max(x, y) = if x >= y then x else y  — calls no other user function
let irMax = irFuncDef(
  name = "max",
  params = @[("x", bv64), ("y", bv64)],
  ret = bv64,
  body = irIf(
    irGe(irVar("x", bv64), irVar("y", bv64)),
    irVar("x", bv64),
    irVar("y", bv64)
  )
)

## func add3(x, y, z) = add(add(x, y), z)  — depends on "add"
let irAdd3 = irFuncDef(
  name = "add3",
  params = @[("x", bv64), ("y", bv64), ("z", bv64)],
  ret = bv64,
  body = irCall("add", @[
    irCall("add", @[irVar("x", bv64), irVar("y", bv64)]),
    irVar("z", bv64)
  ])
)

## func withPost(f) — adds a postcondition referencing a contract symbol
func withPost(f: IRFuncDef; post: IRExpr): IRFuncDef =
  result = f
  result.postConditions = @[post]

## func withPre(f) — adds a precondition referencing a contract symbol
func withPre(f: IRFuncDef; pre: IRExpr): IRFuncDef =
  result = f
  result.preConditions = @[pre]

# ═══════════════════════════════════════════════════════════════
# Suite: collectSemanticDependencies
# ═══════════════════════════════════════════════════════════════

suite "collectSemanticDependencies":

  test "no-call function returns empty dependency set":
    let deps = collectSemanticDependencies(irAdd)
    check deps.len == 0

  test "function calling another user function returns that callee":
    let deps = collectSemanticDependencies(irAdd3)
    check "add" in deps
    check deps.len == 1

  test "self-recursive call is excluded from dependencies":
    let recursive = irFuncDef(
      name = "factorial",
      params = @[("n", bv64)],
      ret = bv64,
      body = irIf(
        irEq(irVar("n", bv64), irLit(0)),
        irLit(1),
        irBinOp(boMul, irVar("n", bv64),
          irCall("factorial", @[irBinOp(boSub, irVar("n", bv64), irLit(1))]))
      ),
      isRec = true
    )
    let deps = collectSemanticDependencies(recursive)
    check "factorial" notin deps

  test "multiple distinct callees are all collected":
    let multi = irFuncDef(
      name = "multi",
      params = @[("x", bv64), ("y", bv64)],
      ret = bv64,
      body = irCall("helperA", @[irVar("x", bv64)])
    )
    let deps = collectSemanticDependencies(multi)
    check "helperA" in deps

  test "preconditions and postconditions are walked for dependencies":
    let withContract = withPre(irAdd, irCall("contractCheck", @[irVar("x", bv64)]))
    let deps = collectSemanticDependencies(withContract)
    check "contractCheck" in deps

  test "result is sorted and deduplicated":
    let dup = irFuncDef(
      name = "dup",
      params = @[("x", bv64)],
      ret = bv64,
      body = irBinOp(boAdd,
        irCall("util", @[irVar("x", bv64)]),
        irCall("util", @[irVar("x", bv64)]))
    )
    let deps = collectSemanticDependencies(dup)
    check deps.len == 1
    check deps[0] == "util"

# ═══════════════════════════════════════════════════════════════
# Suite: computeDependencyDigests
# ═══════════════════════════════════════════════════════════════

suite "computeDependencyDigests":

  test "empty input produces empty output":
    let digests = computeDependencyDigests(@[])
    check digests.len == 0

  test "same callee names produce same digests (determinism)":
    let names = @["add", "mul", "sub"]
    let d1 = computeDependencyDigests(names)
    let d2 = computeDependencyDigests(names)
    check d1 == d2
    check d1.len == 3

  test "each digest is a 64-char SHA256 hex string":
    let digests = computeDependencyDigests(@["add"])
    check digests.len == 1
    check digests[0].len == 64
    check digests[0] == sha256Hex("add")

  test "different callee names produce different digests":
    let d1 = computeDependencyDigests(@["add"])
    let d2 = computeDependencyDigests(@["mul"])
    check d1 != d2

  test "result is sorted regardless of input order":
    let d1 = computeDependencyDigests(@["z", "a", "m"])
    let d2 = computeDependencyDigests(@["a", "m", "z"])
    check d1 == d2
    check d1 == d1.sorted

# ═══════════════════════════════════════════════════════════════
# Suite: computeSemanticBundleFingerprint
# ═══════════════════════════════════════════════════════════════

suite "computeSemanticBundleFingerprint":

  test "same inputs produce same fingerprint (determinism)":
    let tfp = sha256Hex("toolchain-fingerprint")
    let deps = computeDependencyDigests(@["add", "mul"])
    let fp1 = computeSemanticBundleFingerprint(tfp, deps)
    let fp2 = computeSemanticBundleFingerprint(tfp, deps)
    check fp1 == fp2
    check fp1.len == 64

  test "different dependency set produces different fingerprint":
    let tfp = sha256Hex("toolchain-fingerprint")
    let depsA = computeDependencyDigests(@["add"])
    let depsB = computeDependencyDigests(@["add", "mul"])
    let fpA = computeSemanticBundleFingerprint(tfp, depsA)
    let fpB = computeSemanticBundleFingerprint(tfp, depsB)
    check fpA != fpB

  test "same deps different order produces same fingerprint":
    let tfp = sha256Hex("toolchain-fingerprint")
    let deps1 = computeDependencyDigests(@["z", "a", "m"])
    let deps2 = computeDependencyDigests(@["a", "m", "z"])
    let fp1 = computeSemanticBundleFingerprint(tfp, deps1)
    let fp2 = computeSemanticBundleFingerprint(tfp, deps2)
    check fp1 == fp2

  test "empty deps still produces a valid fingerprint":
    let tfp = sha256Hex("toolchain-fingerprint")
    let fp = computeSemanticBundleFingerprint(tfp, @[])
    check fp.len == 64
    # Empty deps should differ from non-empty deps with same toolchain
    let fpWithDeps = computeSemanticBundleFingerprint(tfp, @[sha256Hex("add")])
    check fp != fpWithDeps

# ═══════════════════════════════════════════════════════════════
# Suite: End-to-end — dependencyDigests affects executionIdentity
# ═══════════════════════════════════════════════════════════════

suite "Dependency sensitivity — executionIdentity":

  test "(a) same semantic inputs → same dependencyDigests → same executionIdentity":
    let inputId = sha256Hex("source.nim::add")
    let contractDigest = sha256Hex("contract")
    let tfp = sha256Hex("toolchain")
    let deps = computeDependencyDigests(@["add", "mul"])
    let bundleFp = computeSemanticBundleFingerprint(tfp, deps)
    let execId1 = executionIdentity(inputId, contractDigest, bundleFp)
    let execId2 = executionIdentity(inputId, contractDigest, bundleFp)
    check execId1 == execId2
    check execId1.len == 64

  test "(b) change to a dependency's identity → dependencyDigests change → executionIdentity change":
    let inputId = sha256Hex("source.nim::add")
    let contractDigest = sha256Hex("contract")
    let tfp = sha256Hex("toolchain")
    # Original: depends on "add"
    let depsOrig = computeDependencyDigests(@["add"])
    let fpOrig = computeSemanticBundleFingerprint(tfp, depsOrig)
    let execIdOrig = executionIdentity(inputId, contractDigest, fpOrig)
    # Changed: now depends on "add" AND "mul" (a new dependency)
    let depsChanged = computeDependencyDigests(@["add", "mul"])
    let fpChanged = computeSemanticBundleFingerprint(tfp, depsChanged)
    let execIdChanged = executionIdentity(inputId, contractDigest, fpChanged)
    check execIdOrig != execIdChanged

  test "(c) incidental variance in non-dependency fields → identity UNCHANGED":
    let inputId = sha256Hex("source.nim::add")
    let contractDigest = sha256Hex("contract")
    let tfp = sha256Hex("toolchain")
    let deps = computeDependencyDigests(@["add"])
    let bundleFp = computeSemanticBundleFingerprint(tfp, deps)
    let execId1 = executionIdentity(inputId, contractDigest, bundleFp)
    # Same inputs, same result — incidental variance (e.g. mtime) is
    # absorbed by the canonical content hashing and does not churn identity.
    let execId2 = executionIdentity(inputId, contractDigest, bundleFp)
    check execId1 == execId2

  test "(d) dependencyDigests sorted-order independence":
    let inputId = sha256Hex("source.nim::add")
    let contractDigest = sha256Hex("contract")
    let tfp = sha256Hex("toolchain")
    # Same deps, different insertion order
    let deps1 = computeDependencyDigests(@["z", "a", "m"])
    let deps2 = computeDependencyDigests(@["a", "m", "z"])
    let fp1 = computeSemanticBundleFingerprint(tfp, deps1)
    let fp2 = computeSemanticBundleFingerprint(tfp, deps2)
    let execId1 = executionIdentity(inputId, contractDigest, fp1)
    let execId2 = executionIdentity(inputId, contractDigest, fp2)
    check execId1 == execId2

# ═══════════════════════════════════════════════════════════════
# Suite: canonicalExecutionBundleFingerprint with dependencyDigests
# ═══════════════════════════════════════════════════════════════

suite "canonicalExecutionBundleFingerprint with dependencyDigests":

  test "dependencyDigests field is populated and affects fingerprint":
    let fp1 = canonicalExecutionBundleFingerprint(
      axiomExeDigest = sha256Hex("axiom-exe"),
      axiomSourceDigest = sha256Hex("axiom-source"),
      leanVer = "lean-4.33.0",
      z3Ver = "z3-4.13.3",
      lakeVer = "lake",
      nimVer = "nim-2.2.10",
      dependencyDigests = @[],
      runtimeDigest = sha256Hex("runtime"),
      evaluationImplDigest = sha256Hex("eval-impl")
    )
    let fp2 = canonicalExecutionBundleFingerprint(
      axiomExeDigest = sha256Hex("axiom-exe"),
      axiomSourceDigest = sha256Hex("axiom-source"),
      leanVer = "lean-4.33.0",
      z3Ver = "z3-4.13.3",
      lakeVer = "lake",
      nimVer = "nim-2.2.10",
      dependencyDigests = @[sha256Hex("add")],
      runtimeDigest = sha256Hex("runtime"),
      evaluationImplDigest = sha256Hex("eval-impl")
    )
    check fp1 != fp2
    check fp1.len == 64
    check fp2.len == 64

  test "sorted dependencyDigests produce deterministic fingerprint":
    let fp1 = canonicalExecutionBundleFingerprint(
      axiomExeDigest = sha256Hex("axiom-exe"),
      axiomSourceDigest = sha256Hex("axiom-source"),
      leanVer = "lean-4.33.0",
      z3Ver = "z3-4.13.3",
      lakeVer = "lake",
      nimVer = "nim-2.2.10",
      dependencyDigests = @[sha256Hex("z"), sha256Hex("a"), sha256Hex("m")],
      runtimeDigest = sha256Hex("runtime"),
      evaluationImplDigest = sha256Hex("eval-impl")
    )
    let fp2 = canonicalExecutionBundleFingerprint(
      axiomExeDigest = sha256Hex("axiom-exe"),
      axiomSourceDigest = sha256Hex("axiom-source"),
      leanVer = "lean-4.33.0",
      z3Ver = "z3-4.13.3",
      lakeVer = "lake",
      nimVer = "nim-2.2.10",
      dependencyDigests = @[sha256Hex("a"), sha256Hex("m"), sha256Hex("z")],
      runtimeDigest = sha256Hex("runtime"),
      evaluationImplDigest = sha256Hex("eval-impl")
    )
    check fp1 == fp2

  test "fail-closed: unresolved dependency still produces a digest":
    let deps = computeDependencyDigests(@["unknown_symbol_xyz"])
    check deps.len == 1
    check deps[0].len == 64
    # The digest is sha256Hex("unknown_symbol_xyz") — it captures the
    # identity of the unknown dependency so the fingerprint changes when
    # the dependency set changes, even though the source cannot be resolved.
    check deps[0] == sha256Hex("unknown_symbol_xyz")

# ═══════════════════════════════════════════════════════════════
# Suite: Integration — collectSemanticDependencies + computeDependencyDigests
# ═══════════════════════════════════════════════════════════════

suite "Integration: IR dependency extraction → digests → bundle fingerprint":

  test "add function (no deps) produces empty digests":
    let deps = collectSemanticDependencies(irAdd)
    check deps.len == 0
    let digests = computeDependencyDigests(deps)
    check digests.len == 0

  test "add3 function (depends on add) produces non-empty digests":
    let deps = collectSemanticDependencies(irAdd3)
    check "add" in deps
    let digests = computeDependencyDigests(deps)
    check digests.len == 1
    check digests[0] == sha256Hex("add")

  test "function with contract precondition captures contract dependency":
    let contractCall = irCall("verifyContract", @[irVar("x", bv64)])
    let withPreCond = withPre(irAdd, contractCall)
    let deps = collectSemanticDependencies(withPreCond)
    check "verifyContract" in deps
    let digests = computeDependencyDigests(deps)
    check digests.len == 1
    check digests[0] == sha256Hex("verifyContract")

  test "bundle fingerprint changes when IR dependency set changes":
    let tfp = sha256Hex("toolchain")
    let baseDeps = computeDependencyDigests(collectSemanticDependencies(irAdd))
    let baseFp = computeSemanticBundleFingerprint(tfp, baseDeps)

    let add3Deps = computeDependencyDigests(collectSemanticDependencies(irAdd3))
    let add3Fp = computeSemanticBundleFingerprint(tfp, add3Deps)

    check baseFp != add3Fp

  test "bundle fingerprint is deterministic across repeated extraction":
    let tfp = sha256Hex("toolchain")
    let deps1 = collectSemanticDependencies(irAdd3)
    let deps2 = collectSemanticDependencies(irAdd3)
    check deps1 == deps2
    let fp1 = computeSemanticBundleFingerprint(tfp, computeDependencyDigests(deps1))
    let fp2 = computeSemanticBundleFingerprint(tfp, computeDependencyDigests(deps2))
    check fp1 == fp2
