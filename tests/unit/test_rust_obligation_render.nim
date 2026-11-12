## Rust extraction-bounded claim gate tests (feat/rust-subject-v1, Phase 2-E).
##
## Contract under test (src/verification/rust_obligation_render.nim +
## the cert_writer mint gate):
##   1. Template family (pure) — the closed renderer family classifies;
##      free-composed sources (foreign tactic, extra declaration, sorry) do
##      NOT classify and are refused by the gate.
##   2. Co-binding (pure) — templateHash / rustCanonicalDigest↔irHash /
##      obligationDigest / proposition↔source must all co-bind; any single
##      tamper is refused with the precise reason.
##   3. Extractor identity (measured) — the recorded identity must equal the
##      CURRENT pinned reference-extractor identity at mint; a forged or
##      swapped one is refused (kernel_acceptance_authority.nim mint-time
##      fingerprint refusal pattern).
##   4. Mint time (real Lean kernel, skipped when lake is absent): a faithful
##      claim mints through the EXISTING writer; forged claims are refused
##      BEFORE any certificate is written.

import std/[json, os, options, strutils, unittest]

import core/crypto/hash_kernel
import core/results
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import verification/cert_writer
import verification/llbc_to_canonical
import verification/obligation/canonical_verification
import verification/obligation/kernel_acceptance_authority
import verification/obligation/lean_evidence
import verification/obligation/lean_kernel_boundary
import verification/rust_obligation_render
import verification/rust_rust_pipeline

const ProbePath = "/tmp/axiom-rust-probe/axiom_rust_probe.llbc"

let probePresent = fileExists(ProbePath)
let lakePresent = findExe("lake").len > 0

if not probePresent:
  echo "SKIP: real probe not found at " & ProbePath &
    " — probe-dependent suites skip (explicit skip, not a failure)"
if not lakePresent:
  echo "SKIP: lake not on PATH — mint-time suite skips (explicit skip, not a failure)"

proc claimFor(leanSource, canonicalDigest: string): RustBoundedClaim =
  ## The claim the real lane measures for (leanSource, canonicalDigest) —
  ## the gate input assembled exactly as rust_rust_pipeline assembles it.
  let proposition = rustPropositionFromSource(leanSource)
  RustBoundedClaim(
    templateHash: rustTemplateSkeletonHash(leanSource),
    rustCanonicalDigest: canonicalDigest,
    obligationDigest: sha256Hex(
      canonicalDigest & "|" & proposition & "|" & leanSource),
    extractorIdentity: rustExtractorIdentityDigest())

# ─── Suite 1: closed template family + pure gate refusals (always runs) ─────

const FamilySource = """def add_u8 : Int → Int → Int :=
  fun a b => (a + b)

theorem add_u8_post :
  ∀ (a : Int) (b : Int), ((0 ≤ a) ∧ (a < 256)) → ((a + b) < 256) → ((add_u8 a b) = (a + b)) := by
  intro a b h0 h1
  unfold add_u8
  omega
"""

const FamilyIrHash = "8fd2dae5215d11192e40e753a5e917bc4c8504abfedf2328f98fa409f218fc87"

suite "rust_obligation_render — closed template family (pure)":

  test "the family source classifies; its skeleton hash is an allowlist member":
    let skeleton = rustTemplateSkeleton(FamilySource)
    check skeleton == "def;fun;thm;prop;intro;unfold;omega"
    let h = rustTemplateSkeletonHash(FamilySource)
    check h.len == 64
    check h in rustBoundedTemplateFamilyHashes()
    check rustBoundedTemplateFamilyHashes().len == 4
    check rustTemplateInFamily(FamilySource)

  test "free-composed sources do NOT classify into the family":
    # a foreign closing tactic
    let simp = FamilySource.replace("  omega\n", "  simp\n")
    check rustTemplateSkeleton(simp) == ""
    check not rustTemplateInFamily(simp)
    # an extra declaration
    let extra = FamilySource & "\ntheorem smuggled : True := by trivial\n"
    check rustTemplateSkeleton(extra) == ""
    # a sorry
    let sorry = FamilySource & "  sorry\n"
    check rustTemplateSkeleton(sorry) == ""
    # an axiom line
    let axiom = "axiom smuggled_ax : False\n" & FamilySource
    check rustTemplateSkeleton(axiom) == ""
    # a renamed theorem (must be <def>_post)
    let renamed = FamilySource.replace("theorem add_u8_post :",
                                       "theorem add_u8_other :")
    check rustTemplateSkeleton(renamed) == ""

  test "proposition extraction round-trips the family source":
    check rustPropositionFromSource(FamilySource).contains(
      "(add_u8 a b) = (a + b)")
    check rustPropositionFromSource("def x : Int → Int :=\n") == ""

  test "bounded claim co-binds when every field is faithful":
    let claim = claimFor(FamilySource, FamilyIrHash)
    check rustBoundedClaimRefusal(claim, FamilyIrHash,
      rustPropositionFromSource(FamilySource), FamilySource) == ""

  test "free-composed proposition (template mismatch) is refused":
    let claim = claimFor(FamilySource, FamilyIrHash)
    let simp = FamilySource.replace("  omega\n", "  simp\n")
    check rustBoundedClaimRefusal(claim, FamilyIrHash,
      rustPropositionFromSource(FamilySource), simp)
      .contains("closed renderer template family")

  test "tampered proposition is refused (proposition ↔ source co-bind)":
    let claim = claimFor(FamilySource, FamilyIrHash)
    check rustBoundedClaimRefusal(claim, FamilyIrHash,
      "(assert true)", FamilySource)
      .contains("does not match the accepted source's proposition")

  test "wrong templateHash is refused":
    var claim = claimFor(FamilySource, FamilyIrHash)
    claim.templateHash = sha256Hex("tampered")
    check rustBoundedClaimRefusal(claim, FamilyIrHash,
      rustPropositionFromSource(FamilySource), FamilySource)
      .contains("templateHash does not match")

  test "mismatched RustCanonical digest is refused (claim ↔ irHash co-bind)":
    let claim = claimFor(FamilySource, FamilyIrHash)
    check rustBoundedClaimRefusal(claim, sha256Hex("other-extraction"),
      rustPropositionFromSource(FamilySource), FamilySource)
      .contains("rustCanonicalDigest != certificate irHash")

  test "mismatched obligation digest is refused":
    var claim = claimFor(FamilySource, FamilyIrHash)
    claim.obligationDigest = sha256Hex("tampered")
    check rustBoundedClaimRefusal(claim, FamilyIrHash,
      rustPropositionFromSource(FamilySource), FamilySource)
      .contains("obligationDigest does not co-bind")

suite "rust_obligation_render — extractor identity (measured)":

  test "the current pinned identity is measured and admits itself":
    let current = rustExtractorIdentityDigest()
    check current.startsWith("pinned|")
    check current.len == "pinned|".len + 64
    check rustExtractorIdentityRefusal(current) == ""

  test "a forged / overridden extractor identity is refused at mint":
    check rustExtractorIdentityRefusal(
      "pinned|" & sha256Hex("forged-extractor"))
      .contains("extractor identity mismatch")
    check rustExtractorIdentityRefusal("").contains("not recorded")

# ─── Suite 2: renderer on the real probe canonical (probe-guarded) ──────────

if probePresent:
  suite "rust_obligation_render — renderer over the real canonical":

    let f = parseLlbcFile(ProbePath)
    let produced = llbcFunctionToCanonical(f.root, "add_u8")
    let digest = sha256Hex("phase2e-unit-extraction-digest")
    let specAdd = irEq(irVar("result", irTypeBitVec64()),
                       irAdd(irVar("a", irTypeBitVec64()),
                             irVar("b", irTypeBitVec64())))

    test "add_u8 renders the closed family with two-origin width conditions":
      check produced.ok
      let r = renderRustObligationLean(produced.canonical, digest, specAdd)
      check r.ok
      check r.leanSource.contains("def add_u8 : Int → Int → Int :=")
      check r.leanSource.contains("theorem add_u8_post :")
      check r.leanSource.contains("((0 ≤ a) ∧ (a < 256))")   # aoTypeDerived
      check r.leanSource.contains("((a + b) < 256)")          # aoCallerObligation
      check r.leanSource.endsWith("  unfold add_u8\n  omega\n")
      check r.templateHash in rustBoundedTemplateFamilyHashes()
      check rustPropositionFromSource(r.leanSource) == r.proposition
      check r.obligationDigest ==
        sha256Hex(digest & "|" & r.proposition & "|" & r.leanSource)
      check r.obligationId.len == 64
      # the two origins are distinct in the obligation identity payload
      check r.leanSource.count("(a + b) < 256") == 1

    test "a free-variable postcondition is refused (closed family, fail-closed)":
      let r = renderRustObligationLean(produced.canonical, digest,
        irEq(irVar("result", irTypeBitVec64()),
             irVar("zzz", irTypeBitVec64())))
      check not r.ok
      check r.reason.contains("bounded rendering subset")

    test "a non-64-hex canonical digest is refused":
      let r = renderRustObligationLean(produced.canonical, "short", specAdd)
      check not r.ok
      check r.reason.contains("SHA256 hex digest")

# ─── Suite 3: mint-time gate through the EXISTING writer (kernel-guarded) ───

if probePresent and lakePresent:
  suite "rust bounded-claim gate — mint time through cert_writer (real kernel)":

    let f = parseLlbcFile(ProbePath)
    let produced = llbcFunctionToCanonical(f.root, "add_u8")
    let myIrHash = sha256Hex("phase2e-mint-extraction-digest")
    let specAdd = irEq(irVar("result", irTypeBitVec64()),
                       irAdd(irVar("a", irTypeBitVec64()),
                             irVar("b", irTypeBitVec64())))
    let rendered = renderRustObligationLean(produced.canonical, myIrHash,
                                            specAdd)

    proc buildEvidence(): tuple[ok: bool; cle: CanonicalLeanEvidence] =
      ## ONE real kernel acceptance binds receipt → KAA → CLE (the existing
      ## authority chain, public entry points only). The CLE is a pure value:
      ## it is built once and re-offered to every mint in this suite.
      let kernelResult = canonicalLeanKernelCheck(rendered.leanSource,
                                                  timeoutMs = 120_000)
      check kernelResult.isOk
      if not kernelResult.isOk: return
      let receipt = kernelResult.get()
      var axioms: seq[string] = @[]
      try:
        let probeSource = rendered.leanSource & "\n#print axioms " &
          receipt.receiptTheoremIdentity & "\n"
        let (probeOutput, _) = runLeanProbe(probeSource, "_axioms", 120_000)
        axioms = parseAxiomProfile(probeOutput)
      except CatchableError:
        discard # axiom:best-effort(ioboundary catch) observational probe only
      let kaaResult = bindReceipt(receipt, axioms,
        scanSorryMarkers(rendered.leanSource,
                         receipt.receiptKernelObservation))
      check kaaResult.isOk
      if not kaaResult.isOk: return
      let contractDigest = rustLaneExecutionContractDigest(
        sha256Hex(rendered.leanSource))
      let cle = newCanonicalLeanEvidence(
        obligationId = rendered.obligationId,
        proposition = rendered.proposition,
        leanSource = rendered.leanSource,
        kaa = kaaResult.get(),
        toolchainFingerprint = receipt.receiptToolchainFingerprint,
        executionContractDigest = contractDigest)
      check cle.isOk
      if not cle.isOk: return
      (ok: true, cle: cle.get())

    proc mintWith(claim: RustBoundedClaim; proposition: string;
                  cle: CanonicalLeanEvidence):
        tuple[ok: bool; emitted: bool; log: string] =
      var logLines: seq[string] = @[]
      let certDir = getTempDir() / ("ax_rust_gate_" & $getCurrentProcessId() &
        "_" & claim.obligationDigest[0 ..< 8])
      createDir(certDir)
      let okWrite = writeCertificateFromUapResult(
        certDir, "subject.rs", "add_u8",
        "pub fn add_u8(a: u8, b: u8) -> u8 { a + b }",
        leanKernelVerified = false,
        smtlib2 = "",
        solverStatus = "",
        logLines = logLines,
        irHash = myIrHash,
        leanProposition = proposition,
        kaa = some(cle.kaa),
        evidence = some(cle),
        rustBoundedClaim = some(claim))
      let emitted = fileExists(certDir / (myIrHash & ".json"))
      check (not okWrite) or emitted   # a written result always emitted a file
      if okWrite:
        # the honest success shape (lexicon reason, kernel from the KAA)
        let cert = parseFile(certDir / (myIrHash & ".json"))
        check cert["status"].getStr() == "certLeanVerified"
        check cert["reason"].getStr() == "uap-lean-verified"
        check cert["kernel"].getBool() == true
      try:
        removeDir(certDir)
      except CatchableError:
        discard # axiom:best-effort(ioboundary catch) temp cleanup
      (ok: okWrite, emitted: emitted, log: logLines.join("\n"))

    test "faithful claim MINTS through the existing writer (accept case)":
      check rendered.ok
      let built = buildEvidence()
      check built.ok
      let r = mintWith(claimFor(rendered.leanSource, myIrHash),
                       rendered.proposition, built.cle)
      check r.ok
      check r.emitted

    test "forged extractor identity → refused BEFORE any certificate is written":
      check rendered.ok
      let built = buildEvidence()
      check built.ok
      var claim = claimFor(rendered.leanSource, myIrHash)
      claim.extractorIdentity = "pinned|" & sha256Hex("forged-extractor")
      let r = mintWith(claim, rendered.proposition, built.cle)
      check not r.ok
      check not r.emitted
      check r.log.contains("Rust bounded-claim gate refused issuance")
      check r.log.contains("extractor identity mismatch")

    test "free-composed proposition at mint → refused (co-binding)":
      check rendered.ok
      let built = buildEvidence()
      check built.ok
      let r = mintWith(claimFor(rendered.leanSource, myIrHash),
                       "(assert true)", built.cle)
      check not r.ok
      check not r.emitted
      check r.log.contains("Rust bounded-claim gate refused issuance")
      check r.log.contains("does not match the accepted source's proposition")
