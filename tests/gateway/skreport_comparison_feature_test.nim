## Cross-path skReport reproduction comparison — business gateway feature test
## for the §6c verdict rules (docs/spec/productization_contract.md, v2).
##
## WHAT IS UNDER TEST: `core/utils/skreport_comparison.nim::compareSkReports` —
## the single §6c implementation. The scenarios are the §6c proof table:
##   - v2 RELOCATION POSITIVE: the MEASURED serde-json-claim-2026-10-31 d1/d2
##     shape (everything equal except the absolute path embedded inside
##     targets[0].reason — state-dir name + charon-target build hash,
##     llbc_quirks.md Q10) bound by the v2 production-time sidecar —
##     production-binding digests recompute, the structured rejection records
##     agree, the raw reasons differ ONLY by the recorded offending path
##     (skeleton digests match) → EQUAL, with BOTH raw reason strings
##     preserved verbatim in the record
##   - the SAME displaced shape WITHOUT production-time rejection evidence →
##     unknown (the v1 measurement judgment — never equal)
##   - negative controls: source / claim / scope / toolchain each changed →
##     not_equal; error-kind change (status flip) → not_equal; a DIFFERENT
##     offending file (content digest or index changed) → identity
##     not_equal and NO reason promotion
##   - fail-closed: absent sidecar; payload without identityBundleDigest;
##     tampered binding (digest does not recompute); missing identity key;
##     claim.symbol not binding targets[0].name; multi-target report;
##     rawPath not contained in its own leaf; skeleton recompute mismatch;
##     sidecar schemaVersion violation; digest-format violations;
##     measured-anchor divergence (not_equal) and gap (unknown)
##   - volatile-key-only difference (timeoutCount) → equal (the §6 wall-clock
##     separation must hold for skReports too)
##   - terminal precedence: not_equal > unknown > equal
##
## Malicious/malformed inputs (2026-11-01 security review — all fail closed,
## the contract's "malformed → unknown" failure semantics): flat mid-scalar
## identity trees, non-string reason trees, forged/truncated digests,
## non-rust or absent subjectLane.
##
## equal is a CONDITIONAL verdict: production-time measured, digest-chained,
## re-verifiable — the fixtures build the binding exactly the way the lane
## does (identityBindingDigest + payloadSha256 over the canonical forms), so
## a green equal here proves the §6c v2 rule chain end-to-end at the unit
## level; the LIVE acceptance is the two-checkout ax prove campaign.
##
## The lane's own report/sidecar production authority is NOT touched: this
## suite spawns no process and reads no state — the payloads are in-memory
## fixtures shaped like the measured lane report (schemaVersion
## axiom.report.v1, subjectLane rust, charon block, one target, summary).

import std/[unittest, json, strutils]

import core/crypto/hash_kernel
import core/utils/canonical_projection
import core/utils/constants
import core/utils/skreport_comparison

const d1Path = "/home/u/Axiom4/exp/state_d1/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/211aa9d180883da9/out/private.rs"
const d2Path = "/home/u/Axiom4/exp/state_d2/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/8b65d3d27583c0f0/out/private.rs"
const d1Reason = "producer: LLBC files table pre-validation failed: files[1]: absolute path '" & d1Path & "' (subject-relative POSIX path required)"
const d2Reason = "producer: LLBC files table pre-validation failed: files[1]: absolute path '" & d2Path & "' (subject-relative POSIX path required)"
## The MEASURED offending-content identity: identical across the three cold
## runs d1/d2/d3 (sha256sum over the preserved run state, 2026-10-31).
const measuredContentSha = "30c7e046bfa6c6cf17498e5dac35232b89cb62a2116ba976bfd749bdc763c143"

proc lanePayload(targetReason: string; name = "axiom_rust_probe::add_u8";
                 status = "unknown"; timeoutCount = 0;
                 charonReason = ""): JsonNode =
  ## A measured-shape rust lane report (one target — the certified §6c scope).
  %*{
    "schemaVersion": axiomReportSchemaVersion,
    "subjectLane": "rust",
    "charon": %*{
      "pinned": "0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)",
      "measured": "0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)",
      "ok": true,
      "reason": charonReason
    },
    "targets": %*[ %*{
      "name": name, "status": status, "reason": targetReason
    } ],
    "summary": %*{
      "verified": 0, "failedCount": 0, "timeoutCount": timeoutCount,
      "verifiedRatio": 0.0,
      "statusCounts": %*{"verified": 0, "failed": 0, "unknown": 1, "error": 0}
    }
  }

proc laneIdentity(commit = "8c535a260ce561eaab4111aafc29038eb9f77ff3";
                  moduleSha = "5cf1e7e46001fd46860c906d9c353d950632af742cbb7c154049ca22d3925073";
                  symbol = "axiom_rust_probe::add_u8";
                  specRef = "axiom.specs.json#axiom_rust_probe::add_u8";
                  rustc = "rustc-version=rustc 1.95.0 (59807616e 2026-04-14)|rustc-sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|components-sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb|channel=stable|profile=default|components=rustc,cargo,rust-std"): JsonNode =
  ## The §6c v2 identity SECTION (the sidecar's "identity" value — the
  ## location-independent production-time measurement set).
  %*{
    "subject": %*{
      "commit": commit,
      "modulePath": "src/lib.rs",
      "moduleSha256": moduleSha,
      "sourceFingerprint": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    },
    "claim": %*{
      "symbol": symbol,
      "specRef": specRef,
      "postSha256": "fb6713097920adfe83660250aa8afc51ed6733b23ae6e4bb966b568e814f6c2d"
    },
    "scope": %*{
      "rustTargetsSha256": "0c1f4abca316f8c26a247731cadc1eacc93ace2b49c2f3b55f4eb43909b6004e"
    },
    "toolchain": %*{
      "charon": "0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)",
      "rustc": rustc,
      "cargoLockSha256": "1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4",
      "cargoManifestSha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      "nim": "Nim 2.2.10"
    }
  }

proc rejectionSection(reason: string; rawPath: string;
                      contentSha = measuredContentSha;
                      index = 1): JsonNode =
  ## The identity.rejection record the lane produces for the d1/d2 shape.
  %*{
    "rule": "path_absolute",
    "index": index,
    "crateName": "serde_json",
    "contentSha256": contentSha,
    "skeletonSha256": sha256Hex(reason.replace(rawPath, axiomSkReportSkeletonMarker))
  }

proc bindingRejection(rawPath: string): JsonNode =
  ## The binding.rejection record (run-relative location data — the ONLY
  ## place a physical path may appear).
  %*{"reasonLeaf": "targets[0].reason", "rawPath": rawPath}

proc mkRun(payload: JsonNode; identity: JsonNode;
           rejection: JsonNode = nil; bindRejection: JsonNode = nil;
           sidecarVersion = axiomSkReportIdentitySchemaVersion;
           measured: JsonNode = nil; dropDigestKey = false;
           tamperDigest = false; tamperPayloadSha = false): SkReportRun =
  ## Build one run's (payload, sidecar) pair EXACTLY the way the lane does:
  ## identityBundleDigest over the binding-less sidecar embedded into the
  ## payload, binding.payloadSha256 over the canonical final payload. The
  ## tamper flags simulate post-production edits (they must fail closed).
  var p = payload.copy()
  var side = %*{
    "schemaVersion": %sidecarVersion,
    "identity": (if identity.isNil: newJNull() else: identity.copy())
  }
  if not rejection.isNil:
    side{"identity"}["rejection"] = rejection
  if not dropDigestKey:
    var digest = identityBindingDigest(side)
    if tamperDigest:
      digest = "0" & digest[1 ..< digest.len]
    p["identityBundleDigest"] = %digest
  var binding = %*{"payloadSha256": %sha256Hex(sortedCanonicalJson(p))}
  if tamperPayloadSha:
    binding["payloadSha256"] = %"1111111111111111111111111111111111111111111111111111111111111111"
  if not bindRejection.isNil:
    binding["rejection"] = bindRejection
  side["binding"] = binding
  SkReportRun(payload: p, sidecar: side, measured: measured)

proc noSidecarRun(payload: JsonNode): SkReportRun =
  ## A run whose sidecar production gapped (all-or-nothing) — the payload
  ## carries no identityBundleDigest and there is no sidecar at all.
  SkReportRun(payload: payload.copy(), sidecar: nil, measured: nil)

suite "skReport cross-path reproduction comparison (§6c v2)":

  test "v2 RELOCATION POSITIVE — measured d1/d2 displacement with production-time rejection binding is equal":
    ## Scenario: the serde-json-claim-2026-10-31 d1 vs d2 observation — same
    ## subject pin, same claim, same scope lock, same toolchains, two cold
    ## runs; the ONLY payload difference is the run-relative absolute path
    ## inside targets[0].reason. The v2 sidecar binds subject/claim/scope/
    ## toolchain at production time, digest-chains both pairs, and records
    ## the structured rejection (rule/index/crate/content/skeleton).
    ## Given two relocation runs with complete production-time evidence
    ## When I compare them
    ## Then the verdict is equal — every axis — and the record carries BOTH
    ## raw reason strings verbatim (originals are never rewritten)
    let left = mkRun(lanePayload(d1Reason), laneIdentity(),
                     rejectionSection(d1Reason, d1Path),
                     bindingRejection(d1Path))
    let right = mkRun(lanePayload(d2Reason), laneIdentity(),
                      rejectionSection(d2Reason, d2Path),
                      bindingRejection(d2Path))
    let record = compareSkReports(left, right)
    check record{"schemaVersion"}.getStr() == axiomSkReportComparisonSchemaVersion
    check record{"verdict"}.getStr() == "equal"
    check record{"axes"}{"identity"}.getStr() == "equal"
    check record{"axes"}{"structure"}.getStr() == "equal"
    check record{"axes"}{"reason"}.getStr() == "equal"
    # 원본 reason 무재작성: the record quotes both raw strings verbatim.
    check record{"reasons"}{"left"}.elems[1].getStr() == d1Reason
    check record{"reasons"}{"right"}.elems[1].getStr() == d2Reason
    # the promotion note is mechanical and audit-quoted
    var promoted = false
    for n in record{"notes"}.elems:
      if n.getStr().find("producer-recorded offending path") >= 0:
        promoted = true
    check promoted

  test "identical payloads and identity are equal (plain positive)":
    let payload = lanePayload("out-of-subset grammar (fail-closed): signature Ref input")
    let record = compareSkReports(
      mkRun(payload, laneIdentity()), mkRun(payload, laneIdentity()))
    check record{"verdict"}.getStr() == "equal"
    check record{"left"}{"payloadDigest"}.getStr() ==
          record{"right"}{"payloadDigest"}.getStr()
    check canonicalProjectionHash(stripVolatile(payload)) ==
          canonicalProjectionHash(stripVolatile(payload))

  test "displaced reason WITHOUT rejection evidence stays unknown (v1 judgment preserved)":
    ## The v2 promotion is evidence-bound: identical sidecars that carry NO
    ## structured rejection record must not let the displaced reasons equal.
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity()),
      mkRun(lanePayload(d2Reason), laneIdentity()))
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"identity"}.getStr() == "equal"
    check record{"axes"}{"structure"}.getStr() == "equal"
    check record{"axes"}{"reason"}.getStr() == "unknown"
    check record{"reasons"}{"left"}.elems[1].getStr() == d1Reason
    check record{"reasons"}{"right"}.elems[1].getStr() == d2Reason
    check canonicalProjectionHash(stripVolatile(mkRun(lanePayload(d1Reason),
      laneIdentity()).payload)) != canonicalProjectionHash(stripVolatile(
      mkRun(lanePayload(d2Reason), laneIdentity()).payload))

  test "negative control — different offending FILE (content digest) is not_equal with no reason promotion":
    ## The relocation evidence binds the offending file's CONTENT identity: a
    ## different generated file must never ride the promotion path.
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity(),
            rejectionSection(d1Reason, d1Path), bindingRejection(d1Path)),
      mkRun(lanePayload(d2Reason), laneIdentity(),
            rejectionSection(d2Reason, d2Path,
              contentSha = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
            bindingRejection(d2Path)))
    check record{"verdict"}.getStr() == "not_equal"
    check record{"axes"}{"identity"}.getStr() == "not_equal"
    check record{"axes"}{"reason"}.getStr() == "unknown"

  test "negative control — different offending table position (index) is not_equal":
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity(),
            rejectionSection(d1Reason, d1Path), bindingRejection(d1Path)),
      mkRun(lanePayload(d2Reason), laneIdentity(),
            rejectionSection(d2Reason, d2Path, index = 2),
            bindingRejection(d2Path)))
    check record{"verdict"}.getStr() == "not_equal"
    check record{"axes"}{"identity"}.getStr() == "not_equal"

  test "fail-closed — rawPath not contained in its own leaf gives no promotion":
    ## A fabricated binding whose recorded path is not in the reason: the
    ## skeleton check cannot pass (no promotion), and the misdescribing
    ## rejection record itself diverges from the other side's — the honest
    ## verdict is not_equal (refutation-class), never equal, never unknown
    ## dressed as equality.
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity(),
            rejectionSection(d1Reason, d2Path),   # wrong path recorded
            bindingRejection(d2Path)),
      mkRun(lanePayload(d2Reason), laneIdentity(),
            rejectionSection(d2Reason, d2Path), bindingRejection(d2Path)))
    check record{"verdict"}.getStr() == "not_equal"
    check record{"axes"}{"identity"}.getStr() == "not_equal"
    check record{"axes"}{"reason"}.getStr() == "unknown"

  test "fail-closed — skeleton recompute mismatch gives no promotion":
    ## The recorded skeleton digest is recomputed from the leaf and the
    ## recorded path; a mismatch means the record does not describe THIS
    ## leaf — the forged record diverges from the honest side's record, so
    ## the verdict is not_equal (identity) and the reason stays unpromoted.
    var forged = rejectionSection(d1Reason, d1Path)
    forged{"skeletonSha256"} = %"2222222222222222222222222222222222222222222222222222222222222222"
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity(), forged, bindingRejection(d1Path)),
      mkRun(lanePayload(d2Reason), laneIdentity(),
            rejectionSection(d2Reason, d2Path), bindingRejection(d2Path)))
    check record{"verdict"}.getStr() == "not_equal"
    check record{"axes"}{"identity"}.getStr() == "not_equal"
    check record{"axes"}{"reason"}.getStr() == "unknown"

  test "fail-closed — absent sidecar is unknown (all-or-nothing gap)":
    let record = compareSkReports(
      noSidecarRun(lanePayload(d1Reason)),
      noSidecarRun(lanePayload(d2Reason)))
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"identity"}.getStr() == "unknown"

  test "fail-closed — payload without identityBundleDigest is unknown":
    let left = mkRun(lanePayload(d1Reason), laneIdentity())
    let right = mkRun(lanePayload(d2Reason), laneIdentity(), dropDigestKey = true)
    check right.payload{"identityBundleDigest"}.isNil
    let record = compareSkReports(left, right)
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"identity"}.getStr() == "unknown"

  test "fail-closed — tampered identityBundleDigest does not recompute":
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity(), tamperDigest = true),
      mkRun(lanePayload(d2Reason), laneIdentity()))
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"identity"}.getStr() == "unknown"

  test "fail-closed — tampered binding.payloadSha256 does not recompute":
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity(), tamperPayloadSha = true),
      mkRun(lanePayload(d2Reason), laneIdentity()))
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"identity"}.getStr() == "unknown"

  test "re-measured anchors — matching measurement keeps equal, divergence refutes":
    ## measured is I/O-boundary material: equal anchors confirm with a note,
    ## a divergent anchor is not_equal evidence (declared vs world).
    let measuredOk = %*{"subject": %*{
      "commit": %"8c535a260ce561eaab4111aafc29038eb9f77ff3"}}
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity(), measured = measuredOk),
      mkRun(lanePayload(d1Reason), laneIdentity(), measured = measuredOk))
    check record{"verdict"}.getStr() == "equal"
    var confirmed = false
    for n in record{"notes"}.elems:
      if n.getStr().find("re-measurement") >= 0 and
          n.getStr().find("declared != re-measured") < 0:
        confirmed = true
    check confirmed
    let measuredBad = %*{"scope": %*{
      "rustTargetsSha256": %"9999999999999999999999999999999999999999999999999999999999999999"}}
    let refuted = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity(), measured = measuredBad),
      mkRun(lanePayload(d1Reason), laneIdentity()))
    check refuted{"verdict"}.getStr() == "not_equal"
    check refuted{"axes"}{"identity"}.getStr() == "not_equal"
    var namedPath = false
    for n in refuted{"notes"}.elems:
      if n.getStr().find("scope.rustTargetsSha256") >= 0:
        namedPath = true
    check namedPath

  test "negative control — subject source change is not_equal":
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity(commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
      mkRun(lanePayload(d1Reason), laneIdentity(commit = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")))
    check record{"verdict"}.getStr() == "not_equal"
    check record{"axes"}{"identity"}.getStr() == "not_equal"
    check record{"notes"}.elems[0].getStr().find("subject") >= 0

  test "negative control — claim change is not_equal":
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity()),
      mkRun(lanePayload(d1Reason), laneIdentity(symbol = "axiom_rust_probe::add_u8_mutant")))
    check record{"verdict"}.getStr() == "not_equal"
    check record{"axes"}{"identity"}.getStr() == "not_equal"

  test "negative control — scope lock change is not_equal":
    var right = laneIdentity()
    right{"scope"}{"rustTargetsSha256"} = %"1111111111111111111111111111111111111111111111111111111111111111"
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity()),
      mkRun(lanePayload(d1Reason), right))
    check record{"verdict"}.getStr() == "not_equal"
    check record{"axes"}{"identity"}.getStr() == "not_equal"

  test "negative control — toolchain change is not_equal":
    var right = laneIdentity()
    right{"toolchain"}{"charon"} = %"0.1.282 (0000000000000000000000000000000000000000)"
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity()),
      mkRun(lanePayload(d1Reason), right))
    check record{"verdict"}.getStr() == "not_equal"
    check record{"axes"}{"identity"}.getStr() == "not_equal"

  test "negative control — error-kind change (status flip) is not_equal":
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason, status = "unknown"), laneIdentity()),
      mkRun(lanePayload("spec declined by kernel; counterexample CONFIRMED: (0,0)->1!=0",
                        status = "failed"), laneIdentity()))
    check record{"verdict"}.getStr() == "not_equal"
    check record{"axes"}{"structure"}.getStr() == "not_equal"

  test "missing identity key is unknown (inputs are not assumed to carry identity)":
    var right = laneIdentity()
    right{"subject"}.delete("moduleSha256")
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity()),
      mkRun(lanePayload(d1Reason), right))
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"identity"}.getStr() == "unknown"
    check record{"notes"}.elems[0].getStr().find("subject.moduleSha256") >= 0

  test "claim.symbol not binding targets[0].name is unknown":
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason, name = "axiom_rust_probe::add_u8"),
            laneIdentity(symbol = "some_other_symbol")),
      mkRun(lanePayload(d1Reason, name = "axiom_rust_probe::add_u8"),
            laneIdentity(symbol = "some_other_symbol")))
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"identity"}.getStr() == "unknown"

  test "multi-target report is outside the certified scope (unknown)":
    var leftPayload = lanePayload(d1Reason)
    var rightPayload = lanePayload(d2Reason)
    let extra = %*{"name": "axiom_rust_probe::add_u8_mutant",
                   "status": "unknown", "reason": ""}
    leftPayload{"targets"}.add(extra)
    rightPayload{"targets"}.add(copy(extra))
    let record = compareSkReports(
      mkRun(leftPayload, laneIdentity()), mkRun(rightPayload, laneIdentity()))
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"structure"}.getStr() == "unknown"

  test "volatile-key-only difference (timeoutCount) stays equal":
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason, timeoutCount = 0), laneIdentity()),
      mkRun(lanePayload(d1Reason, timeoutCount = 1), laneIdentity()))
    check record{"verdict"}.getStr() == "equal"

  test "terminal precedence — not_equal beats reason unknown":
    let record = compareSkReports(
      mkRun(lanePayload(d1Reason), laneIdentity(commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
      mkRun(lanePayload(d2Reason), laneIdentity()))
    check record{"verdict"}.getStr() == "not_equal"
    check record{"axes"}{"identity"}.getStr() == "not_equal"
    check record{"axes"}{"reason"}.getStr() == "unknown"

  test "non-v1 payload document is unknown":
    let bogus = %*{"schemaVersion": "axiom.report.v0", "targets": []}
    let record = compareSkReports(
      mkRun(bogus, laneIdentity()), mkRun(lanePayload(d1Reason), laneIdentity()))
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"structure"}.getStr() == "unknown"

  # ── malicious/malformed inputs (2026-11-01 security review) ─────────────

  test "malformed identity — flat mid-scalar bundle cannot reach equal":
    let flat = %*{
      "subject": "8c535a260ce561eaab4111aafc29038eb9f77ff3",
      "claim": "axiom_rust_probe::add_u8",
      "scope": "serde-json-claim",
      "toolchain": "charon 0.1.281"
    }
    let payload = lanePayload(d1Reason)
    let record = compareSkReports(
      mkRun(payload, flat), mkRun(payload, flat))
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"identity"}.getStr() == "unknown"
    check record{"notes"}.elems.len > 0

  test "malformed reason — non-string reason tree cannot reach equal":
    proc badReasonPayload(msg: string): JsonNode =
      result = lanePayload(d1Reason)
      let charon = result{"charon"}
      charon["reason"] = %*{"stage": "charon", "msg": msg}
      charon["ok"] = %false
    let record = compareSkReports(
      mkRun(badReasonPayload("timeout"), laneIdentity()),
      mkRun(badReasonPayload("panic"), laneIdentity()))
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"reason"}.getStr() == "unknown"
    check record{"axes"}{"structure"}.getStr() == "equal"

  test "malformed sidecar — schemaVersion must be the declared v2":
    block absentVersion:
      let payload = lanePayload(d1Reason)
      var side = %*{"identity": laneIdentity()}
      side["binding"] = %*{"payloadSha256": %sha256Hex(sortedCanonicalJson(payload))}
      # digest key computed over the binding-less doc for honesty
      payload["identityBundleDigest"] = %identityBindingDigest(side)
      side{"binding"}["payloadSha256"] = %sha256Hex(sortedCanonicalJson(payload))
      let record = compareSkReports(
        SkReportRun(payload: payload, sidecar: side, measured: nil),
        mkRun(lanePayload(d1Reason), laneIdentity()))
      check record{"verdict"}.getStr() == "unknown"
      check record{"axes"}{"identity"}.getStr() == "unknown"
    block unrecognizedVersion:
      let record = compareSkReports(
        mkRun(lanePayload(d1Reason), laneIdentity(),
              sidecarVersion = "axiom.skreport-identity.v3"),
        mkRun(lanePayload(d1Reason), laneIdentity()))
      check record{"verdict"}.getStr() == "unknown"
      check record{"axes"}{"identity"}.getStr() == "unknown"

  test "malformed identity — digest-typed keys must be real sha256 hex":
    var forged = laneIdentity()
    forged{"subject"}{"moduleSha256"} = %"not-actually-a-sha256-digest"
    block bothSidesForged:
      let record = compareSkReports(
        mkRun(lanePayload(d1Reason), forged), mkRun(lanePayload(d1Reason), forged))
      check record{"verdict"}.getStr() == "unknown"
      check record{"axes"}{"identity"}.getStr() == "unknown"
    block oneSidedForged:
      let record = compareSkReports(
        mkRun(lanePayload(d1Reason), laneIdentity()),
        mkRun(lanePayload(d1Reason), forged))
      check record{"verdict"}.getStr() == "unknown"
      check record{"axes"}{"identity"}.getStr() == "unknown"
    block truncatedDigest:
      var short = laneIdentity()
      short{"claim"}{"postSha256"} = %"fb6713097920adfe83660250aa8afc51ed6733b23ae6e4bb966b568e814f6c"
      let record = compareSkReports(
        mkRun(lanePayload(d1Reason), short), mkRun(lanePayload(d1Reason), short))
      check record{"verdict"}.getStr() == "unknown"
      check record{"axes"}{"identity"}.getStr() == "unknown"

  test "non-rust or absent subjectLane is outside the certified scope (unknown)":
    block nonRustLane:
      let payload = lanePayload(d1Reason)
      payload{"subjectLane"} = %"python"
      let record = compareSkReports(
        mkRun(payload, laneIdentity()), mkRun(payload, laneIdentity()))
      check record{"verdict"}.getStr() == "unknown"
      check record{"axes"}{"structure"}.getStr() == "unknown"
    block absentLane:
      let payload = lanePayload(d1Reason)
      payload.delete("subjectLane")
      let record = compareSkReports(
        mkRun(payload, laneIdentity()), mkRun(payload, laneIdentity()))
      check record{"verdict"}.getStr() == "unknown"
      check record{"axes"}{"structure"}.getStr() == "unknown"

  test "F1 audit — a NESTED identityBundleDigest difference is ordinary structural content (not_equal)":
    ## The root-level binding key is identity-axis jurisdiction; a key of the
    ## same name at any other depth is payload content like any other and must
    ## be compared by the structure axis — not silently exempted.
    let pl = lanePayload(d1Reason)
    let pr = lanePayload(d1Reason)
    pl{"summary"}["identityBundleDigest"] = %"left-nested"
    pr{"summary"}["identityBundleDigest"] = %"right-nested"
    let record = compareSkReports(
      mkRun(pl, laneIdentity()), mkRun(pr, laneIdentity()))
    check record{"verdict"}.getStr() == "not_equal"
    check record{"axes"}{"structure"}.getStr() == "not_equal"

  test "documented §6/R3 boundary — a difference living ONLY under a nested VOLATILE-named key is outside every axis (equal, re-audit 2026-11-01 latent surface)":
    ## NOT a defect: §6c rule 2 mandates the §6 single canonicalizer, and
    ## stripVolatile removes volatile-NAMED keys (path, subjectRoot, cacheHit,
    ## timeoutCount, …) at arbitrary depth by the documented R3
    ## path-independent-projection contract — location/cache/timing
    ## observations are deliberately not logical identity. Consequence,
    ## pinned here so the boundary is machine-visible: a difference that
    ## lives ONLY under a nested volatile-named key compares equal with NO
    ## note. Honest lane payloads (axiom.report.v1, rust lane) do not nest
    ## those names today (latent for honest artifacts); consumer-supplied or
    ## forged inputs reach it at B3iii-grade effort. Removal requires a §6
    ## canonicalizer amendment FIRST (productization_contract.md §6c rule 2,
    ## "범위·한계") — the comparison must not defect from the canonicalizer
    ## unilaterally.
    let pl = lanePayload(d1Reason)
    let pr = lanePayload(d1Reason)
    pl{"summary"}["path"] = %"value-from-run-A"
    pr{"summary"}["path"] = %"value-from-run-B"
    let record = compareSkReports(
      mkRun(pl, laneIdentity()), mkRun(pr, laneIdentity()))
    check record{"verdict"}.getStr() == "equal"
    check record{"axes"}{"structure"}.getStr() == "equal"
    check record{"notes"}.elems.len == 0

  test "F2 audit — EVERY differing reason leaf is examined; an unpromoted later difference is unknown":
    ## The reason axis must not stop at the first differing pair: a promoted
    ## displacement at leaf[0] must not conceal a genuine, unpromoted
    ## difference at a later leaf.
    let pl = lanePayload("genuine failure A", charonReason = d1Reason)
    let pr = lanePayload("genuine failure B", charonReason = d2Reason)
    let record = compareSkReports(
      mkRun(pl, laneIdentity(), rejectionSection(d1Reason, d1Path),
            bindingRejection(d1Path)),
      mkRun(pr, laneIdentity(), rejectionSection(d2Reason, d2Path),
            bindingRejection(d2Path)))
    check record{"verdict"}.getStr() == "unknown"
    check record{"axes"}{"reason"}.getStr() == "unknown"

  test "F3 audit — promotion requires the pair at the recorded reasonLeaf position (fail closed)":
    ## binding.rejection.reasonLeaf is a production-binding fact; a promotion
    ## whose leaf pair does not sit exactly at the recorded position — or
    ## whose recorded position is absent, empty, bogus, or side-divergent —
    ## is refused (the pair stays unpromoted: unknown).
    block bogusRecordedLeaf:
      var bogus = bindingRejection(d1Path)
      bogus{"reasonLeaf"} = %"totally-bogus-leaf"
      let record = compareSkReports(
        mkRun(lanePayload(d1Reason), laneIdentity(),
              rejectionSection(d1Reason, d1Path), bogus),
        mkRun(lanePayload(d2Reason), laneIdentity(),
              rejectionSection(d2Reason, d2Path), bindingRejection(d2Path)))
      check record{"verdict"}.getStr() == "unknown"
      check record{"axes"}{"reason"}.getStr() == "unknown"
    block absentRecordedLeaf:
      var absent = %*{"rawPath": %d1Path}
      let record = compareSkReports(
        mkRun(lanePayload(d1Reason), laneIdentity(),
              rejectionSection(d1Reason, d1Path), absent),
        mkRun(lanePayload(d2Reason), laneIdentity(),
              rejectionSection(d2Reason, d2Path), bindingRejection(d2Path)))
      check record{"verdict"}.getStr() == "unknown"
      check record{"axes"}{"reason"}.getStr() == "unknown"
    block pairOffTheRecordedLeaf:
      ## both records name charon.reason while the differing pair sits at
      ## targets[0].reason — record/position incoherence refuses promotion
      var off = bindingRejection(d1Path)
      off{"reasonLeaf"} = %"charon.reason"
      var offR = bindingRejection(d2Path)
      offR{"reasonLeaf"} = %"charon.reason"
      let record = compareSkReports(
        mkRun(lanePayload(d1Reason), laneIdentity(),
              rejectionSection(d1Reason, d1Path), off),
        mkRun(lanePayload(d2Reason), laneIdentity(),
              rejectionSection(d2Reason, d2Path), offR))
      check record{"verdict"}.getStr() == "unknown"
      check record{"axes"}{"reason"}.getStr() == "unknown"
