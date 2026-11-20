import std/[algorithm, json, os, strutils, tables, unittest]

import ../../src/core/crypto/hash_kernel
import ../../src/core/proof/source_fingerprint
import ../../src/core/trusted/fingerprint_generator
import ../../src/verification/canonical_json
import ../../src/verification/cert_export
import ../../src/verification/certificate_identity

## Contract: docs/spec/admission_evidence_export_contract.md
## Each negative control breaks exactly one integrity layer and keeps the
## lower layers consistent, so the observed reasonCode proves the intended
## safeguard fired (contract §3.1), not an incidental digest error.

const
  KeyA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  KeyB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  KeyC = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  KeyD = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  KeyE = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

proc uapCert(irHash, modulePath, functionName, status, leanName: string;
             axioms: JsonNode): JsonNode =
  result = %*{
    "modulePath": modulePath,
    "functionName": functionName,
    "status": status,
    "solverStatus": "unsat",
    "kernel": true,
    "solverMeta": {"leanCompilerVerified": true},
    "irHash": irHash,
    "leanSource": "theorem " & leanName & " : True := trivial",
    "leanProposition": "True"
  }
  if not axioms.isNil:
    result["axiomsUsed"] = axioms

proc manifestEntry(modulePath, functionName, status: string;
                   irHash: string): JsonNode =
  %*{
    "modulePath": modulePath,
    "functionName": functionName,
    "status": status,
    "solverMethod": "z3+lean",
    "lastVerifiedAt": "2026-11-20T00:00:00Z",
    "irHash": irHash
  }

proc writeBody(dir: string; body: JsonNode): string =
  result = certCasKey(body) & ".json"
  writeFile(dir / result, $body)

proc writeRuntimeManifest(dir: string; entries: seq[JsonNode]) =
  var root = %*{"version": 2, "entries": []}
  for e in entries:
    root["entries"].add e
  writeFile(dir / "manifest.json", $root)

proc makeGoldenVault(base: string): string =
  ## One verified UAP cert (manifest irHash deliberately differs from the
  ## body's CAS key — §2.2a) plus one non-verified entry without a body.
  result = base / "vault-src"
  createDir(result)
  discard writeBody(result, uapCert(KeyA, "src/x.nim", "f", "certGreen",
    "fixture_theorem", %["propext", "Quot.sound"]))
  writeRuntimeManifest(result, @[
    manifestEntry("src/x.nim", "f", "certGreen", KeyB),
    manifestEntry("src/x.nim", "g", "certZ3Candidate", KeyC)
  ])

proc recomputeSetDigest(man: JsonNode): string =
  ## Contract §2.5, built from the exported projection. Used only to keep
  ## lower digest layers consistent while a higher layer is under test.
  var nodes = initTable[string, JsonNode]()
  var names: seq[string] = @[]
  for e in man["entries"]:
    let f = e["certificateFile"]
    if f.isNil or f.kind != JString: continue
    var d = newJObject()
    d["file"] = f
    d["sha256"] = e["certificateSha256"]
    d["modulePath"] = e["modulePath"]
    d["functionName"] = e["functionName"]
    d["status"] = e["status"]
    d["recomputedStatus"] = e["recomputedStatus"]
    d["theoremIdentity"] = e["theoremIdentity"]
    d["axiomObservation"] = e["axiomObservation"]["status"]
    names.add f.getStr("")
    nodes[f.getStr("")] = d
  names.sort()
  var arr = newJArray()
  for n in names:
    arr.add nodes[n]
  var input = newJObject()
  input["schema"] = %ExportSetSchema
  input["certificates"] = arr
  sha256Hex(canonicalJsonString(input))

proc loadManifest(bundleDir: string): JsonNode =
  parseJson(readFile(bundleDir / ExportManifestName))

proc saveManifest(bundleDir: string; man: JsonNode) =
  writeFile(bundleDir / ExportManifestName, canonicalJsonString(man) & "\n")

proc removeInventoryLine(bundleDir, name: string) =
  let path = bundleDir / ExportInventoryName
  var kept: seq[string] = @[]
  for line in readFile(path).splitLines():
    if line.len > 0 and line != name:
      kept.add line
  writeFile(path, kept.join("\n") & "\n")

suite "admission evidence export — ax cert export / verify-export":

  var tmpRoot: string

  setup:
    tmpRoot = getTempDir() / "ax_cert_export_test_" & $getCurrentProcessId()
    removeDir(tmpRoot)
    createDir(tmpRoot)

  teardown:
    removeDir(tmpRoot)

  test "golden: export PASS with complete projection; verify-export PASS":
    let src = makeGoldenVault(tmpRoot)
    let outDir = tmpRoot / "out"
    let exp = exportToDir(src, outDir)
    check exp.ok
    check exp.certCount == 1
    check exp.digest.len == 64

    let man = loadManifest(outDir / "vault")
    check man["schema"].getStr("") == ExportSchema
    let verified = man["entries"][0]
    check verified["certificateFile"].getStr("") == KeyA & ".json"
    check verified["certificateSha256"].getStr("") ==
      sha256Hex($uapCert(KeyA, "src/x.nim", "f", "certGreen",
        "fixture_theorem", %["propext", "Quot.sound"]))
    check verified["recomputedStatus"].getStr("") == "certGreen"
    check verified["theoremIdentity"].getStr("") == "fixture_theorem"
    check verified["axiomObservation"]["status"].getStr("") == "observed"
    check verified["axiomObservation"]["names"].len == 2
    let candidate = man["entries"][1]
    check candidate["certificateFile"].kind == JNull
    check candidate["recomputedStatus"].kind == JNull
    check candidate["axiomObservation"]["status"].getStr("") == "not-applicable"

    let ver = verifyBundle(outDir / "vault")
    check ver.ok
    check ver.entryCount == 2
    check ver.bodiesPresent
    check ver.digest == exp.digest
    check ver.closure == "not-claimed"

  test "exporter determinism: same vault exported twice → identical digest and bytes":
    let src = makeGoldenVault(tmpRoot)
    let e1 = exportToDir(src, tmpRoot / "out1")
    let e2 = exportToDir(src, tmpRoot / "out2")
    check e1.ok and e2.ok
    check e1.digest == e2.digest
    check readFile(tmpRoot / "out1" / "vault" / ExportManifestName) ==
      readFile(tmpRoot / "out2" / "vault" / ExportManifestName)
    check readFile(tmpRoot / "out1" / "vault" / ExportInventoryName) ==
      readFile(tmpRoot / "out2" / "vault" / ExportInventoryName)
    check readFile(tmpRoot / "out1" / "vault" / (KeyA & ".json")) ==
      readFile(tmpRoot / "out2" / "vault" / (KeyA & ".json"))

  test "lookup is (modulePath,functionName), not manifest irHash (§2.2a)":
    # Golden vault: manifest irHash = KeyB, body CAS key = KeyA.
    let exp = exportToDir(makeGoldenVault(tmpRoot), tmpRoot / "out")
    check exp.ok
    check loadManifest(tmpRoot / "out" / "vault")["entries"][0][
      "certificateFile"].getStr("") == KeyA & ".json"

  test "ambiguous certificate identity → CERT_INVENTORY_MISMATCH":
    let src = tmpRoot / "vault-src"
    createDir(src)
    discard writeBody(src, uapCert(KeyA, "src/x.nim", "f", "certGreen",
      "fixture_theorem", %["propext"]))
    discard writeBody(src, uapCert(KeyD, "src/x.nim", "f", "certGreen",
      "fixture_theorem2", %["propext"]))
    writeRuntimeManifest(src, @[manifestEntry("src/x.nim", "f", "certGreen", KeyB)])
    let exp = exportToDir(src, tmpRoot / "out")
    check not exp.ok
    check "CERT_INVENTORY_MISMATCH" in exp.codes

  test "CAS key != basename → CERT_INVENTORY_MISMATCH":
    let src = tmpRoot / "vault-src"
    createDir(src)
    writeFile(src / (KeyD & ".json"), $uapCert(KeyA, "src/x.nim", "f",
      "certGreen", "fixture_theorem", %["propext"]))
    writeRuntimeManifest(src, @[manifestEntry("src/x.nim", "f", "certGreen", KeyB)])
    let exp = exportToDir(src, tmpRoot / "out")
    check not exp.ok
    check "CERT_INVENTORY_MISMATCH" in exp.codes

  test "verified entry without body → CERT_BODY_MISSING":
    let src = tmpRoot / "vault-src"
    createDir(src)
    writeRuntimeManifest(src, @[manifestEntry("src/x.nim", "f", "certGreen", KeyB)])
    let exp = exportToDir(src, tmpRoot / "out")
    check not exp.ok
    check "CERT_BODY_MISSING" in exp.codes

  test "non-empty output dir → export fails (residue guard)":
    let src = makeGoldenVault(tmpRoot)
    createDir(tmpRoot / "out" / "vault")
    writeFile(tmpRoot / "out" / "vault" / "leftover.txt", "residue")
    let exp = exportToDir(src, tmpRoot / "out")
    check not exp.ok
    check "CERT_INVENTORY_MISMATCH" in exp.codes

  test "empty axiomsUsed is observed (kernel-pure), names = []":
    let src = tmpRoot / "vault-src"
    createDir(src)
    discard writeBody(src, uapCert(KeyA, "src/x.nim", "f", "certGreen",
      "fixture_theorem", %[]))
    writeRuntimeManifest(src, @[manifestEntry("src/x.nim", "f", "certGreen", KeyB)])
    let exp = exportToDir(src, tmpRoot / "out")
    check exp.ok
    let e = loadManifest(tmpRoot / "out" / "vault")["entries"][0]
    check e["axiomObservation"]["status"].getStr("") == "observed"
    check e["axiomObservation"]["names"].len == 0
    check verifyBundle(tmpRoot / "out" / "vault").ok

  test "synthetic subject-continuity body without axiomsUsed → AXIOM_OBSERVATION_MISSING":
    let src = tmpRoot / "vault-src"
    createDir(src)
    var body = %*{
      "kind": "subject-continuity",
      "modulePath": "src/s.nim",
      "functionName": "s",
      "status": "certGreen",
      "solverStatus": "unsat",
      "kernel": true,
      "solverMeta": {"leanCompilerVerified": true},
      "subjectId": KeyE,
      "leanSource": "theorem kc : True := trivial",
      "leanProposition": "True"
    }
    writeFile(src / (KeyE & ".json"), $body)
    writeRuntimeManifest(src, @[manifestEntry("src/s.nim", "s", "certGreen", KeyB)])
    let exp = exportToDir(src, tmpRoot / "out")
    check not exp.ok
    check "AXIOM_OBSERVATION_MISSING" in exp.codes

  test "stale inventory (body deleted) → CERT_INVENTORY_MISMATCH":
    let exp = exportToDir(makeGoldenVault(tmpRoot), tmpRoot / "out")
    check exp.ok
    removeFile(tmpRoot / "out" / "vault" / (KeyA & ".json"))
    let ver = verifyBundle(tmpRoot / "out" / "vault")
    check not ver.ok
    check ver.reasonCode == "CERT_INVENTORY_MISMATCH"

  test "extra file in export set → CERT_INVENTORY_MISMATCH":
    let exp = exportToDir(makeGoldenVault(tmpRoot), tmpRoot / "out")
    check exp.ok
    writeFile(tmpRoot / "out" / "vault" / "notes.txt", "extra")
    let ver = verifyBundle(tmpRoot / "out" / "vault")
    check not ver.ok
    check ver.reasonCode == "CERT_INVENTORY_MISMATCH"

  test "verified entry without body reference (consistent inventory) → CERT_BODY_MISSING":
    let exp = exportToDir(makeGoldenVault(tmpRoot), tmpRoot / "out")
    check exp.ok
    let bundle = tmpRoot / "out" / "vault"
    removeFile(bundle / (KeyA & ".json"))
    removeInventoryLine(bundle, KeyA & ".json")
    var man = loadManifest(bundle)
    let e = man["entries"][0]
    e["certificateFile"] = newJNull()
    e["certificateSha256"] = newJNull()
    e["recomputedStatus"] = newJNull()
    e["theoremIdentity"] = newJNull()
    e["axiomObservation"]["status"] = %"not-applicable"
    e["axiomObservation"]["names"] = newJNull()
    saveManifest(bundle, man)
    let ver = verifyBundle(bundle)
    check not ver.ok
    check ver.reasonCode == "CERT_BODY_MISSING"

  test "recomputedStatus projection tampered → CERT_STATUS_MISMATCH":
    let exp = exportToDir(makeGoldenVault(tmpRoot), tmpRoot / "out")
    check exp.ok
    let bundle = tmpRoot / "out" / "vault"
    var man = loadManifest(bundle)
    man["entries"][0]["recomputedStatus"] = %"certLeanVerified"
    saveManifest(bundle, man)
    let ver = verifyBundle(bundle)
    check not ver.ok
    check ver.reasonCode == "CERT_STATUS_MISMATCH"

  test "status string promoted to verified without evidence → CERT_STATUS_MISMATCH":
    let src = tmpRoot / "vault-src"
    createDir(src)
    # Z3-only evidence (no Lean): recomputes to certZ3Candidate, never certGreen.
    var body = %*{
      "modulePath": "src/x.nim",
      "functionName": "f",
      "status": "certZ3Candidate",
      "solverStatus": "unsat",
      "kernel": false,
      "solverMeta": {"leanCompilerVerified": false},
      "irHash": KeyA,
      "smtlib2": "(assert true)"
    }
    discard writeBody(src, body)
    writeRuntimeManifest(src, @[manifestEntry("src/x.nim", "f", "certZ3Candidate", KeyB)])
    let exp = exportToDir(src, tmpRoot / "out")
    check exp.ok
    let bundle = tmpRoot / "out" / "vault"
    var man = loadManifest(bundle)
    man["entries"][0]["status"] = %"certGreen"
    saveManifest(bundle, man)
    let ver = verifyBundle(bundle)
    check not ver.ok
    check ver.reasonCode == "CERT_STATUS_MISMATCH"

  test "body bytes tampered → CERT_DIGEST_MISMATCH":
    let exp = exportToDir(makeGoldenVault(tmpRoot), tmpRoot / "out")
    check exp.ok
    let bodyPath = tmpRoot / "out" / "vault" / (KeyA & ".json")
    writeFile(bodyPath, readFile(bodyPath) & " ")
    let ver = verifyBundle(tmpRoot / "out" / "vault")
    check not ver.ok
    check ver.reasonCode == "CERT_DIGEST_MISMATCH"

  test "certificateSetDigest tampered → CERT_SET_DIGEST_MISMATCH":
    let exp = exportToDir(makeGoldenVault(tmpRoot), tmpRoot / "out")
    check exp.ok
    let bundle = tmpRoot / "out" / "vault"
    var man = loadManifest(bundle)
    man["certificateSetDigest"] = %KeyE
    saveManifest(bundle, man)
    let ver = verifyBundle(bundle)
    check not ver.ok
    check ver.reasonCode == "CERT_SET_DIGEST_MISMATCH"

  test "certificateSetDigest absent → CERT_SET_DIGEST_ABSENT":
    let exp = exportToDir(makeGoldenVault(tmpRoot), tmpRoot / "out")
    check exp.ok
    let bundle = tmpRoot / "out" / "vault"
    var man = loadManifest(bundle)
    man.delete("certificateSetDigest")
    saveManifest(bundle, man)
    let ver = verifyBundle(bundle)
    check not ver.ok
    check ver.reasonCode == "CERT_SET_DIGEST_ABSENT"

  test "axiom observation removed with recomputed lower digests → AXIOM_OBSERVATION_MISSING":
    let exp = exportToDir(makeGoldenVault(tmpRoot), tmpRoot / "out")
    check exp.ok
    let bundle = tmpRoot / "out" / "vault"
    let bodyPath = bundle / (KeyA & ".json")
    var body = parseJson(readFile(bodyPath))
    body.delete("axiomsUsed")
    writeFile(bodyPath, $body)
    var man = loadManifest(bundle)
    let e = man["entries"][0]
    e["certificateSha256"] = %sha256Hex(readFile(bodyPath))
    e["axiomObservation"]["status"] = %"not-observed"
    e["axiomObservation"]["names"] = newJNull()
    man["certificateSetDigest"] = %recomputeSetDigest(man)
    saveManifest(bundle, man)
    let ver = verifyBundle(bundle)
    check not ver.ok
    check ver.reasonCode == "AXIOM_OBSERVATION_MISSING"

  test "axiomObservation names projection tampered → CERT_PROJECTION_MISMATCH":
    let exp = exportToDir(makeGoldenVault(tmpRoot), tmpRoot / "out")
    check exp.ok
    let bundle = tmpRoot / "out" / "vault"
    var man = loadManifest(bundle)
    man["entries"][0]["axiomObservation"]["names"] = %["fake"]
    saveManifest(bundle, man)
    let ver = verifyBundle(bundle)
    check not ver.ok
    check ver.reasonCode == "CERT_PROJECTION_MISMATCH"

  test "entry without body carrying a body projection → CERT_PROJECTION_MISMATCH":
    let exp = exportToDir(makeGoldenVault(tmpRoot), tmpRoot / "out")
    check exp.ok
    let bundle = tmpRoot / "out" / "vault"
    var man = loadManifest(bundle)
    let e = man["entries"][1]  # certZ3Candidate, certificateFile = null
    e["certificateSha256"] = %KeyE
    saveManifest(bundle, man)
    let ver = verifyBundle(bundle)
    check not ver.ok
    check ver.reasonCode == "CERT_PROJECTION_MISMATCH"

  test "closure mode without journal → environmentError (exit 2), never PASS":
    # Closure runs only after isDeepVerified: the fixture must carry a valid
    # fingerprint/sourceHash/identityDigest so the first failing stage is the
    # journal binding, not an earlier integrity stage.
    let projectRoot = tmpRoot / "subject"
    createDir(projectRoot / "src")
    let sourceContent = "proc fx(): int = 1\n"
    writeFile(projectRoot / "src" / "x.nim", sourceContent)
    var body = %*{
      "modulePath": "src/x.nim",
      "functionName": "f",
      "status": "certGreen",
      "solverStatus": "unsat",
      "kernel": true,
      "solverMeta": {"leanCompilerVerified": true},
      "irHash": KeyA,
      "leanSource": "theorem fixture_theorem : True := trivial",
      "leanProposition": "True",
      "smtlib2": "",
      "axiomsUsed": ["propext", "Quot.sound"]
    }
    body["sourceHash"] = %computeStableSourceFingerprint(sourceContent)
    body["fingerprint"] = %computeVerificationFingerprint(KeyA, "True")
    body["identityDigest"] = %v3IdentityFromJson(body)
    let src = tmpRoot / "vault-src"
    createDir(src)
    discard writeBody(src, body)
    writeRuntimeManifest(src, @[manifestEntry("src/x.nim", "f", "certGreen", KeyB)])
    let exp = exportToDir(src, tmpRoot / "out")
    check exp.ok
    let ver = verifyBundle(tmpRoot / "out" / "vault", closureMode = true,
      projectRoot = projectRoot)
    check not ver.ok
    check ver.environmentError
    check ver.reasonCode == "CERT_INTEGRITY_FAILED"
    check ver.closure == "executed"

  test "scoped export: declared target only; non-declared verified row disclosed, never claimed":
    let src = tmpRoot / "vault-src"
    createDir(src)
    discard writeBody(src, uapCert(KeyA, "src/x.nim", "f", "certGreen",
      "fixture_theorem", %["propext"]))
    writeRuntimeManifest(src, @[
      manifestEntry("src/x.nim", "f", "certGreen", KeyB),
      manifestEntry("json_rpc/errors.nim", "new_errclass_control_02",
        "certGreen", KeyC)
    ])
    let exp = exportToDir(src, tmpRoot / "out", @["src/x.nim::f"])
    check exp.ok
    check exp.certCount == 1
    let bundle = tmpRoot / "out" / "vault"
    let man = loadManifest(bundle)
    check man["scope"]["targets"].len == 1
    check man["scope"]["targets"][0].getStr == "src/x.nim::f"
    check man["outOfScope"].len == 1
    check man["outOfScope"][0]["modulePath"].getStr == "json_rpc/errors.nim"
    check man["outOfScope"][0]["functionName"].getStr == "new_errclass_control_02"
    check man["outOfScope"][0]["reason"].getStr == "not-declared"
    check man["outOfScope"][0]["certificateFile"].kind == JNull
    let ver = verifyBundle(bundle, declaredTargets = @["src/x.nim::f"])
    check ver.ok
    # Determinism: identical scope + inputs → identical digest and bytes.
    let exp2 = exportToDir(src, tmpRoot / "out2", @["src/x.nim::f"])
    check exp2.ok
    check exp2.digest == exp.digest

  test "scoped export: declared target absent from the vault → CERT_INVENTORY_MISMATCH":
    let src = makeGoldenVault(tmpRoot)
    let exp = exportToDir(src, tmpRoot / "out", @["src/x.nim::missing"])
    check not exp.ok
    check "CERT_INVENTORY_MISMATCH" in exp.codes

  test "scoped verify: bundle scope != declared set → CERT_SCOPE_MISMATCH":
    let src = tmpRoot / "vault-src"
    createDir(src)
    discard writeBody(src, uapCert(KeyA, "src/x.nim", "f", "certGreen",
      "fixture_theorem", %["propext"]))
    writeRuntimeManifest(src, @[manifestEntry("src/x.nim", "f", "certGreen", KeyB)])
    let exp = exportToDir(src, tmpRoot / "out", @["src/x.nim::f"])
    check exp.ok
    let ver = verifyBundle(tmpRoot / "out" / "vault",
      declaredTargets = @["src/x.nim::other"])
    check not ver.ok
    check ver.reasonCode == "CERT_SCOPE_MISMATCH"

  test "scoped verify: declared target not a verified claim → CERT_STATUS_MISMATCH":
    let src = makeGoldenVault(tmpRoot)
    let exp = exportToDir(src, tmpRoot / "out", @["src/x.nim::g"])
    check exp.ok
    let ver = verifyBundle(tmpRoot / "out" / "vault",
      declaredTargets = @["src/x.nim::g"])
    check not ver.ok
    check ver.reasonCode == "CERT_STATUS_MISMATCH"

  test "scoped verify: declared body removed with consistent inventory → CERT_BODY_MISSING":
    let src = tmpRoot / "vault-src"
    createDir(src)
    discard writeBody(src, uapCert(KeyA, "src/x.nim", "f", "certGreen",
      "fixture_theorem", %["propext"]))
    writeRuntimeManifest(src, @[manifestEntry("src/x.nim", "f", "certGreen", KeyB)])
    let exp = exportToDir(src, tmpRoot / "out", @["src/x.nim::f"])
    check exp.ok
    let bundle = tmpRoot / "out" / "vault"
    removeFile(bundle / (KeyA & ".json"))
    removeInventoryLine(bundle, KeyA & ".json")
    var man = loadManifest(bundle)
    let e = man["entries"][0]
    e["certificateFile"] = newJNull()
    e["certificateSha256"] = newJNull()
    e["recomputedStatus"] = newJNull()
    e["theoremIdentity"] = newJNull()
    e["axiomObservation"]["status"] = %"not-applicable"
    e["axiomObservation"]["names"] = newJNull()
    saveManifest(bundle, man)
    let ver = verifyBundle(bundle, declaredTargets = @["src/x.nim::f"])
    check not ver.ok
    check ver.reasonCode == "CERT_BODY_MISSING"

  test "CLI: --proposals drives scope; malformed proposals exits 2":
    let src = tmpRoot / "vault-src"
    createDir(src)
    discard writeBody(src, uapCert(KeyA, "src/x.nim", "f", "certGreen",
      "fixture_theorem", %["propext"]))
    writeRuntimeManifest(src, @[manifestEntry("src/x.nim", "f", "certGreen", KeyB)])
    let props = tmpRoot / "proposals.json"
    writeFile(props, """{"schema_version":2,"propositions":[{"target":"src/x.nim::f"}]}""")
    check runCertExportCli(@["--vault", src, "--out", tmpRoot / "out",
      "--proposals", props, "--json"]) == 0
    check runCertVerifyExportCli(@["--bundle", tmpRoot / "out" / "vault",
      "--proposals", props, "--json"]) == 0
    writeFile(props, """{"schema_version":2,"propositions":[]}""")
    check runCertExportCli(@["--vault", src, "--out", tmpRoot / "out2",
      "--proposals", props, "--json"]) == 2

  test "CLI: export exits 0 on PASS; usage error exits 2":
    let src = makeGoldenVault(tmpRoot)
    check runCertExportCli(@["--vault", src, "--out", tmpRoot / "out",
      "--json"]) == 0
    check runCertVerifyExportCli(@["--bundle", tmpRoot / "out" / "vault",
      "--json"]) == 0
    check runCertExportCli(@["--json"]) == 2
    check runCertVerifyExportCli(@[]) == 2