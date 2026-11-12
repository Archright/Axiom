import std/[json, os, strutils, unittest, options]
import ../../src/verification/cert_writer
import ../../src/core/trusted/fingerprint_generator
import ../../src/core/trusted/trust_commit
import ../../src/core/trusted/axiom_pragmas
import ../../src/verification/certificate_identity
import ../../src/core/crypto/hash_kernel
import ../../src/core/proof/source_fingerprint
import ../../src/core/types/verification_tier
import ../../src/verification/cert_vault_role
import ../../src/verification/cert_promotion
import ../../src/verification/certificate_verifier
import ../../src/verification/certificate_manager
import ../../src/core/proof/proof_integrity
import ../../src/core/utils/repo_root
import ../../src/core/results
import ../../src/verification/obligation/kernel_acceptance_authority
import ../../src/verification/obligation/lean_kernel_boundary

## START gate block C — certificate lifecycle (plan: yelena-belova-constantine-jean-grey.md).
##
## Contract under test (v1 productization contract §6b/§7a + START DoD):
##   generate → validate → persist (disk) → reload → revalidate → identical digest.
##
## This file executes the REAL writer (writeCertificateFromUapResult), the REAL
## manager hard-gate (writeCertificate / validateCertGreenWritable), the REAL
## trust journal (commitVerification / readCommit), the REAL closure verifier
## (verifyCertificateClosure), and the REAL VKD admission predicate
## (proof_integrity.isVkdAdmissible). No stubs, no mocked I/O.
##
## Writer and verifier now share ONE canonical identity implementation
## (certificate_identity.nim: V3IdentityState + compV3Identity + canonicalV3FieldKeys).
## The identityDigest is computed from the FINAL v3 state after any status
## demotion, and the verifier recomputes it via v3IdentityFromJson after
## isDeepVerified — so persist→reload→revalidate closes (ccsPass). Tests cover
## the contract closure (1-2), the shared single-source alignment (3), and
## tamper-mutation integrity (4). Test 5 proves certGreen admission + VKD path.

suite "START-C — v3 certificate lifecycle (generate → validate → persist → reload → revalidate)":

  # ── hermetic fixture (kernel function registered in-process) ──────────────
  const fixtureModule = "module_lifecycle_test.nim"
  const fixtureFunc = "probeLifecycleKernel"
  const fixtureSource = "proc probeLifecycleKernel(x: int): int = x + 1"
  const fixtureIrHash = "ir-hash-lifecycle-001"
  const fixtureLeanProp = "(assert true)"
  const fixtureSmt = "(assert true)"

  proc withRegisteredKernel(funcName: string) =
    ## Register a kernel-scope member so writer lookupIsKernel() == true.
    registerAxiom(funcName, "ir:" & funcName, "", "", "module_lifecycle_test.nim",
                  isKern = true, irHash = fixtureIrHash)
    initRegistryLookup()

  proc generateLifecycleCert(tmpDir: string): string =
    ## Run the real writer (dual evidence → vtDual → certGreen claim).
    ## Returns the emitted cert file path.
    writeFile(tmpDir / fixtureModule, fixtureSource)
    withRegisteredKernel(fixtureFunc)
    var logLines: seq[string] = @[]
    setPromotionActive()
    defer: clearPromotionActive()
    let written = writeCertificateFromUapResult(
      tmpDir, fixtureModule, fixtureFunc, fixtureSource,
      leanKernelVerified = true,
      smtlib2 = fixtureSmt,
      solverStatus = "unsat",
      logLines = logLines,
      vacuityProven = true,
      irHash = fixtureIrHash,
      leanProposition = fixtureLeanProp)
    check written
    let certPath = tmpDir / (fixtureIrHash & ".json")
    check fileExists(certPath)
    certPath

  template withHermeticJournalRoot(tmpDir: string; body: untyped) =
    ## cert_lifecycle_contracts.md §5 dual-root rule: the closure's journal leg
    ## (trustCommitId) ALWAYS resolves at the product repo root, while the
    ## source-staleness leg reads `projectRoot`. Inject this test's tmpDir as
    ## the product root (AXIOM_ROOT) so the minted journal under tmpDir is the
    ## one the closure resolves — the same idiom as cert_reconcile_test.nim.
    ## The writer side is unaffected: repoRootForPath re-verifies the
    ## .axiom_root anchor, which a bare tmpDir does not carry, so the journal
    ## is still minted under tmpDir.
    let origAxiomRoot = getEnv("AXIOM_ROOT", "")
    putEnv("AXIOM_ROOT", tmpDir)
    try:
      body
    finally:
      if origAxiomRoot.len > 0: putEnv("AXIOM_ROOT", origAxiomRoot)
      else: delEnv("AXIOM_ROOT")

  test "R4 required fields present + identity-digest stable across persist→reload":
    let tmpDir = getTempDir() / "ax_lifecycle_fields_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      let certPath = generateLifecycleCert(tmpDir)
      let certJson = parseFile(certPath)
      # policy r4.requiredFields + contract §7a identityDigest
      for required in ["claim", "attestation", "inputHash", "provenance",
                       "toolchainIdentity", "solverInvocation",
                       "solverInputDigest", "solverResultDigest", "identityDigest"]:
        check certJson.hasKey(required)
        check certJson[required].kind != JNull
      check certJson["claim"]["type"].getStr() == "verification"
      check certJson["claim"]["status"].getStr() == "certGreen"
      check certJson["attestation"]["journalRef"].getStr() ==
            certJson["provenance"]["journalCommitId"].getStr()
      check certJson["identityDigest"].getStr() ==
            certJson["provenance"]["certificateDigest"].getStr()
      check certJson["trustCommitId"].getStr().len > 0
      # journal record physically exists (replay-bound artifact)
      let journalFile = tmpDir / "data" / "trusted" / "journal" /
                        (certJson["trustCommitId"].getStr() & ".json")
      check fileExists(journalFile)
      # reload again → identical digest (persist/reload half of lifecycle)
      let reloaded = parseFile(certPath)
      check reloaded["identityDigest"].getStr() == certJson["identityDigest"].getStr()
      # writer-consistency: stored digest == digest recomputed from the reloaded
      # fields with the writer's own v3 formula (fields in cert_writer.nim:347-361)
      let wFields = @[
        reloaded["schemaVersion"].getStr(),
        reloaded["modulePath"].getStr(),
        reloaded["functionName"].getStr(),
        reloaded["sourceHash"].getStr(),
        reloaded["irHash"].getStr(),
        reloaded["leanProposition"].getStr(),
        reloaded["solverStatus"].getStr(),
        reloaded["status"].getStr(),
        reloaded["winningStrategy"].getStr(),
        reloaded["inputHash"].getStr(),
        reloaded["solverInputDigest"].getStr(),
        reloaded["solverResultDigest"].getStr()
      ]
      check computeCertificateIdentity(wFields) ==
            reloaded["identityDigest"].getStr()
    finally:
      removeDir(tmpDir)

  test "REVALIDATE (verifyCertificateClosure) — contract: ccsPass (STARTC gate)" &
      " — writer-aligned canonical identity, persist→reload→revalidate closes":
    let tmpDir = getTempDir() / "ax_lifecycle_closure_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let certPath = generateLifecycleCert(tmpDir)
        let res = verifyCertificateClosure(certPath, tmpDir)
        # Full lifecycle closes only if the canonical revalidate returns ccsPass.
        check res.status == ccsPass
    finally:
      removeDir(tmpDir)

  test "identity single-source: writer, verifier, and stored digest agree (START-D)":
    let tmpDir = getTempDir() / "ax_lifecycle_diag_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let parserOut = generateLifecycleCert(tmpDir)
        let certJson = parseFile(parserOut)
        # closure passes (shared canonical recompute)
        let res = verifyCertificateClosure(parserOut, tmpDir)
        check res.status == ccsPass
        # verifier's canonical recompute from the JSON and a numeric writer-side
        # projection over the same ordered fields both equal the stored digest.
        check v3IdentityFromJson(certJson) == certJson["identityDigest"].getStr()
        check computeCertificateIdentity(@[
          certJson["schemaVersion"].getStr(),
          certJson["modulePath"].getStr(),
          certJson["functionName"].getStr(),
          certJson["sourceHash"].getStr(),
          certJson["irHash"].getStr(),
          certJson["leanProposition"].getStr(),
          certJson["solverStatus"].getStr(),
          certJson["status"].getStr(),
          certJson["winningStrategy"].getStr(),
          certJson["inputHash"].getStr(),
          certJson["solverInputDigest"].getStr(),
          certJson["solverResultDigest"].getStr()
        ]) == certJson["identityDigest"].getStr()
    finally:
      removeDir(tmpDir)

  test "mutation: tampering any of the 12 identity fields breaks the closure":
    let tmpDir = getTempDir() / "ax_lifecycle_mut_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      withHermeticJournalRoot(tmpDir):
        let certPath = generateLifecycleCert(tmpDir)
        # baseline: the untampered cert passes
        let base = verifyCertificateClosure(certPath, tmpDir)
        check base.status == ccsPass
        for key in canonicalV3FieldKeys:
          let orig = parseFile(certPath)
          orig[key] = %("MUTATED-" & key)
          let mutatedPath = tmpDir / ("mut_" & key & ".json")
          writeFile(mutatedPath, $orig)
          let r = verifyCertificateClosure(mutatedPath, tmpDir)
          # Identity-participating tamper must fail closed: either the deep-verify
          # stage (sourceHash/status/irHash) or the identity recompute rejects it.
          check r.status != ccsPass
    finally:
      removeDir(tmpDir)

  test "certGreen path exists: writer + manager hard-gate + isVkdAdmissible admit a dual cert":
    ## Real VKS module: src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers
    ## (present in data/verification_scope.lock kernel_symbols; NOT exempt).
    ## The certificate evidence (unsat ∧ lean-compiler-verified) is exactly what
    ## isVkdAdmissible declares admissible (vtDual → certGreen) per §6b.
    let tmpDir = getTempDir() / "ax_lifecycle_green_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      let repoRoot = resolveRepoRoot()
      let modulePath = "src/core/orchestrator/orchestrator_api.nim"
      let functionName = "normalizeMaxWorkers"
      var sourceCode = ""
      try:
        sourceCode = readFile(repoRoot / modulePath)
      except CatchableError:
        check false  # real module must be readable
      check sourceCode.len > 0
      withRegisteredKernel(functionName)
      var logLines: seq[string] = @[]
      setPromotionActive()
      defer: clearPromotionActive()
      # kernel=true authority: since DECISION-0630 the persisted kernel flag can
      # only come from a genuine Lean kernel acceptance (bindReceipt is the sole
      # KAA creation path — the static registry is compatibility metadata, so
      # registryIsKernel alone can never mint a certGreen dual cert). Bind a
      # REAL canonical-sink receipt (same discipline as test_d2_golden.nim /
      # test_base36_contract_policy.nim) and issue through it.
      let kernelReceipt = canonicalLeanKernelCheck(
        "theorem probeLifecycleGreenKernel : True := trivial\n")
      check kernelReceipt.isOk()
      let kaa = bindReceipt(kernelReceipt.get())
      check kaa.isOk()
      let ok = writeCertificateFromUapResult(
        tmpDir, modulePath, functionName, sourceCode,
        leanKernelVerified = true,
        smtlib2 = fixtureSmt,
        solverStatus = "unsat",
        logLines = logLines,
        vacuityProven = true,
        irHash = "ir-hash-green-001",
        leanProposition = fixtureLeanProp,
        kaa = some(kaa.get()))
      check ok
      let certJson = parseFile(tmpDir / "ir-hash-green-001.json")
      check certJson["status"].getStr() == "certGreen"
      check certJson["kernel"].getBool() == true
      # manager hard-gate accepts a certGreen with dual evidence
      check validateCertGreenWritable(certJson)
      let gateWrite = writeCertificate(tmpDir / "hardgate_ok.json", certJson)
      check gateWrite
      check fileExists(tmpDir / "hardgate_ok.json")
      # VKD admission predicate admits it against the REAL scope lock
      let scope = loadKernelScope(repoRoot / "data" / "verification_scope.lock",
                                  failClosed = true)
      check scope.kernelTotal == 40
      check scope.vksTotal == 23
      let entry = RuntimeAxiomEntry(
        name: functionName,
        sourcePath: modulePath,
        isKernel: true,
        irHash: "ir-hash-green-001")
      let verdict = isVkdAdmissible(certJson, entry, scope,
                                    certificate_verifier.isDeepVerified)
      check verdict == varAdmit
    finally:
      removeDir(tmpDir)