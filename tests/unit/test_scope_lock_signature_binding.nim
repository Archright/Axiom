## Unit tests for the vks_rust `signatureHash` BINDING (issue #223).
##
## The defect these tests close: `validateRustScopeSection` checked only that
## the field is 64-char lowercase hex, so ANY well-formed string satisfied the
## scope declaration. A digest that is never recomputed from the signature it
## names certifies nothing; a consumer that reads the lock as a trust basis got
## a guarantee that did not exist.
##
## The binding contract asserted here:
##   (a) a tampered but well-formed 64-hex hash is REJECTED (digest mismatch),
##       including the strongest form — another REAL signature digest of the
##       same module, well-formed and plausible, bound to the wrong symbol;
##   (b) the signature text changes while the declared hash stays → REJECTED;
##   (c) an unmodified declaration is ACCEPTED — on a fixture AND on the
##       committed data/verification_scope.lock (6/6 targets bound);
##   (d) a missing field and a malformed field are DISTINCT rejection reasons,
##       each distinct from a mismatch, and neither is coerced into PASS;
##   (e) an unresolvable module and an absent signature line are distinct
##       fail-closed reasons (never a silent pass-through);
##   (f) the writer (`buildScopeLockJson`) refuses to regenerate over an unbound
##       declaration — regeneration never launders the identity.
##
## The expected digests below are LITERAL sha256 values (verified with
## `sha256sum`), not values produced by the function under test: the
## canonicalisation is pinned to an external reference, so a change in either
## direction fails here.
##
## Run: nim c -r --path:src --hints:off --warnings:off \
##        tests/unit/test_scope_lock_signature_binding.nim

import std/[json, os, strutils]
import core/trusted/axiom_pragmas
import verification/rust_input_contract

const
  # sha256("pub fn add_u8(a: u8, b: u8) -> u8")
  AddHash = "fb6713097920adfe83660250aa8afc51ed6733b23ae6e4bb966b568e814f6c2d"
  # sha256("pub fn add_u8_mutant(a: u8, b: u8) -> u8")
  MutantHash = "4791bc600ce8e0aeb241bbe7546e0d34e4a2af9e34380b9f0c9b0a248b899d0b"
  # well-formed, plausible, and the digest of NOTHING in the fixture module
  ArbitraryHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  ModulePath = "crate/src/lib.rs"

let LibRs = """pub fn add_u8(a: u8, b: u8) -> u8 {
    a + b
}

pub fn add_u8_mutant(a: u8, b: u8) -> u8 {
    a + b + 1
}
"""

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

  # ── fixtures ────────────────────────────────────────────────────────────
  proc tempRoot(tag: string): string =
    let d = getTempDir() / "axiom_sig_binding_" & tag & "_" &
            $getCurrentProcessId()
    createDir(d / "crate" / "src")
    d

  proc writeModule(root, text: string) =
    writeFile(root / ModulePath, text)

  proc targetObj(hash: string): JsonNode =
    %*{"commit": "0123456789abcdef0123456789abcdef01234567",
       "module": ModulePath, "symbol": "axiom_probe::add_u8",
       "signatureHash": hash,
       "specRef": "crate/axiom.specs.json#axiom_probe::add_u8",
       "conditions": ["0 <= a"]}

  proc lockWith(hash: string): JsonNode =
    result = %*{"schema_version": 3, "vksRust": 1}
    result["rust_targets"] = %[targetObj(hash)]

  proc repoRoot(): string =
    ## The committed lock and the fixture crates live in the repo tree; the
    ## committed-lock assertion below is only meaningful against it. Absence is
    ## a hard failure (cwd is the repo root under `make test-fast`), never a
    ## silent skip.
    var d = getCurrentDir()
    while true:
      if fileExists(d / "data" / "verification_scope.lock") and
         dirExists(d / "tests" / "fixtures" / "rust"):
        return d
      let parent = parentDir(d)
      if parent == d or parent.len == 0:
        raise newException(IOError,
          "repo root (data/verification_scope.lock + tests/fixtures/rust) not " &
          "found above " & getCurrentDir())
      d = parent

  # ── (0) the canonicalisation itself, pinned to an external sha256 ───────
  echo "=== (0) canonical signature serialisation ==="

  check "canonical line drops indentation, the body brace and surrounding space":
    assert canonicalRustSignatureLine("pub fn add_u8(a: u8, b: u8) -> u8 {") ==
      "pub fn add_u8(a: u8, b: u8) -> u8"
    assert canonicalRustSignatureLine("    pub fn add_u8(a: u8, b: u8) -> u8  ") ==
      "pub fn add_u8(a: u8, b: u8) -> u8"

  check "digest equals the LITERAL sha256 of the canonical line":
    assert rustSignatureDigest("pub fn add_u8(a: u8, b: u8) -> u8 {") == AddHash
    assert rustSignatureDigest("pub fn add_u8_mutant(a: u8, b: u8) -> u8 {") ==
      MutantHash

  check "signature line lookup is name-exact (add_u8 never binds add_u8_mutant)":
    assert findRustSignatureLine(LibRs, "add_u8") ==
      "pub fn add_u8(a: u8, b: u8) -> u8 {"
    assert findRustSignatureLine(LibRs, "add_u8_mutant") ==
      "pub fn add_u8_mutant(a: u8, b: u8) -> u8 {"
    assert findRustSignatureLine(LibRs, "add_u") == ""

  # ── (c) unmodified declaration is accepted ─────────────────────────────
  echo "=== (c) unmodified declaration accepted ==="

  check "a declaration whose hash matches its module is bound (accepted)":
    let root = tempRoot("ok")
    writeModule(root, LibRs)
    let b = verifyRustSignatureBinding([root], lockWith(AddHash))
    assert b.checked, "a declaration with targets must be checked"
    assert b.ok, "expected ok, reason: " & b.reason
    assert b.boundTargets == 1, "expected 1 bound target, got " & $b.boundTargets

  check "legacy lock without rust_targets is unchecked (nothing declared)":
    let b = verifyRustSignatureBinding([tempRoot("legacy")],
      %*{"schema_version": 3, "vksTotal": 0})
    assert (not b.checked) and b.ok
    assert b.boundTargets == 0

  # ── (a) tampered 64-hex hash is rejected ───────────────────────────────
  echo "=== (a) tampered 64-hex hash rejected ==="

  check "an arbitrary well-formed 64-hex hash is rejected (mismatch)":
    let root = tempRoot("arbitrary")
    writeModule(root, LibRs)
    let b = verifyRustSignatureBinding([root], lockWith(ArbitraryHash))
    assert b.checked and (not b.ok), "arbitrary 64-hex must not pass"
    assert "signatureHash mismatch" in b.reason, "reason: " & b.reason
    assert ArbitraryHash in b.reason, "reason must name the declared value"
    assert AddHash in b.reason, "reason must name the recomputed value"

  check "a REAL digest of the same module bound to the wrong symbol is rejected":
    let root = tempRoot("wrongpair")
    writeModule(root, LibRs)
    # MutantHash is the sha256 of add_u8_mutant's line: well-formed, real, and
    # not this symbol's digest — the class a shape check cannot distinguish.
    let b = verifyRustSignatureBinding([root], lockWith(MutantHash))
    assert b.checked and (not b.ok)
    assert "signatureHash mismatch" in b.reason, "reason: " & b.reason

  # ── (b) signature text changed, hash old → rejected ────────────────────
  echo "=== (b) changed signature text rejected ==="

  check "signature text changed while the declared hash stays is rejected":
    let root = tempRoot("changedtext")
    writeModule(root, LibRs)
    assert verifyRustSignatureBinding([root], lockWith(AddHash)).ok,
      "precondition: the original text must bind"
    writeModule(root, LibRs.replace(
      "pub fn add_u8(a: u8, b: u8) -> u8 {",
      "pub fn add_u8(a: u8, b: u8, c: u8) -> u8 {"))
    let b = verifyRustSignatureBinding([root], lockWith(AddHash))
    assert b.checked and (not b.ok), "changed signature text must not pass"
    assert "signatureHash mismatch" in b.reason, "reason: " & b.reason

  check "body-only edit keeps the binding (the declaration line is the identity)":
    let root = tempRoot("bodyedit")
    writeModule(root, LibRs)
    writeModule(root, LibRs.replace("    a + b\n", "    a + b + 0\n"))
    let b = verifyRustSignatureBinding([root], lockWith(AddHash))
    assert b.ok, "a body edit must not move the signature identity: " & b.reason

  # ── (d) missing vs malformed vs mismatch are distinct reasons ──────────
  echo "=== (d) distinct rejection classes ==="

  check "missing signatureHash is rejected with its own reason":
    let root = tempRoot("missing")
    writeModule(root, LibRs)
    var l = lockWith(AddHash)
    l["rust_targets"][0].delete("signatureHash")
    let b = verifyRustSignatureBinding([root], l)
    assert b.checked and (not b.ok), "a missing field must not pass"
    assert "signatureHash missing" in b.reason, "reason: " & b.reason

  check "malformed signatureHash is rejected with its own reason":
    let root = tempRoot("malformed")
    writeModule(root, LibRs)
    for bad in ["abc", "A".repeat(64), AddHash & "0"]:
      let b = verifyRustSignatureBinding([root], lockWith(bad))
      assert b.checked and (not b.ok), "malformed '" & bad & "' must not pass"
      assert "signatureHash malformed" in b.reason, "reason: " & b.reason

  check "missing, malformed and mismatch are three DIFFERENT reasons":
    let root = tempRoot("classes")
    writeModule(root, LibRs)
    var missing = lockWith(AddHash)
    missing["rust_targets"][0].delete("signatureHash")
    let rMissing = verifyRustSignatureBinding([root], missing).reason
    let rMalformed = verifyRustSignatureBinding([root], lockWith("zz")).reason
    let rMismatch = verifyRustSignatureBinding([root], lockWith(ArbitraryHash)).reason
    assert rMissing.len > 0 and rMalformed.len > 0 and rMismatch.len > 0
    assert rMissing != rMalformed
    assert rMissing != rMismatch
    assert rMalformed != rMismatch

  # ── (e) unresolvable module / absent signature line ────────────────────
  echo "=== (e) unresolvable module and absent signature line ==="

  check "a module that resolves under no root is rejected":
    let root = tempRoot("nomodule")
    let b = verifyRustSignatureBinding([root], lockWith(AddHash))
    assert b.checked and (not b.ok), "an unresolvable module must not pass"
    assert "module unresolvable" in b.reason, "reason: " & b.reason

  check "a module that declares no such function is rejected":
    let root = tempRoot("nofn")
    writeModule(root, "pub fn other(a: u8) -> u8 {\n    a\n}\n")
    let b = verifyRustSignatureBinding([root], lockWith(AddHash))
    assert b.checked and (not b.ok), "an absent signature line must not pass"
    assert "signature line not found" in b.reason, "reason: " & b.reason

  # ── (f) the writer refuses an unbound declaration ──────────────────────
  echo "=== (f) writer refuses an unbound declaration ==="

  check "buildScopeLockJson emits for a bound declaration and refuses a tampered one":
    let root = tempRoot("writer")
    writeModule(root, LibRs)
    let loadedGood = loadRustTargetModuleSources([root], lockWith(AddHash))
    let good = buildScopeLockJson(root, lockWith(AddHash), loadedGood.sources)
    assert good.len > 0, "a bound declaration must regenerate"
    assert "\"signatureHash\":\"" & AddHash & "\"" in good,
      "the declared (verified) digest is carried verbatim"
    let loadedBad = loadRustTargetModuleSources([root], lockWith(ArbitraryHash))
    let bad = buildScopeLockJson(root, lockWith(ArbitraryHash), loadedBad.sources)
    assert bad.len == 0, "an unbound declaration must be refused"

  # ── (g) the committed lock binds ───────────────────────────────────────
  echo "=== (g) the committed data/verification_scope.lock binds ==="

  check "every committed rust_target binds to its fixture source":
    let root = repoRoot()
    let lock = parseFile(root / "data" / "verification_scope.lock")
    let b = verifyRustSignatureBinding([root], lock)
    assert b.checked and b.ok, "committed lock must bind: " & b.reason
    assert b.boundTargets == lock["rust_targets"].len
    assert b.boundTargets == 6, "expected the 6 declared targets, got " &
      $b.boundTargets

  check "tampering the committed lock's u64_add hash to a sibling's real digest is rejected":
    let root = repoRoot()
    var lock = parseFile(root / "data" / "verification_scope.lock")
    var idx = -1
    for i in 0 ..< lock["rust_targets"].len:
      if lock["rust_targets"][i]["symbol"].getStr() == "axiom_u64_probe::u64_add":
        idx = i
    assert idx >= 0, "committed lock must declare axiom_u64_probe::u64_add"
    lock["rust_targets"][idx]["signatureHash"] =
      %lock["rust_targets"][idx + 1]["signatureHash"].getStr()
    let b = verifyRustSignatureBinding([root], lock)
    assert b.checked and (not b.ok), "a tampered committed lock must not pass"
    assert "signatureHash mismatch" in b.reason, "reason: " & b.reason
    assert "axiom_u64_probe::u64_add" in b.reason, "reason: " & b.reason

  # ── summary ────────────────────────────────────────────────────────────
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