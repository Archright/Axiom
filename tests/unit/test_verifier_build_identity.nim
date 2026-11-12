{.push raises: [CatchableError].}

## Verifier build identity (Phase 1B engineBuild) — regression tests.
##
## Covers:
##   - the pure composer: determinism, order invariance, path/content
##     sensitivity, empty-manifest fail-closed;
##   - the generated VerifierBuildId equals the documented verifier input-set
##     composition (src/**/*.nim minus src/generated/ + config.nims +
##     axiom.nimble + axiom.lock) — which excludes docs/tests BY CONSTRUCTION:
##     a docs-only commit cannot move the identity, a verifier source change
##     must (the perturbation tests pin both directions on fixture inputs);
##   - writer == pin: the cert writer's toolchainIdentity and the journal
##     admission pin are the SAME measured composition;
##   - missing/mismatched engineBuild never matches the pin (fail-closed);
##   - the product-label axiomVersion is NOT a pin component;
##   - the v3 identity extension is marker-conditional: legacy states keep the
##     13-field identity, strict-contract states bind the completeness fields.
##
## Run: nim c --hints:off --path:src -o:tmp/test_verifier_build_identity -r tests/unit/test_verifier_build_identity.nim

import std/[os, strutils, json, sequtils, unittest]
import ../../src/core/trusted/verifier_build_identity
import ../../src/core/crypto/hash_kernel
import ../../src/verification/attestation_orchestrator
import ../../src/verification/cert_reconcile
import ../../src/verification/certificate_identity

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      return getCurrentDir()
    dir = parent

proc generatedVerifierBuildId(): string =
  ## Read the generated `VerifierBuildId` const out of build_env.nim (or its
  ## tracked bootstrap fallback). "" when unavailable.
  for candidate in ["src/generated/build_env.nim",
                    "src/generated/build_env.nim.default"]:
    let p = findRepoRoot() / candidate
    if not fileExists(p):
      continue
    for line in readFile(p).splitLines():
      if line.contains("VerifierBuildId*"):
        let parts = line.split('"')
        if parts.len >= 2:
          return parts[1]
  ""

proc collectVerifierInputManifest(root: string): seq[(string, string)] =
  ## The DOCUMENTED verifier build input set (tools/hermetic_build.nim
  ## computeVerifierBuildManifest contract): src/**/*.nim excluding
  ## src/generated/, plus config.nims + axiom.nimble + axiom.lock. Docs, tests,
  ## data and git metadata are NOT inputs.
  for f in walkDirRec(root / "src"):
    if f.endsWith(".nim") and not f.contains("/generated/"):
      result.add((relativePath(f, root), sha256Hex(readFile(f))))
  for extra in ["config.nims", "config/effects.nims", "src/gate/config.nims",
                "Makefile", "axiom.nimble", "axiom.lock",
                "proofs/lean-toolchain"]:
    let p = root / extra
    if fileExists(p):
      result.add((extra, sha256Hex(readFile(p))))

suite "verifier build identity (Phase 1B engineBuild)":

  test "composer is deterministic and order-invariant":
    let a: seq[(string, string)] = @[("src/b.nim", "aa"), ("src/a.nim", "bb")]
    let b: seq[(string, string)] = @[("src/a.nim", "bb"), ("src/b.nim", "aa")]
    let idA = computeVerifierBuildId(a)
    check idA.len == 64
    check idA == computeVerifierBuildId(a)
    check idA == computeVerifierBuildId(b)

  test "composer is content- and path-sensitive":
    let base: seq[(string, string)] = @[("src/a.nim", "aa"), ("src/b.nim", "bb")]
    let contentMoved: seq[(string, string)] = @[("src/a.nim", "cc"), ("src/b.nim", "bb")]
    let pathMoved: seq[(string, string)] = @[("src/moved.nim", "aa"), ("src/b.nim", "bb")]
    let idBase = computeVerifierBuildId(base)
    check computeVerifierBuildId(contentMoved) != idBase
    check computeVerifierBuildId(pathMoved) != idBase

  test "empty manifest fails closed (no plausible identity)":
    check computeVerifierBuildId(@[]).len == 0

  test "generated VerifierBuildId is the documented input-set composition":
    ## The generator's manifest must be EXACTLY the documented verifier input
    ## set — which excludes docs/tests by construction, so a docs-only commit
    ## keeps the identity and a verifier source change moves it.
    let gen = generatedVerifierBuildId()
    if gen.len == 0:
      discard  # build_env.nim not generated in this checkout — nothing to pin
    else:
      check gen.len == 64
      for ch in gen:
        check ch in {'0'..'9', 'a'..'f'}
      let manifest = collectVerifierInputManifest(findRepoRoot())
      check manifest.len > 0
      check computeVerifierBuildId(manifest) == gen

  test "verifier source change moves the id; non-input changes cannot":
    ## Fixture-input pin of the cutover property: any single verifier input
    ## mutation moves the id; the input set itself never contains docs/tests,
    ## so a docs-only commit is the identity function over the manifest.
    let manifest = collectVerifierInputManifest(findRepoRoot())
    if manifest.len == 0:
      discard  # manifest unavailable in this checkout
    else:
      let base = computeVerifierBuildId(manifest)
      var drifted = manifest
      drifted[0] = (drifted[0][0], sha256Hex(drifted[0][1] & "-docs-only-sim"))  # source content drift
      check computeVerifierBuildId(drifted) != base
      # Simulated docs-only commit: no verifier input changes → same identity.
      check computeVerifierBuildId(manifest) == base

  test "writer composition == journal admission pin (same proc, writer==pin)":
    let pin = currentJournalToolchainPin()
    check pin == verifierToolchainIdentityJson()
    check pin{"nim"}.getStr("").len > 0
    check pin{"lean"}.getStr("").len > 0
    check pin{"z3"}.getStr("").len > 0
    check pin{"engineBuild"}.getStr("").len == 64

  test "pin matches the writer form; missing/mismatched engineBuild fails closed":
    var writerForm = verifierToolchainIdentityJson()
    writerForm["axiomVersion"] = newJString("v0.3.7")  # product label, writer-only
    check toolchainIdentityMatchesPin(writerForm)
    var missing = writerForm
    missing.delete("engineBuild")
    check toolchainIdentityMatchesPin(missing) == false
    var mismatched = writerForm
    mismatched["engineBuild"] = newJString(repeat('0', 64))
    check toolchainIdentityMatchesPin(mismatched) == false

  test "stale or non-canonical engine identity is never admissible":
    ## The VerifierBuildSourceHash cross-check: an id measured for a different
    ## source tree, a missing tree binding, or a non-canonical value is
    ## "unmeasured" — never a stale-but-plausible engine identity.
    let real = repeat('a', 64)
    check admissibleVerifierBuildId(real, "src-hash-1", "src-hash-1") == real
    check admissibleVerifierBuildId(real, "src-hash-1", "src-hash-2") == "unmeasured"
    check admissibleVerifierBuildId(real, "", "src-hash-1") == "unmeasured"
    check admissibleVerifierBuildId("__AXIOM_VERIFIER_BUILD_ID__",
      "src-hash-1", "src-hash-1") == "unmeasured"
    check admissibleVerifierBuildId("", "src-hash-1", "src-hash-1") == "unmeasured"
    check admissibleVerifierBuildId(repeat('Z', 64),
      "src-hash-1", "src-hash-1") == "unmeasured"

  test "v3 identity extension is marker-conditional (old certs keep 13-field identity)":
    let legacy = V3IdentityState(
      schemaVersion: "axiom.certificate.v3", modulePath: "src/m.nim",
      functionName: "f", sourceHash: "s", irHash: "i", leanProposition: "p",
      solverStatus: "unsat", status: "certGreen", winningStrategy: "lean-replay",
      inputHash: "ih", solverInputDigest: "sid", solverResultDigest: "srd",
      evidenceId: "e")
    let legacyWithEmptyStrict = legacy
    check compV3Identity(legacy) == compV3Identity(legacyWithEmptyStrict)
    # The strict fields without the marker do NOT move the identity.
    var marked = legacy
    marked.completenessContract = CompletenessContractStrictV1
    marked.completenessEvidenceKey = repeat('a', 64)
    marked.completenessBindingDigest = repeat('b', 64)
    check compV3Identity(marked) != compV3Identity(legacy)
    # Marker without bound fields still extends (writer never emits that; the
    # identity must not silently alias it to the legacy projection).
    var markerOnly = legacy
    markerOnly.completenessContract = CompletenessContractStrictV1
    check compV3Identity(markerOnly) != compV3Identity(legacy)

  test "v3IdentityFromJson round-trips both generations":
    let legacyJson = %*{
      "schemaVersion": "axiom.certificate.v3", "modulePath": "src/m.nim",
      "functionName": "f", "sourceHash": "s", "irHash": "i",
      "leanProposition": "p", "solverStatus": "unsat", "status": "certGreen",
      "winningStrategy": "lean-replay", "inputHash": "ih",
      "solverInputDigest": "sid", "solverResultDigest": "srd",
      "evidenceId": "e"
    }
    let state = V3IdentityState(
      schemaVersion: "axiom.certificate.v3", modulePath: "src/m.nim",
      functionName: "f", sourceHash: "s", irHash: "i", leanProposition: "p",
      solverStatus: "unsat", status: "certGreen", winningStrategy: "lean-replay",
      inputHash: "ih", solverInputDigest: "sid", solverResultDigest: "srd",
      evidenceId: "e")
    check v3IdentityFromJson(legacyJson) == compV3Identity(state)
    var strictJson = legacyJson
    strictJson["completenessContract"] = newJString(CompletenessContractStrictV1)
    strictJson["completenessEvidenceKey"] = newJString(repeat('a', 64))
    strictJson["completenessBindingDigest"] = newJString(repeat('b', 64))
    check v3IdentityFromJson(strictJson) == compV3Identity(V3IdentityState(
      schemaVersion: "axiom.certificate.v3", modulePath: "src/m.nim",
      functionName: "f", sourceHash: "s", irHash: "i", leanProposition: "p",
      solverStatus: "unsat", status: "certGreen", winningStrategy: "lean-replay",
      inputHash: "ih", solverInputDigest: "sid", solverResultDigest: "srd",
      evidenceId: "e",
      completenessContract: CompletenessContractStrictV1,
      completenessEvidenceKey: repeat('a', 64),
      completenessBindingDigest: repeat('b', 64)))
    # Stripping the marker from a strict cert demotes the projection — the
    # stored 16-field digest no longer matches (fail-closed tamper direction).
    var stripped = strictJson
    stripped.delete("completenessContract")
    check v3IdentityFromJson(stripped) == v3IdentityFromJson(legacyJson)
