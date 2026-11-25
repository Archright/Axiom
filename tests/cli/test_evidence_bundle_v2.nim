## Evidence Bundle v2 — export → verify end-to-end plus a tamper matrix.
##
## The fixture is synthetic but the artifacts are real: a temp git subject, a
## certificate whose identity fields recompute, a run-scoped proof state, and
## a propositions map. Kernel re-execution runs the pinned Lean/Z3 binaries.
##
## Every tamper case re-seals the digests where the mutation is semantic, so a
## FAIL is attributable to the targeted leg rather than to a stale digest.

import std/json
import std/os
import std/osproc
import std/strutils
import std/times
import std/unittest
import core/crypto/hash_kernel
import core/proof/source_fingerprint
import core/results
import infrastructure/process_utils
import verification/canonical_json
import verification/evidence_bundle/bundle_export
import verification/evidence_bundle/bundle_schema
import verification/evidence_bundle/bundle_toolchain
import verification/evidence_bundle/bundle_verify
import verification/evidence_bundle/strict_json
import verification/kernel_reexecution

const
  TestAttestationSchema = "axiom.evidence-bundle.attestation.v1"
  TestAppId = 5795152
  TestRulesetId = 27097366

type
  Fixture = object
    root: string
    subject: string
    vault: string
    proofStatePath: string
    propositionsPath: string
    emptyPropositionsPath: string
    bundleDir: string
    commit: string
    proposition: string

proc sh(cmd: string): string =
  let (output, code) = execCmdWithTimeout(cmd, timeoutMs = 120_000)
  if code != 0:
    raise newException(IOError, "command failed (" & $code & "): " & cmd & "\n" & output)
  output

proc writeText(path, text: string) =
  let parent = parentDir(path)
  if parent.len > 0 and not dirExists(parent):
    createDir(parent)
  writeFile(path, text)

proc loadStrict(path: string): JsonNode =
  let parsed = parseStrictJson(readFile(path))
  if parsed.isErr:
    raise newException(ValueError, path & ": " & parsed.error)
  parsed.get

proc legacyEvidenceId(obligationId, propositionHash, leanSourceHash, kaaDigest,
                      toolchainFingerprint, executionContractDigest: string): string =
  evidenceIdFromFields(obligationId, propositionHash, leanSourceHash, kaaDigest,
    toolchainFingerprint, executionContractDigest, "")

proc buildFixture(): Fixture =
  result.root = getTempDir() / ("axiom_ebv2_" & $getCurrentProcessId() & "_" &
    $epochTime().int64)
  if dirExists(result.root):
    removeDir(result.root)
  createDir(result.root)
  result.subject = result.root / "subject"
  createDir(result.subject / "src")
  result.vault = result.root / "vault"
  createDir(result.vault)

  let sourceText = "proc f*(): int = 42\n"
  writeText(result.subject / "src" / "demo.nim", sourceText)
  discard sh("git -C " & quoteShell(result.subject) & " init -q")
  discard sh("git -C " & quoteShell(result.subject) &
    " config user.email evidence-bundle@example.invalid")
  discard sh("git -C " & quoteShell(result.subject) &
    " config user.name evidence-bundle-test")
  discard sh("git -C " & quoteShell(result.subject) & " add -A")
  discard sh("git -C " & quoteShell(result.subject) & " commit -q -m init")
  result.commit = sh("git -C " & quoteShell(result.subject) & " rev-parse HEAD").strip()

  let proposition = "theorem demo_f : True"
  let propositionHash = sha256Hex(proposition)
  let leanSource = "theorem demo_f : True := by trivial\n"
  let leanSourceHash = sha256Hex(leanSource)
  let obligationId = sha256Hex("obligation|demo")
  let toolchainFingerprint = sha256Hex("toolchain|demo")
  let executionContractDigest = sha256Hex("execution|demo")

  var kaa = newJObject()
  kaa["observedAxiomSet"] = newJArray()
  kaa["receiptArtifactIdentity"] = %leanSourceHash
  # `canonicalizeKaa` always projects `receiptTheoremIdentity`; a fixture without
  # it is a malformed projection, and the verifier now rejects exactly that.
  kaa["receiptTheoremIdentity"] = %"demo_f"
  kaa["schema"] = %"axiom.kaa.v1"
  let canonicalKaa = canonicalJsonString(kaa)
  let kaaDigest = sha256Hex(canonicalKaa)
  let evidenceId = legacyEvidenceId(obligationId, propositionHash, leanSourceHash,
    kaaDigest, toolchainFingerprint, executionContractDigest)
  let irHash = sha256Hex("ir|demo")

  let cert = %*{
    "irHash": irHash,
    "modulePath": "src/demo.nim",
    "functionName": "f",
    "propositionHash": propositionHash,
    "leanSourceHash": leanSourceHash,
    "leanSource": leanSource,
    "smtlib2": "(assert false)\n(check-sat)\n",
    "sourceHash": computeStableSourceFingerprint(sourceText),
    "obligationId": obligationId,
    "kaaDigest": kaaDigest,
    "canonicalKaa": canonicalKaa,
    "toolchainFingerprint": toolchainFingerprint,
    "executionContractDigest": executionContractDigest,
    "evidenceId": evidenceId,
    "status": "certGreen",
    "axiomsUsed": newJArray(),
    "backend": "lean+z3",
    "kernel": true,
    "solverStatus": "unsat",
    "solverMeta": {"leanCompilerVerified": true}
  }
  writeText(result.vault / (irHash & ".json"), canonicalJsonString(cert) & "\n")

  let proofState = %*{
    "executionIdentity": {"verifierBuildId": measuredVerifierBuildId()},
    "unitEvidenceRefs": {
      "src/demo.nim::f": {
        "canonicalEvidence": {
          "propositionHash": propositionHash,
          "evidenceId": evidenceId,
          "leanSourceHash": leanSourceHash,
          "kaaDigest": kaaDigest,
          "toolchainFingerprint": toolchainFingerprint
        }
      }
    },
    "runAccounting": {
      "units": [{
        "unitId": "src/demo.nim::f",
        "verificationOutcome": "SATISFIED",
        "satisfactionSource": "FRESH"
      }]
    }
  }
  result.proofStatePath = result.root / "proof-state.json"
  writeText(result.proofStatePath, canonicalJsonString(proofState) & "\n")

  var props = newJObject()
  props[propositionHash] = %proposition
  result.propositionsPath = result.root / "propositions.json"
  writeText(result.propositionsPath, canonicalJsonString(props) & "\n")

  result.emptyPropositionsPath = result.root / "propositions-empty.json"
  writeText(result.emptyPropositionsPath, "{}\n")
  result.proposition = proposition

  result.bundleDir = result.root / "bundle"

proc exportWith(f: Fixture; proofStatePath, propositionsPath,
                outDir: string): Result[BundleExportOutcome, string] =
  exportEvidenceBundle(BundleExportOptions(
    proofStatePath: proofStatePath,
    subjectRepo: "Archright/Axiom",
    subjectCommit: f.commit,
    baseSha: f.commit,
    subjectRoot: f.subject,
    outDir: outDir,
    vaultDir: f.vault,
    propositionsPath: propositionsPath,
    runId: "12345",
    runAttempt: "1",
    workflowPath: ".github/workflows/ci.yml",
    workflowRef: "Archright/Axiom/.github/workflows/ci.yml@refs/heads/main",
    event: "push",
    headSha: f.commit))

proc exportFixture(f: Fixture): BundleExportOutcome =
  let exported = exportWith(f, f.proofStatePath, f.propositionsPath, f.bundleDir)
  if exported.isErr:
    raise newException(IOError, "export failed: " & exported.error)
  exported.get

proc verifyBundle(dir: string; kernel = false; attestation = "";
                  checkRuns = ""; ruleset = ""): BundleVerifyOutcome =
  verifyEvidenceBundle(BundleVerifyOptions(
    bundleDir: dir,
    attestationPath: attestation,
    checkRunsPath: checkRuns,
    rulesetPath: ruleset,
    runKernel: kernel))

func statusOf(outcome: BundleVerifyOutcome; name: string): BundleLegStatus =
  for leg in outcome.legs:
    if leg.name == name: return leg.status
  blsFail

proc dumpOutcome(outcome: BundleVerifyOutcome) =
  for leg in outcome.legs:
    echo "    ", leg.name, " ", legStatusText(leg.status), " — ", leg.detail
  echo "    exit=", outcome.exitCode

proc manifestOf(dir: string): JsonNode =
  loadStrict(dir / "manifest.json")

proc reseal(dir: string; manifest: JsonNode) =
  manifest["evidenceDigest"] = %evidenceDigestFor(manifest)
  manifest["provenanceDigest"] = %provenanceDigestFor(manifest)
  manifest["bundleDigest"] = %bundleDigestFor(manifest)
  writeText(dir / "manifest.json", canonicalManifestText(manifest))

proc certRel(manifest: JsonNode; i: int): string =
  strOf(manifest["certs"][i], "path")

proc readCert(dir: string; manifest: JsonNode; i: int): JsonNode =
  loadStrict(dir / certRel(manifest, i))

proc writeCert(dir: string; manifest: JsonNode; i: int; doc: JsonNode) =
  let rel = certRel(manifest, i)
  let text = canonicalJsonString(doc) & "\n"
  writeText(dir / rel, text)
  manifest["certs"][i]["sha256"] = %sha256Hex(text)

proc copyFixtureBundle(f: Fixture; name: string): string =
  result = f.root / name
  copyDir(f.bundleDir, result)

proc expectFail(f: Fixture; name, legName: string;
                mutate: proc(dir: string)) =
  let dir = copyFixtureBundle(f, name)
  mutate(dir)
  let outcome = verifyBundle(dir)
  check outcome.exitCode == 1
  check statusOf(outcome, legName) == blsFail
  if statusOf(outcome, legName) != blsFail:
    echo "tamper case ", name, " did not fail ", legName
    dumpOutcome(outcome)

proc expectKernelFail(f: Fixture; name: string;
                      mutate: proc(dir: string)) =
  let dir = copyFixtureBundle(f, name)
  mutate(dir)
  let outcome = verifyBundle(dir, kernel = true)
  check outcome.exitCode == 1
  check statusOf(outcome, "kernel") == blsFail
  if statusOf(outcome, "kernel") != blsFail:
    echo "tamper case ", name, " did not fail kernel"
    dumpOutcome(outcome)

# ── fixture setup + positive paths ──────────────────────────────────────────

suite "evidence bundle v2":
  test "export, verify, and tamper matrix":
    let f = buildFixture()
    defer:
      try:
        removeDir(f.root)
      except CatchableError as e:
        echo "[cleanup] removeDir failed for ", f.root, ": ", e.msg

    let exported = exportFixture(f)
    check exported.certCount == 1
    check exported.sourceCount == 1
    check exported.evidenceDigest.len == 64
    check exported.provenanceDigest.len == 64
    check exported.bundleDigest.len == 64
    check fileExists(f.bundleDir / "manifest.json")
    check fileExists(f.bundleDir / "certs" / (exported.bundleDigest & ".json")) == false

    let clean = verifyBundle(f.bundleDir)
    check clean.exitCode == 0
    check statusOf(clean, "bundleContent") == blsPass
    check statusOf(clean, "certEvidence") == blsPass
    check statusOf(clean, "subjectBinding") == blsPass
    check statusOf(clean, "kernel") == blsNotChecked
    check statusOf(clean, "provenance") == blsNotChecked
    check statusOf(clean, "mergeAuthority") == blsNotChecked
    if clean.exitCode != 0: dumpOutcome(clean)

    let manifest = manifestOf(f.bundleDir)
    check manifest["schema"].getStr() == "axiom.evidence-bundle.v2"
    check manifest["counts"]["certs"].getInt() == 1
    check manifest["counts"]["kernelSymbols"].getInt() == 1

    # ── canonicalProposition fallback (§6): proof state, not the map ──────
    # The engine persists the sealed CLE's proposition into
    # canonicalEvidence.canonicalProposition. Export must succeed with an
    # EMPTY propositions map (the file is still required by the CLI contract)
    # and the verifier must accept the resulting bundle.
    proc stateWithCanonicalProposition(text: string): JsonNode =
      result = loadStrict(f.proofStatePath)
      let unit = result["unitEvidenceRefs"]["src/demo.nim::f"]
      unit["canonicalEvidence"]["canonicalProposition"] = %text

    let stateWithPropPath = f.root / "proof-state-with-proposition.json"
    writeText(stateWithPropPath,
      canonicalJsonString(stateWithCanonicalProposition(f.proposition)) & "\n")

    let fromStateDir = f.root / "bundle-from-state-proposition"
    let fromState = exportWith(f, stateWithPropPath,
      f.emptyPropositionsPath, fromStateDir)
    check fromState.isOk
    if fromState.isOk:
      check fromState.get.certCount == 1
      let fromStateClean = verifyBundle(fromStateDir)
      check fromStateClean.exitCode == 0
      if fromStateClean.exitCode != 0: dumpOutcome(fromStateClean)
    else:
      echo "    export from state proposition failed: ", fromState.error

    # Tampering the proposition (it no longer hashes to propositionHash)
    # must still fail, even with the fallback path.
    let tamperedStatePath = f.root / "proof-state-tampered-proposition.json"
    writeText(tamperedStatePath,
      canonicalJsonString(stateWithCanonicalProposition(
        "theorem demo_f : False")) & "\n")
    let tampered = exportWith(f, tamperedStatePath,
      f.emptyPropositionsPath, f.root / "bundle-tampered-proposition")
    check tampered.isErr
    if tampered.isErr:
      check tampered.error.contains("does not hash to propositionHash")
    else:
      echo "    tampered proposition unexpectedly exported"

    # Without either source the export is refused (the fallback is the state
    # field, never an implicit empty proposition).
    let noProp = exportWith(f, f.proofStatePath, f.emptyPropositionsPath,
      f.root / "bundle-empty-propositions")
    check noProp.isErr
    if noProp.isErr:
      check noProp.error.contains("canonicalProposition is missing")
    else:
      echo "    empty propositions unexpectedly exported"

    # ── kernel re-execution (real Lean + Z3) ──────────────────────────────
    let kernel = verifyBundle(f.bundleDir, kernel = true)
    check kernel.exitCode == 0
    check statusOf(kernel, "kernel") == blsPass
    if kernel.exitCode != 0: dumpOutcome(kernel)

    # ── provenance + merge authority positive path ───────────────────────
    var attestation = %*{
      "schema": TestAttestationSchema,
      "signerRepository": "Archright/Axiom",
      "verified": true,
      "subjectDigestSha256": exported.evidenceDigest
    }
    attestation["run"] = manifest["run"]
    let attPath = f.root / "attestation.json"
    writeText(attPath, canonicalJsonString(attestation) & "\n")

    let runs = %*{
      "total_count": 1,
      "check_runs": [{
        "id": 1,
        "name": "admission-check",
        "status": "completed",
        "conclusion": "success",
        "head_sha": f.commit,
        "app": {"id": TestAppId}
      }]
    }
    let runsPath = f.root / "check-runs.json"
    writeText(runsPath, canonicalJsonString(runs) & "\n")

    let ruleset = %*{
      "id": TestRulesetId,
      "name": "main",
      "target": "branch",
      "enforcement": "active",
      "bypass_actors": newJArray(),
      "rules": [{
        "type": "required_status_checks",
        "parameters": {
          "strict_required_status_checks_policy": true,
          "required_status_checks": [{
            "context": "admission-check",
            "integration_id": TestAppId
          }]
        }
      }]
    }
    let rulesetPath = f.root / "ruleset.json"
    writeText(rulesetPath, canonicalJsonString(ruleset) & "\n")

    let external = verifyBundle(f.bundleDir, attestation = attPath,
      checkRuns = runsPath, ruleset = rulesetPath)
    check external.exitCode == 0
    check statusOf(external, "provenance") == blsPass
    check statusOf(external, "mergeAuthority") == blsPass
    if external.exitCode != 0: dumpOutcome(external)

    # ── negative external observations ───────────────────────────────────
    var badAttestation = %*{
      "schema": TestAttestationSchema,
      "signerRepository": "attacker/repo",
      "verified": true,
      "subjectDigestSha256": exported.evidenceDigest
    }
    badAttestation["run"] = manifest["run"]
    let badAttPath = f.root / "attestation-bad.json"
    writeText(badAttPath, canonicalJsonString(badAttestation) & "\n")
    let badProvenance = verifyBundle(f.bundleDir, attestation = badAttPath)
    check badProvenance.exitCode == 1
    check statusOf(badProvenance, "provenance") == blsFail

    var failedRuns = %*{
      "total_count": 1,
      "check_runs": [{
        "id": 2,
        "name": "admission-check",
        "status": "completed",
        "conclusion": "failure",
        "head_sha": f.commit,
        "app": {"id": TestAppId}
      }]
    }
    let failedRunsPath = f.root / "check-runs-failed.json"
    writeText(failedRunsPath, canonicalJsonString(failedRuns) & "\n")
    let failedAuthority = verifyBundle(f.bundleDir, checkRuns = failedRunsPath)
    check failedAuthority.exitCode == 1
    check statusOf(failedAuthority, "mergeAuthority") == blsFail

    var bypassRuleset = ruleset
    bypassRuleset["bypass_actors"] = %*[{"actor_id": 1}]
    let bypassPath = f.root / "ruleset-bypass.json"
    writeText(bypassPath, canonicalJsonString(bypassRuleset) & "\n")
    let bypassed = verifyBundle(f.bundleDir, ruleset = bypassPath)
    check bypassed.exitCode == 1
    check statusOf(bypassed, "mergeAuthority") == blsFail

    # ── tamper matrix ────────────────────────────────────────────────────
    expectFail(f, "t_missing_field", "bundleContent", proc(dir: string) =
      let m = manifestOf(dir)
      var stripped = newJObject()
      for k, v in m:
        if k != "sourceVault": stripped[k] = v
      reseal(dir, stripped))

    expectFail(f, "t_unknown_field", "bundleContent", proc(dir: string) =
      let m = manifestOf(dir)
      m["extraField"] = %true
      reseal(dir, m))

    expectFail(f, "t_duplicate_key", "bundleContent", proc(dir: string) =
      let text = readFile(dir / "manifest.json")
      writeText(dir / "manifest.json", text[0 .. 0] &
        "\"schema\":\"axiom.evidence-bundle.v2\"," & text[1 .. ^1]))

    expectFail(f, "t_evidence_digest", "bundleContent", proc(dir: string) =
      let m = manifestOf(dir)
      var digest = m["evidenceDigest"].getStr()
      digest[0] = if digest[0] == 'a': 'b' else: 'a'
      m["evidenceDigest"] = %digest
      writeText(dir / "manifest.json", canonicalManifestText(m)))

    expectFail(f, "t_subject_id", "bundleContent", proc(dir: string) =
      let m = manifestOf(dir)
      m["subject"]["subjectId"] = %sha256Hex("wrong subject")
      reseal(dir, m))

    expectFail(f, "t_cert_file_sha", "bundleContent", proc(dir: string) =
      let m = manifestOf(dir)
      writeText(dir / certRel(m, 0), readFile(dir / certRel(m, 0)) & " "))

    expectFail(f, "t_missing_cert", "bundleContent", proc(dir: string) =
      let m = manifestOf(dir)
      removeFile(dir / certRel(m, 0)))

    expectFail(f, "t_symlink_source", "bundleContent", proc(dir: string) =
      let target = dir / "sources" / "src" / "demo.nim"
      removeFile(target)
      createSymlink("/etc/hostname", target))

    expectFail(f, "t_cert_path", "bundleContent", proc(dir: string) =
      let m = manifestOf(dir)
      m["certs"][0]["path"] = %"../evil.json"
      reseal(dir, m))

    expectFail(f, "t_cert_proposition", "certEvidence", proc(dir: string) =
      let m = manifestOf(dir)
      let wrongHash = sha256Hex("wrong proposition")
      var doc = readCert(dir, m, 0)
      doc["propositionHash"] = %wrongHash
      m["certs"][0]["propositionHash"] = %wrongHash
      writeCert(dir, m, 0, doc)
      reseal(dir, m))

    expectFail(f, "t_axiom_allowlist", "certEvidence", proc(dir: string) =
      let m = manifestOf(dir)
      var doc = readCert(dir, m, 0)
      var kaa = parseStrictJson(doc["canonicalKaa"].getStr()).get
      kaa["observedAxiomSet"] = %*["sorryAx"]
      let canonicalKaa = canonicalJsonString(kaa)
      let kaaDigest = sha256Hex(canonicalKaa)
      doc["canonicalKaa"] = %canonicalKaa
      doc["kaaDigest"] = %kaaDigest
      doc["axiomsUsed"] = %*["sorryAx"]
      doc["evidenceId"] = %legacyEvidenceId(doc["obligationId"].getStr(),
        doc["propositionHash"].getStr(), doc["leanSourceHash"].getStr(), kaaDigest,
        doc["toolchainFingerprint"].getStr(), doc["executionContractDigest"].getStr())
      writeCert(dir, m, 0, doc)
      reseal(dir, m))

    expectFail(f, "t_source_blob", "bundleContent", proc(dir: string) =
      writeText(dir / "sources" / "src" / "demo.nim", "proc f*(): int = 43\n"))

    expectFail(f, "t_source_index_duplicate", "bundleContent", proc(dir: string) =
      let index = loadStrict(dir / "sources" / "source-index.json")
      index["entries"].add(index["entries"][0])
      let m = manifestOf(dir)
      m["subject"]["treeDigest"] = %treeDigestFor(index["entries"])
      m["subject"]["subjectId"] = %subjectIdFor(
        m["subject"]["repository"].getStr(), m["subject"]["commit"].getStr(),
        m["subject"]["treeDigest"].getStr(), m["subject"]["baseSha"].getStr())
      writeText(dir / "sources" / "source-index.json",
        canonicalJsonString(index) & "\n")
      reseal(dir, m))

    expectFail(f, "t_tree_digest", "bundleContent", proc(dir: string) =
      let index = loadStrict(dir / "sources" / "source-index.json")
      var sha = index["entries"][0]["sha256"].getStr()
      sha[0] = if sha[0] == 'a': 'b' else: 'a'
      index["entries"][0]["sha256"] = %sha
      writeText(dir / "sources" / "source-index.json",
        canonicalJsonString(index) & "\n"))

    expectFail(f, "t_source_hash", "subjectBinding", proc(dir: string) =
      let m = manifestOf(dir)
      var doc = readCert(dir, m, 0)
      doc["sourceHash"] = %sha256Hex("not the shipped blob")
      writeCert(dir, m, 0, doc)
      reseal(dir, m))

    # A certificate may claim a different axiom set; the fresh Lean run is the
    # surface that catches it (cert/KAA/manifest agree with each other).
    expectKernelFail(f, "t_kernel_axioms", proc(dir: string) =
      let m = manifestOf(dir)
      var doc = readCert(dir, m, 0)
      var kaa = parseStrictJson(doc["canonicalKaa"].getStr()).get
      kaa["observedAxiomSet"] = %*["propext"]
      let canonicalKaa = canonicalJsonString(kaa)
      let kaaDigest = sha256Hex(canonicalKaa)
      doc["canonicalKaa"] = %canonicalKaa
      doc["kaaDigest"] = %kaaDigest
      doc["axiomsUsed"] = %*["propext"]
      doc["evidenceId"] = %legacyEvidenceId(doc["obligationId"].getStr(),
        doc["propositionHash"].getStr(), doc["leanSourceHash"].getStr(), kaaDigest,
        doc["toolchainFingerprint"].getStr(), doc["executionContractDigest"].getStr())
      m["certs"][0]["axiomsUsed"] = %*["propext"]
      m["certs"][0]["evidenceId"] = doc["evidenceId"]
      writeCert(dir, m, 0, doc)
      reseal(dir, m))

    # ── theorem identity (DEBT#572) ────────────────────────────────────────
    # The declaration the kernel printed axioms FOR is the axis a decoy source
    # attacks. `CertKeys` admits no flat `theoremName` and no `observation`, so
    # a bundle certificate's ONLY claim carrier is `canonicalKaa.
    # receiptTheoremIdentity`; the previous comparison read the flat field,
    # which is always "" here, and therefore never ran.
    proc mutateKaaTheorem(dir: string; claimed: string) =
      let m = manifestOf(dir)
      var doc = readCert(dir, m, 0)
      var kaa = parseStrictJson(doc["canonicalKaa"].getStr()).get
      kaa["receiptTheoremIdentity"] = %claimed
      let canonicalKaa = canonicalJsonString(kaa)
      doc["canonicalKaa"] = %canonicalKaa
      doc["kaaDigest"] = %sha256Hex(canonicalKaa)
      doc["evidenceId"] = %legacyEvidenceId(doc["obligationId"].getStr(),
        doc["propositionHash"].getStr(), doc["leanSourceHash"].getStr(),
        doc["kaaDigest"].getStr(), doc["toolchainFingerprint"].getStr(),
        doc["executionContractDigest"].getStr())
      m["certs"][0]["evidenceId"] = doc["evidenceId"]
      writeCert(dir, m, 0, doc)
      reseal(dir, m)

    # An absent claim is a malformed projection, not "nothing to check".
    expectFail(f, "t_kaa_theorem_absent", "certEvidence", proc(dir: string) =
      mutateKaaTheorem(dir, ""))

    # The measured 8.2 forgery: every recorded field stays self-consistent and
    # the claim is simply a theorem the embedded source never states, so only a
    # fresh run can tell the difference.
    expectKernelFail(f, "t_kernel_theorem", proc(dir: string) =
      mutateKaaTheorem(dir, "inc3_correct"))

    # The resolver itself, without Lean or a bundle: carriers must agree, and
    # absence is an error rather than a skipped comparison.
    check claimedTheoremIdentity(%*{"theoremName": "decoy_true"}).get == "decoy_true"
    check claimedTheoremIdentity(%*{"theoremName": "inc3_correct",
      "observation": {"lean": {"theoremName": "decoy_true"}}}).isErr
    check claimedTheoremIdentity(%*{}).isErr
    check theoremIdentityBindingError("inc3_correct", "decoy_true").len > 0
    check theoremIdentityBindingError("decoy_true", "decoy_true").len == 0
    check theoremIdentityBindingError("", "decoy_true").len > 0
    check theoremIdentityBindingError("decoy_true", "").len > 0

    # The shape predicate is what separates "never made a claim" from "made a
    # claim we cannot read". Both are `canonicalKaa` strings, so the
    # discriminator is whether the value parses to a projection — not whether
    # the field is non-empty. The legacy vault certificate
    # (axiom.certificate.v3, src/verification/certificates/) stores a bare
    # digest: it carries no projection, so `ax cert verify --kernel` must not
    # invent a theorem requirement for it. A projection that parses but omits
    # `receiptTheoremIdentity` is the malformed case and still denies.
    let legacyShape = %*{"canonicalKaa": sha256Hex("legacy")}
    check not kaaProjectionPresent(legacyShape)
    check claimedTheoremIdentity(legacyShape).isErr   # nothing to read ...
    check not kaaProjectionPresent(%*{"canonicalKaa": ""})
    check not kaaProjectionPresent(%*{"canonicalKaa": "not json at all"})
    check not kaaProjectionPresent(%*{"canonicalKaa": "[1, 2]"})
    var projection = newJObject()
    projection["schema"] = %"axiom.kaa.v1"
    check kaaProjectionPresent(%*{"canonicalKaa": canonicalJsonString(projection)})
    check claimedTheoremIdentity(
      %*{"canonicalKaa": canonicalJsonString(projection)}).isErr  # ... malformed projection denies
    projection["receiptTheoremIdentity"] = %"demo_f"
    check claimedTheoremIdentity(
      %*{"canonicalKaa": canonicalJsonString(projection)}).get == "demo_f"