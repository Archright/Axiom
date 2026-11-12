## Unit tests for the vks_rust scope-lock extension (schema v3, additive) and
## the obligation origin/conditional-guarantee surfaces it relies on.
##
## Covers (docs/spec/rust_certified_subset.md §2):
##   (a) valid Rust targets pass — validation + lock regeneration round-trip
##   (b) a missing `specRef` fails closed (validation + writer refusal, lock
##       bytes are NOT laundered)
##   (c) a `vksRust` mismatch against the declared list fails closed
##   (d) the Nim `vksTotal` invariant is unaffected by the Rust fields
##       (separate denominators; `vksTotal == kernelTotal − exempt` holds
##       with and without a Rust declaration)
## plus the surfaces the Rust slice hangs off:
##   (e) `AssumptionOrigin` is a real identity discriminator
##   (f) `withConditionalGuarantee` reports without altering the verdict
##   (g) `buildRustScopeJson` canonical emission is key-order independent
##
## checkScopeLockConsistency itself is module-private; the checker's Rust leg
## is asserted through the same validateRustScopeSection it calls.
##
## Run: nim c -r --path:src --hints:off --warnings:off \
##        tests/unit/test_scope_lock_rust.nim

import std/[json, options, os, strutils]
import core/trusted/axiom_pragmas
import verification/obligation/obligation_types
import verification/obligation/obligation_ir
import cli/scope_cli

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  template assertEq(a, b: untyped) =
    assert a == b, "Expected " & $b & " but got " & $a

  # -----------------------------------------------------------------------
  # Fixtures
  # -----------------------------------------------------------------------

  const
    Sig1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    Commit1 = "0123456789abcdef0123456789abcdef01234567"
    Commit2 = "fedcba9876543210fedcba9876543210fedcba98"
    SpecRef = "docs/spec/rust_certified_subset.md"

  proc targetJson(commit, module, symbol, sig, specRef: string;
                  conditions: seq[string]): JsonNode =
    %*{"commit": commit, "module": module, "symbol": symbol,
       "signatureHash": sig, "specRef": specRef, "conditions": conditions}

  let validTarget1 = targetJson(Commit1, "rs/crate/src/lib.rs", "u8_add",
                                Sig1, SpecRef & "#width-precondition",
                                @["0 <= a", "0 <= b", "a + b < 256"])
  let validTarget2 = targetJson(Commit2, "rs/crate/src/lib.rs", "u8_rem",
                                Sig1, SpecRef, @["b != 0"])

  proc lockJson(targets: JsonNode; vksRust: int): JsonNode =
    result = %*{"schema_version": 3, "kernel_total": 0, "kernel_symbols": [],
                "vksTotal": 0, "kernel_exempt_symbols": [],
                "last_updated": "test", "updated_by": "test"}
    result["rust_targets"] = targets
    result["vksRust"] = %vksRust

  proc legacyLockJson(): JsonNode =
    %*{"schema_version": 3, "kernel_total": 0, "kernel_symbols": [],
       "vksTotal": 0, "kernel_exempt_symbols": [],
       "last_updated": "test", "updated_by": "test"}

  proc tempRoot(tag: string): string =
    let d = getTempDir() / "axiom_scope_lock_rust_test_" & tag & "_" &
            $getCurrentProcessId()
    createDir(d / "data")
    d

  proc writeLock(root: string; node: JsonNode) =
    writeFile(root / "data" / "verification_scope.lock", $node)

  proc readLock(root: string): JsonNode =
    parseFile(root / "data" / "verification_scope.lock")

  proc writeExempt(root: string) =
    ## One exempt symbol of the two seeded registry entries → vksTotal = 2−1 = 1.
    writeFile(root / "data" / "kernel_exempt_symbols.json",
              "[\"src/test_mod_scope_rust.nim::rust_test_kernel_b\"]")

  # Seed the runtime kernel registry: 2 kernel symbols, 1 exempt.
  registerAxiom("rust_test_kernel_a", "ir-a", "smt-a", "lean-a",
                "src/test_mod_scope_rust.nim")
  registerAxiom("rust_test_kernel_b", "ir-b", "smt-b", "lean-b",
                "src/test_mod_scope_rust.nim")

  # -----------------------------------------------------------------------
  # (a) valid Rust targets pass
  # -----------------------------------------------------------------------
  echo "=== (a) valid Rust targets pass ==="

  check "validateRustScopeSection accepts two consistent targets":
    let v = validateRustScopeSection(lockJson(%[validTarget1, validTarget2], 2))
    assert v.checked, "rust section present must be checked"
    assert v.ok, "expected ok, reason: " & v.reason
    assertEq(v.computedVksRust, 2)

  check "writer regenerates a lock preserving a valid Rust declaration":
    let root = tempRoot("valid")
    writeLock(root, lockJson(%[validTarget1, validTarget2], 2))
    let (ok, _) = writeScopeLockFromRegistry(root)
    assert ok, "writer must accept a valid Rust declaration"
    let regenerated = readLock(root)
    assertEq(regenerated["vksRust"].getInt(), 2)
    assertEq(regenerated["rust_targets"].len, 2)
    assertEq(regenerated["rust_targets"][0]["symbol"].getStr(), "u8_add")
    assertEq(regenerated["rust_targets"][0]["specRef"].getStr(),
             SpecRef & "#width-precondition")

  check "writer is idempotent over a valid Rust declaration":
    let root = tempRoot("idempotent")
    writeLock(root, lockJson(%[validTarget1, validTarget2], 2))
    discard writeScopeLockFromRegistry(root)
    let bytes = readFile(root / "data" / "verification_scope.lock")
    let (ok2, _) = writeScopeLockFromRegistry(root)
    assert ok2
    assertEq(readFile(root / "data" / "verification_scope.lock"), bytes)

  # -----------------------------------------------------------------------
  # (b) missing specRef fails closed
  # -----------------------------------------------------------------------
  echo "=== (b) missing specRef fails closed ==="

  check "validateRustScopeSection rejects a missing specRef":
    let bad = targetJson(Commit1, "rs/crate/src/lib.rs", "u8_add", Sig1, "",
                         @["a + b < 256"])
    bad.delete("specRef")
    let v = validateRustScopeSection(lockJson(%[bad], 1))
    assert v.checked
    assert (not v.ok), "missing specRef must fail"
    assert "specRef" in v.reason, "reason must name specRef: " & v.reason

  check "writer refuses to regenerate over a missing specRef and keeps bytes":
    let root = tempRoot("nospecref")
    let bad = targetJson(Commit1, "rs/crate/src/lib.rs", "u8_add", Sig1, "",
                         @["a + b < 256"])
    bad.delete("specRef")
    let badLock = lockJson(%[bad], 1)
    writeLock(root, badLock)
    let badBytes = readFile(root / "data" / "verification_scope.lock")
    let (ok, _) = writeScopeLockFromRegistry(root)
    assert (not ok), "writer must refuse an invalid Rust declaration"
    assertEq(readFile(root / "data" / "verification_scope.lock"), badBytes)

  # -----------------------------------------------------------------------
  # (c) vksRust mismatch against the declared list fails closed
  # -----------------------------------------------------------------------
  echo "=== (c) vksRust mismatch fails closed ==="

  check "declared vksRust=3 with 2 targets fails closed":
    let v = validateRustScopeSection(lockJson(%[validTarget1, validTarget2], 3))
    assert v.checked
    assert (not v.ok), "mismatch must fail"
    assert "vksRust mismatch" in v.reason, "reason: " & v.reason
    assertEq(v.computedVksRust, 2)

  check "writer refuses a vksRust mismatch and keeps bytes":
    let root = tempRoot("mismatch")
    let badLock = lockJson(%[validTarget1, validTarget2], 5)
    writeLock(root, badLock)
    let badBytes = readFile(root / "data" / "verification_scope.lock")
    let (ok, _) = writeScopeLockFromRegistry(root)
    assert (not ok), "writer must refuse a vksRust mismatch"
    assertEq(readFile(root / "data" / "verification_scope.lock"), badBytes)

  check "partial declaration (targets without vksRust) fails closed":
    var partial = lockJson(%[validTarget1], 1)
    partial.delete("vksRust")
    let v = validateRustScopeSection(partial)
    assert v.checked and (not v.ok)

  check "duplicate (module, symbol) target fails closed":
    let dup = validTarget1.copy()
    let v = validateRustScopeSection(lockJson(%[validTarget1, dup], 2))
    assert v.checked and (not v.ok)
    assert "duplicate" in v.reason

  check "legacy lock without rust fields is Nim-only (checked=false, ok)":
    let v = validateRustScopeSection(legacyLockJson())
    assert (not v.checked)
    assert v.ok
    assertEq(v.computedVksRust, 0)

  # -----------------------------------------------------------------------
  # (d) Nim vksTotal is unaffected by the Rust fields
  # -----------------------------------------------------------------------
  echo "=== (d) Nim vksTotal unaffected ==="

  check "vksTotal == kernelTotal − exempt with AND without a Rust declaration":
    # Legacy lock: no rust fields at all.
    let legacyRoot = tempRoot("legacy")
    writeExempt(legacyRoot)
    writeLock(legacyRoot, legacyLockJson())
    let legacyOut = parseJson(buildScopeLockJson(legacyRoot, readLock(legacyRoot)))
    # Rust lock: two declared targets, same Nim registry + exemptions.
    let rustRoot = tempRoot("rustdenom")
    writeExempt(rustRoot)
    writeLock(rustRoot, lockJson(%[validTarget1, validTarget2], 2))
    let rustOut = parseJson(buildScopeLockJson(rustRoot, readLock(rustRoot)))
    # Nim denominator (2 kernel − 1 exempt = 1) identical in both.
    assertEq(legacyOut["vksTotal"].getInt(), 1)
    assertEq(rustOut["vksTotal"].getInt(), 1)
    assertEq(legacyOut["kernel_total"].getInt(), 2)
    assertEq(rustOut["kernel_total"].getInt(), 2)
    # Rust denominator is separate: NOT folded into vksTotal.
    assertEq(rustOut["vksRust"].getInt(), 2)
    assert rustOut["vksTotal"].getInt() != 3, "vks_rust must not join the Nim VKS"
    # Legacy lock inherits the zero Rust declaration on regeneration.
    assertEq(legacyOut["rust_targets"].len, 0)
    assertEq(legacyOut["vksRust"].getInt(), 0)

  check "valid rust section passes the checker's Rust leg":
    let root = tempRoot("consistent")
    writeExempt(root)
    writeLock(root, lockJson(%[validTarget1], 1))
    let v = validateRustScopeSection(readLock(root))
    assert v.checked and v.ok, "reason: " & v.reason

  # -----------------------------------------------------------------------
  # (e) AssumptionOrigin — real identity discriminator
  # -----------------------------------------------------------------------
  echo "=== (e) AssumptionOrigin discriminator ==="

  check "same tuple, different origin → different obligation id":
    let idUser = computeObligationId("m::f", okSafetyDiv, "", "p", "r",
                                     aoUserDeclared)
    let idType = computeObligationId("m::f", okSafetyDiv, "", "p", "r",
                                     aoTypeDerived)
    let idCaller = computeObligationId("m::f", okSafetyDiv, "", "p", "r",
                                       aoCallerObligation)
    assert idUser != idType
    assert idUser != idCaller
    assert idType != idCaller

  check "same tuple, same origin → same obligation id (determinism)":
    let id1 = computeObligationId("m::f", okSafetyDiv, "", "p", "r",
                                  aoCallerObligation)
    let id2 = computeObligationId("m::f", okSafetyDiv, "", "p", "r",
                                  aoCallerObligation)
    assertEq(id1, id2)

  check "makeVerificationObligation folds origin into identity":
    let obl = makeVerificationObligation(okContractPre, "rs::u8_add",
      "0 <= a|0 <= b", "rust-u8-range", "rust-subject-v1", nil,
      aoTypeDerived)
    assertEq(obl.assumptionOrigin.ord, aoTypeDerived.ord)
    assertEq(obl.id, computeObligationId(obl.subject, obl.kind,
      obl.assumptions, obl.predicate, obl.derivationRule, obl.assumptionOrigin))
    # The default producer keeps the legacy channel value.
    let legacy = makeVerificationObligation(okSafetyDiv, "foo", "", "rule",
                                           "src", nil)
    assertEq(legacy.assumptionOrigin.ord, aoUserDeclared.ord)

  # -----------------------------------------------------------------------
  # (f) conditional guarantee reporting surface
  # -----------------------------------------------------------------------
  echo "=== (f) conditional guarantee ==="

  check "withConditionalGuarantee reports assumptions without altering verdict":
    let outcome = ObligationOutcome(phase: ppTerminal,
      terminal: some(ptRefuted), detail: "overflow reachable")
    let conditional = withConditionalGuarantee(outcome, @["a + b < 256"])
    assert conditional.terminal.get == ptRefuted, "verdict must be carried through"
    assert conditional.phase == ppTerminal
    assert conditional.detail == "overflow reachable"
    assert conditional.conditionalGuarantee
    assert conditional.undischargedAssumptions == @["a + b < 256"]

  check "empty assumption list is not a conditional guarantee":
    let outcome = ObligationOutcome(phase: ppTerminal,
      terminal: some(ptProved), detail: "proved")
    let marked = withConditionalGuarantee(outcome, @[])
    assert (not marked.conditionalGuarantee)
    assert marked.undischargedAssumptions.len == 0
    assert marked.terminal.get == ptProved

  check "ProofTerminal verdict space is unchanged (no conditional enum)":
    assert ProofTerminal.high.ord == 6, "ProofTerminal must keep exactly 7 values"

  # -----------------------------------------------------------------------
  # (g) canonical emission — key-order independence
  # -----------------------------------------------------------------------
  echo "=== (g) buildRustScopeJson canonical emission ==="

  check "same targets in different key order emit identical bytes":
    let ordered = %*[{"commit": Commit1, "module": "rs/lib.rs",
      "symbol": "u8_add", "signatureHash": Sig1, "specRef": "docs/spec",
      "conditions": ["a + b < 256"]}]
    let shuffled = %*[{"conditions": ["a + b < 256"], "specRef": "docs/spec",
      "signatureHash": Sig1, "symbol": "u8_add", "module": "rs/lib.rs",
      "commit": Commit1}]
    let bytes1 = buildRustScopeJson(ordered, 1)
    let bytes2 = buildRustScopeJson(shuffled, 1)
    assertEq(bytes1, bytes2)
    assert "\"rust_targets\":[" in bytes1
    assert "\"vksRust\":1" in bytes1
    # field order is canonical: commit first, conditions last
    assert bytes1.find("{\"commit\":") < bytes1.find("\"conditions\":[")

  # -----------------------------------------------------------------------
  # Summary
  # -----------------------------------------------------------------------
  echo ""
  echo "=== Results ==="
  echo "  Passed: " & $passed
  echo "  Failed: " & $failed
  if failed > 0:
    echo "  FAILED"
    quit(1)
  else:
    echo "  ALL PASSED"

when isMainModule:
  main()
