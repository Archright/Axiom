import std/[json, options, os, unittest]
import core/crypto/hash_kernel
import verification/[cert_export, cert_writer, llbc_to_canonical,
                     rust_input_contract, rust_rust_pipeline, vault_manifest]

suite "Rust lane vault manifest (#247) and pre-parsed outcome (#229)":
  test "#229: rustSubjectOutcomeParsed matches rustSubjectOutcome on fixture LLBC":
    let llbcPath = "tests/fixtures/rust/axiom_u64_probe/axiom_u64_probe.llbc"
    let subjectRoot = "tests/fixtures/rust/axiom_u64_probe"
    if not fileExists(llbcPath):
      skip()
    else:
      let llbcText = readFile(llbcPath)
      let parsed = parseJson(llbcText)
      let names = llbcFunDeclNamePaths(parsed)
      check names.len > 0
      let target = names[0].fullName
      let contract = rustSubjectInputContract(parsed, subjectRoot, "")
      let direct = rustSubjectOutcome(llbcText, target, subjectRoot = subjectRoot)
      let cached = rustSubjectOutcomeParsed(parsed, contract, target)
      check cached.producer.ok == direct.producer.ok
      check cached.agreement.verdict == direct.agreement.verdict
      check cached.agreement.nimDigest == direct.agreement.nimDigest

  test "#247: merging issued Rust certificate into vault manifest enables cert_export":
    let tmp = getTempDir() / ("ax_247_" & $getCurrentProcessId())
    let vaultDir = tmp / "vault"
    let outDir = tmp / "export"
    createDir(vaultDir)
    try:
      let irHash = sha256Hex("rust-lane-247-ir")
      let modulePath = "src/lib.rs"
      let fnName = "probe_crate::add_u8"
      let certBody = %*{
        "modulePath": modulePath,
        "functionName": fnName,
        "status": "certLeanVerified",
        "verificationTier": "lean-verified",
        "solverStatus": "",
        "kernel": true,
        "solverMeta": {"leanCompilerVerified": true, "z3Executed": false},
        "irHash": irHash,
        "leanSource": "theorem add_u8_post : True := trivial",
        "leanProposition": "True",
        "axiomsUsed": ["propext"]
      }
      writeFile(vaultDir / (irHash & ".json"), $certBody)
      let manifestPath = vaultDir / "manifest.json"
      var m = loadManifest(manifestPath)
      m.mergeResult(
        certBody.getOrDefault("functionName").getStr(),
        certBody.getOrDefault("modulePath").getStr(),
        irHash,
        certBody.getOrDefault("status").getStr(),
        "smLean")
      m.atomicWriteManifest(manifestPath)
      check fileExists(manifestPath)
      let exp = exportToDir(vaultDir, outDir)
      if not exp.ok:
        echo "EXPORT FAIL: codes=", exp.codes, " detail=", exp.detail
      check exp.ok
      check exp.certCount == 1
      check exp.codes.len == 0
    finally:
      removeDir(tmp)
