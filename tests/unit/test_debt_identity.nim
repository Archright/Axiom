## Phase 0 typed identity + Phase 7 audit identity lock tests.
##
## Verifies:
##  - validated constructors reject non-"sha256:" forms (I11)
##  - content / execution / lineage identity separation (禁止 #2)
##  - content-addressed ExecutionId (param-sensitive), stable LineageId
##  - AuditRunId excludes wall-clock metadata; same input → same run id (I10)
##  - AuditInputId = H(canonical manifest) is deterministic (I9)
##  - rule set hash is a real digest of rule text (bugfix, not "classifier-dev")

import std/[unittest, options, strutils]
import core/types/debt_types
import core/debt/debt_identity
import core/debt/debt_classifier

suite "typed identity validators (I11)":
  test "parseContentDigest accepts canonical sha256 ref":
    let d = "sha256:" & repeat('a', 64)
    check parseContentDigest(d).isSome
    check parseContentDigest(d).get.raw == d

  test "parseContentDigest rejects malformed refs":
    check parseContentDigest("").isNone
    check parseContentDigest("sha256:tooshort").isNone
    check parseContentDigest("md5:abcd").isNone
    check parseContentDigest("sha256:" & repeat('Z', 64)).isNone  # uppercase hex rejected

  test "isValidSha256Ref shape":
    check isValidSha256Ref("sha256:" & repeat('0', 64))
    check not isValidSha256Ref("sha256:" & repeat('0', 63))

suite "content/execution/lineage separation (禁止 #2)":
  test "execution identity is param-sensitive (content-addressed)":
    let a = newExecutionId("p", "tc", "cfg", "in", "timeout=5s")
    let a2 = newExecutionId("p", "tc", "cfg", "in", "timeout=5s")
    let b = newExecutionId("p", "tc", "cfg", "in", "timeout=30s")
    check a == a2            # deterministic for identical parameters
    check a != b             # timeout change → different execution identity

  test "lineage identity is stable per logical subject":
    let l1 = newLineageId("FunctionX")
    let l2 = newLineageId("FunctionX")
    let other = newLineageId("FunctionY")
    check l1 == l2
    check l1 != other

suite "audit identity (I9/I10)":
  test "AuditRunId excludes wall-clock and stays deterministic":
    let input = AuditInputId(sha256Ref("AuditInput:", "manifest"))
    let r1 = newAuditRunId(input, 0, "aaa")
    let r2 = newAuditRunId(input, 0, "aaa")
    check r1 == r2                 # same input + ordinal + nonce → same id
    check newAuditRunId(input, 1, "aaa") != r1  # ordinal sensitive
    check newAuditRunId(input, 0, "aab")  != r1  # nonce sensitive
    # must be a content ref so it is distinguishable from wall-clock metadata
    check isValidSha256Ref(raw(r1))

  test "AuditInputId = H(canonical manifest), ruleSetHash-sensitive":
    let d = ContentDigest("sha256:" & repeat('b', 64))
    let m1 = AuditInputManifest(repositorySnapshot: "abc", evidenceRoot: d,
                                provenanceRoot: d, artifactRoot: d,
                                executionRoot: d, ruleSetHash: "rules-v1",
                                toolchainContext: "nim")
    let m1b = AuditInputManifest(repositorySnapshot: "abc", evidenceRoot: d,
                                 provenanceRoot: d, artifactRoot: d,
                                 executionRoot: d, ruleSetHash: "rules-v1",
                                 toolchainContext: "nim")
    let m2 = AuditInputManifest(repositorySnapshot: "abc", evidenceRoot: d,
                                provenanceRoot: d, artifactRoot: d,
                                executionRoot: d, ruleSetHash: "rules-v2",
                                toolchainContext: "nim")
    check manifestInputId(m1) == manifestInputId(m1b)  # deterministic
    check manifestInputId(m1) != manifestInputId(m2)   # rule change → new input id

suite "rule set pinning (replaces classifier-dev)":
  test "debtRuleSetHash is a real digest, deterministic":
    check debtRuleSetHash() == debtRuleSetHash()
    check isValidSha256Ref(debtRuleSetHash())
    check debtRuleSetHash() != "classifier-dev"
    check DebtClassifierVersion != "classifier-dev"
    check DebtTaxonomyVersion != "classifier-dev"