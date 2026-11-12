## Bug attribution grounds — pure validator tests (record layer).
##
## SSOT: docs/spec/bug_verdict_glossary.md (§2.2 공용 4요소 · §2.4a–§2.4c) +
## docs/spec/bug_attribution_grounds_file.md +
## data/bug_attribution/SPEC-B36-COUT.json.
##
## Measured here:
##   1. The committed base36 spec overlays carry a valid additive
##      `claimOwnership` block (closed owner set, contract-path agreement,
##      resolvable contract/adoptionRef paths) — and every tampered shape
##      (missing, typo'd owner, contradiction, empty adoptionRef) fails
##      closed. The base32 rem overlay's backfilled block validates under the
##      same closed schema.
##   2. The committed grounds record SPEC-B36-COUT.json validates against its
##      cited spec overlay: subject binding cross-check, C-carried observation
##      quartet, all-false E1/E2/E3 grounds (=> Bug Suspected territory by
##      glossary §2.4b — the label itself is projection-only and is NOT
##      stored), corroboration marked corroboration-ONLY, and the
##      canonical-serialization recordDigest.
##   3. The groundsValidation surface: present:true without a C-carried
##      reproduction quartet is invalidated with a recorded reason;
##      present:false with refs or a reproduction block is rejected; unknown
##      requirementSourceStatus values are rejected while all three closed-set
##      values are accepted; a stored display label is rejected by the closed
##      key set; a tampered recordDigest is rejected.
import std/[json, os, strutils, unittest]

import ../../src/core/results
import ../../src/core/utils/repo_root
import ../../src/core/trusted/bug_attribution_grounds

proc committedSpec(name: string): JsonNode =
  parseJson(readFile(repoRootConst() / "config" / "spec" / name))

proc committedGrounds(): JsonNode =
  parseJson(readFile(repoRootConst() / "data" / "bug_attribution" /
    "SPEC-B36-COUT.json"))

proc redigest(node: JsonNode): JsonNode =
  ## Re-pin recordDigest after a mutation (the digest never covers itself —
  ## computeRecordDigest deletes the member before hashing).
  node["recordDigest"] = %computeRecordDigest(node)
  node

# ---------------------------------------------------------------------------
# Suite 1 — claimOwnership (additive spec field, fail-closed)
# ---------------------------------------------------------------------------

suite "claimOwnership — closed owner set + contract agreement":

  test "both committed base36 specs carry a valid claimOwnership block":
    for name in ["nim_stew_base36_cout_spec.json",
                 "base36_sizing_relational_spec.json"]:
      let node = committedSpec(name)
      let res = validateClaimOwnership(node)
      check res.isOk()
      check res.get() == "axiom-defined-rule"
      # The recorded paths must resolve on disk (adoptionRef = where
      # adoption is recorded; contract = the owning contract doc).
      check fileExists(repoRootConst() /
        node["claimOwnership"]["contract"].getStr())
      check fileExists(repoRootConst() /
        node["claimOwnership"]["adoptionRef"].getStr())
      check node["claimOwnership"]["contract"].getStr() ==
        node["contract"].getStr()

  test "the committed base32 overlay's backfilled claimOwnership block validates":
    let node = committedSpec("nim_stew_base32_rem_spec.json")
    let res = validateClaimOwnership(node)
    check res.isOk()
    check res.get() == "axiom-defined-rule"
    # The recorded paths must resolve on disk (adoptionRef = where
    # adoption is recorded; contract = the owning contract doc).
    check fileExists(repoRootConst() /
      node["claimOwnership"]["contract"].getStr())
    check fileExists(repoRootConst() /
      node["claimOwnership"]["adoptionRef"].getStr())
    check node["claimOwnership"]["contract"].getStr() ==
      node["contract"].getStr()

  test "fail-closed: a spec without claimOwnership is rejected":
    var node = committedSpec("nim_stew_base36_cout_spec.json")
    node.delete("claimOwnership")
    let res = validateClaimOwnership(node)
    check res.isErr()
    check res.error.contains("claimOwnership")
    check res.error.contains("object required")

  test "fail-closed: a typo'd owner value is rejected":
    var node = committedSpec("nim_stew_base36_cout_spec.json")
    node["claimOwnership"]["owner"] = %"axiom-defined-rules"
    let res = validateClaimOwnership(node)
    check res.isErr()
    check res.error.contains("owner must be one of")

  test "the closed owner set accepts software-requirement":
    var node = committedSpec("nim_stew_base36_cout_spec.json")
    node["claimOwnership"]["owner"] = %"software-requirement"
    let res = validateClaimOwnership(node)
    check res.isOk()
    check res.get() == "software-requirement"

  test "fail-closed: a contradictory contract path is rejected":
    var node = committedSpec("nim_stew_base36_cout_spec.json")
    node["claimOwnership"]["contract"] = %"docs/spec/some_other_contract.md"
    let res = validateClaimOwnership(node)
    check res.isErr()
    check res.error.contains("contradicts")

  test "fail-closed: an empty adoptionRef is rejected":
    var node = committedSpec("nim_stew_base36_cout_spec.json")
    node["claimOwnership"]["adoptionRef"] = %""
    let res = validateClaimOwnership(node)
    check res.isErr()
    check res.error.contains("adoptionRef")

  test "fail-closed: an unexpected claimOwnership key is rejected":
    var node = committedSpec("nim_stew_base36_cout_spec.json")
    node["claimOwnership"]["Owners"] = %"axiom-defined-rule"
    let res = validateClaimOwnership(node)
    check res.isErr()
    check res.error.contains("unexpected key")

# ---------------------------------------------------------------------------
# Suite 2 — the committed grounds record (subject binding + digest)
# ---------------------------------------------------------------------------

suite "grounds file SPEC-B36-COUT — committed record validates":

  test "the committed grounds record validates against its cited spec":
    let res = validateGroundsFile(committedGrounds(),
      committedSpec("nim_stew_base36_cout_spec.json"))
    check res.isOk()
    let view = res.get()
    check view.specId == "SPEC-B36-COUT"
    check view.subjectCommit == "1853f20bdfeda61331a0b7e02f7aace0e88a0dfe"
    check view.moduleSha256 ==
      "b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8"
    check view.requirementSourceStatus == "recordedDisclaiming"
    check view.corroborationSpecId == "SPEC-B36-COUT"
    check view.corroborationVerdict == "vsDisproved"
    check view.corroborationReplayVerdict == "rvAgree"

  test "the committed bytesview grounds record validates against its overlay":
    let res = validateGroundsFile(
      parseJson(readFile(repoRootConst() / "data" / "bug_attribution" /
        "SPEC-LIBP2P-BV-SLICE.json")),
      committedSpec("nim_libp2p_bytesview_slice.json"))
    check res.isOk()
    check res.get().specId == "SPEC-LIBP2P-BV-SLICE"
    check res.get().subjectCommit == "a130a7f32219909bdcda14b7f1e64d0804fc832c"
    check res.get().moduleSha256 ==
      "b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee"
    check res.get().requirementSourceStatus == "unrecorded"

  test "BYO runtime overlay: repository re-bound to a bare slug still validates":
    # proposition_intake re-binds subject.repository to the authoritative
    # slug (config/spec prose → slug); the commit/blob pins stay
    # byte-identical — the grounds binding must follow the subject.commit
    # pin field, not the repository prose.
    var spec = committedSpec("nim_libp2p_bytesview_slice.json")
    spec["subject"]["repository"] = %"iftech/nim-libp2p"
    let res = validateGroundsFile(
      parseJson(readFile(repoRootConst() / "data" / "bug_attribution" /
        "SPEC-LIBP2P-BV-SLICE.json")), spec)
    check res.isOk()

  test "fail-closed: a spec subject.commit pin differing from the grounds commit is rejected":
    var spec = committedSpec("nim_libp2p_bytesview_slice.json")
    spec["subject"]["repository"] = %"iftech/nim-libp2p"
    spec["subject"]["commit"] = %('0'.repeat(40))
    let res = validateGroundsFile(
      parseJson(readFile(repoRootConst() / "data" / "bug_attribution" /
        "SPEC-LIBP2P-BV-SLICE.json")), spec)
    check res.isErr()
    check res.error.contains("pinned subject commit")

  test "recordDigest is the canonical-serialization digest (method §3)":
    let grounds = committedGrounds()
    check computeRecordDigest(grounds) == grounds["recordDigest"].getStr()

  test "recordDigest is on-disk-formatting independent":
    let grounds = committedGrounds()
    # Same record, different byte layout (compact round-trip).
    let reformatted = parseJson($grounds)
    check computeRecordDigest(reformatted) == grounds["recordDigest"].getStr()

  test "fail-closed: a wrong subjectCommit is rejected":
    var grounds = committedGrounds()
    grounds["subjectCommit"] = %('0'.repeat(40))
    let res = validateGroundsFile(grounds,
      committedSpec("nim_stew_base36_cout_spec.json"))
    check res.isErr()
    check res.error.contains("subjectCommit is not the cited spec's pinned " &
      "subject commit")

  test "fail-closed: a wrong moduleSha256 is rejected":
    var grounds = committedGrounds()
    grounds["moduleSha256"] = %('a'.repeat(64))
    let res = validateGroundsFile(grounds,
      committedSpec("nim_stew_base36_cout_spec.json"))
    check res.isErr()
    check res.error.contains("moduleSha256 does not match")

  test "fail-closed: citing a different spec is rejected":
    # Same subject records, but the cited overlay is SPEC-B36-RELATIONAL —
    # the specId cross-check must fail closed.
    let res = validateGroundsFile(committedGrounds(),
      committedSpec("base36_sizing_relational_spec.json"))
    check res.isErr()
    check res.error.contains("specId")

# ---------------------------------------------------------------------------
# Suite 3 — groundsValidation surface (fail-closed mutations, re-digested)
# ---------------------------------------------------------------------------

suite "groundsValidation — recorded reasons on invalid ground shapes":

  test "E1 present:true without a reproduction quartet is invalidated with " &
      "a recorded reason":
    var grounds = committedGrounds()
    grounds["confirmation"]["grounds"]["E1"] = %*{
      "present": true,
      "refs": ["docs/evidence/unknown_record.md"]}
    let res = validateGroundsFile(redigest(grounds),
      committedSpec("nim_stew_base36_cout_spec.json"))
    check res.isErr()
    check res.error.contains("groundsValidation")
    check res.error.contains("E1")
    check res.error.contains("C-carried reproduction quartet")

  test "E1 present:true WITH a complete C-carried reproduction validates":
    var grounds = committedGrounds()
    grounds["confirmation"]["grounds"]["E1"] = %*{
      "present": true,
      "refs": ["docs/evidence/unknown_record.md"],
      "reproduction": grounds["anomaly"]["observationQuartet"]["reproduction"]}
    let res = validateGroundsFile(redigest(grounds),
      committedSpec("nim_stew_base36_cout_spec.json"))
    check res.isOk()

  test "present:false with non-empty refs is rejected":
    var grounds = committedGrounds()
    grounds["confirmation"]["grounds"]["E2"] = %*{
      "present": false,
      "refs": ["docs/evidence/unknown_record.md"]}
    let res = validateGroundsFile(redigest(grounds),
      committedSpec("nim_stew_base36_cout_spec.json"))
    check res.isErr()
    check res.error.contains("groundsValidation")
    check res.error.contains("E2")
    check res.error.contains("requires empty refs")

  test "present:false with a reproduction block is rejected":
    var grounds = committedGrounds()
    grounds["confirmation"]["grounds"]["E3"] = %*{
      "present": false,
      "refs": [],
      "reproduction": grounds["anomaly"]["observationQuartet"]["reproduction"]}
    let res = validateGroundsFile(redigest(grounds),
      committedSpec("nim_stew_base36_cout_spec.json"))
    check res.isErr()
    check res.error.contains("groundsValidation")
    check res.error.contains("E3")
    check res.error.contains("requires no reproduction")

  test "all four closed-set requirementSourceStatus values are accepted":
    for status in ["recordedBinding", "recordedDisclaiming", "unrecorded",
                   "unknown"]:
      var grounds = committedGrounds()
      grounds["requirementSourceStatus"] = %status
      let res = validateGroundsFile(redigest(grounds),
        committedSpec("nim_stew_base36_cout_spec.json"))
      check res.isOk()
      check res.get().requirementSourceStatus == status

  test "fail-closed: an unknown requirementSourceStatus is rejected":
    var grounds = committedGrounds()
    grounds["requirementSourceStatus"] = %"recordedDisclaimer"
    let res = validateGroundsFile(redigest(grounds),
      committedSpec("nim_stew_base36_cout_spec.json"))
    check res.isErr()
    check res.error.contains("requirementSourceStatus must be one of")

  test "fail-closed: a stored display label is rejected by the closed schema":
    var grounds = committedGrounds()
    grounds["attributionLabel"] = %"Bug Suspected"
    let res = validateGroundsFile(redigest(grounds),
      committedSpec("nim_stew_base36_cout_spec.json"))
    check res.isErr()
    check res.error.contains("unexpected key")

  test "fail-closed: a tampered recordDigest is rejected":
    var grounds = committedGrounds()
    grounds["recordDigest"] = %('0'.repeat(64))
    let res = validateGroundsFile(grounds,
      committedSpec("nim_stew_base36_cout_spec.json"))
    check res.isErr()
    check res.error.contains("recordDigest does not match")

  test "fail-closed: an exactCommit contradicting subjectCommit is rejected":
    var grounds = committedGrounds()
    grounds["anomaly"]["observationQuartet"]["exactCommit"] = %('f'.repeat(40))
    let res = validateGroundsFile(redigest(grounds),
      committedSpec("nim_stew_base36_cout_spec.json"))
    check res.isErr()
    check res.error.contains("must equal subjectCommit")
