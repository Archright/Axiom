{.push raises: [].}

## Tests for the BYO-Agent propositions intake (Phase 5.1) —
## `ax prove --proposals <path>`.
##
## Contract: docs/spec/byo_agent_proposition_contract.md (schema v2).
## Scope: the intake layer — schema / subject-claim fail-closed gates, the
## per-proposition capability seeds (INCAPABLE{UNKNOWN_SPEC |
## UNSUPPORTED_LOGIC} — not rejections), runtime overlay installation under
## $AXIOM_STATE_DIR/specs, the loader shadow-merge seam, and the generated
## parser surface. The full prove path (subject pin verification, lane
## dispatch, verdict display) is E2E territory and is intentionally not
## exercised here.

import std/[json, os, strutils, times, unittest]
import cli/cli_surface_generated
import cli/cli_types
import cli/external_subject_registry
import cli/proposition_intake
import core/results
import core/utils/repo_root

const fixtureSpecDir = repoRootConst() / "tests" / "fixtures" / "spec_overlays"
const fixtureSpecId = "SPEC-FIXTURE-CONSTRUCTED-GATE"
const fixtureSpecRelPath = "constructed_gate_fixture.json"
const fixtureRepositoryClaim = "acme/fixture-subject"
const fixtureCommitClaim = "0123456789abcdef0123456789abcdef01234567"

proc validPropositionsJson(specId: string = fixtureSpecId;
                           target: string = "fixture_gate_subject::gateAccept";
                           id: string = "prop-1";
                           claimForm: bool = false): JsonNode =
  var proposition = %*{
    "id": id,
    "target": target,
    "source_location": {"file": "fixture_gate_subject.nim", "line": 21},
    "explanation": "gateAccept disagrees with the forbid set for c=2"
  }
  if claimForm:
    proposition["logic"] = %("forbid-set-membership")
    proposition["expression"] = %("gateAccept(2) == false")
  else:
    proposition["specId"] = %specId
  %*{
    "schema_version": 2,
    "subject": {
      "repository": fixtureRepositoryClaim,
      "commit": fixtureCommitClaim
    },
    "agent": {"id": "test-agent", "version": "1.0.0"},
    "propositions": [proposition]
  }

proc freshStateDir(name: string): string =
  getTempDir() / "axiom_byoa_intake_" & name & "_" & $epochTime()

proc committedFixture(): JsonNode {.raises: [CatchableError].} =
  parseJson(readFile(fixtureSpecDir / fixtureSpecRelPath))

proc committedFixtureBlobSha(): string {.raises: [CatchableError].} =
  committedFixture(){"subject"}{"blobSha256"}.getStr("")

# ---------------------------------------------------------------------------
# Suite 1 — generated parser surface
# ---------------------------------------------------------------------------

suite "--proposals parser surface (cli_surface_generated)":
  test "parses the path value into the proposals field":
    let res = parseAxProveFlags(@["--proposals", "/tmp/propositions.json"])
    check res.ok
    check res.value.proposals == "/tmp/propositions.json"
  test "missing value fails with the canonical message":
    let res = parseAxProveFlags(@["--proposals"])
    check not res.ok
    check res.err == "missing value: --proposals"
  test "help text mentions --proposals":
    check axProveFlagsHelp().contains("--proposals")

# ---------------------------------------------------------------------------
# Suite 2 — closed-shape schema validation (pure)
# ---------------------------------------------------------------------------

suite "parsePropositionsSchema (BAD_SCHEMA / NO_PROPOSALS)":
  test "valid lane-form document projects every declared field":
    let res = parsePropositionsSchema(validPropositionsJson())
    check res.ok
    check res.value.subjectRepository == fixtureRepositoryClaim
    check res.value.subjectCommit == fixtureCommitClaim
    check res.value.agentId == "test-agent"
    check res.value.agentVersion == "1.0.0"
    check res.value.propositions.len == 1
    check res.value.propositions[0].id == "prop-1"
    check res.value.propositions[0].form == pfLane
    check res.value.propositions[0].specId == fixtureSpecId
    check res.value.propositions[0].sourceLine == 21
  test "valid claim-form document projects logic and expression":
    let res = parsePropositionsSchema(validPropositionsJson(claimForm = true))
    check res.ok
    check res.value.propositions[0].form == pfClaim
    check res.value.propositions[0].specId == ""
    check res.value.propositions[0].logic == "forbid-set-membership"
    check res.value.propositions[0].expression == "gateAccept(2) == false"
  test "non-object root is BAD_SCHEMA":
    check parsePropositionsSchema(newJArray()).error.contains("BAD_SCHEMA")
  test "schema_version 1 (v1) is BAD_SCHEMA — v2 is the only accepted version":
    var doc = validPropositionsJson()
    doc["schema_version"] = %1
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "schema_version other than 2 is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc["schema_version"] = %3
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "missing schema_version is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc.delete("schema_version")
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "empty subject.repository is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"subject"}["repository"] = %""
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "non-40-hex subject.commit is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"subject"}["commit"] = %"deadbeef"
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "empty agent.id is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"agent"}["id"] = %""
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "propositions of non-array type is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc["propositions"] = %"not-an-array"
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "empty propositions array is NO_PROPOSALS":
    var doc = validPropositionsJson()
    doc["propositions"] = %[]
    check parsePropositionsSchema(doc).error.contains("NO_PROPOSALS")
  test "missing proposition.id is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}.delete("id")
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "empty proposition.id is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}["id"] = %""
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "proposition.id over 128 characters is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}["id"] = %repeat("x", 129)
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "duplicate proposition.id is BAD_SCHEMA":
    var doc = validPropositionsJson()
    var second = doc{"propositions"}{0}.copy()
    second["target"] = %"fixture_gate_subject::fixtureControlReject"
    doc{"propositions"}.add(second)
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
    check parsePropositionsSchema(doc).error.contains("unique")
  test "lane-form and claim-form together are BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}["logic"] = %"forbid-set-membership"
    doc{"propositions"}{0}["expression"] = %"gateAccept(2) == false"
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "neither lane-form nor claim-form is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}.delete("specId")
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "claim-form without expression is BAD_SCHEMA":
    var doc = validPropositionsJson(claimForm = true)
    doc{"propositions"}{0}.delete("expression")
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "claim-form logic over 128 characters is BAD_SCHEMA":
    var doc = validPropositionsJson(claimForm = true)
    doc{"propositions"}{0}["logic"] = %repeat("y", 129)
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "claim-form expression over 4096 characters is BAD_SCHEMA":
    var doc = validPropositionsJson(claimForm = true)
    doc{"propositions"}{0}["expression"] = %repeat("z", 4097)
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "more than 32 propositions is BAD_SCHEMA":
    var doc = validPropositionsJson()
    for i in 1 .. 32:
      var extra = doc{"propositions"}{0}.copy()
      extra["id"] = %("prop-" & $i)
      doc{"propositions"}.add(extra)
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "empty proposition.specId is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}["specId"] = %""
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "empty proposition.target is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}["target"] = %""
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "source_location is optional in v2":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}.delete("source_location")
    let res = parsePropositionsSchema(doc)
    check res.ok
    check res.value.propositions[0].sourceFile == ""
    check res.value.propositions[0].sourceLine == 0
  test "malformed source_location object is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}["source_location"] = %"not-an-object"
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "negative source_location.line is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}{"source_location"}["line"] = %(-1)
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")
  test "explanation is optional in v2":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}.delete("explanation")
    check parsePropositionsSchema(doc).ok
  test "non-string explanation is BAD_SCHEMA":
    var doc = validPropositionsJson()
    doc{"propositions"}{0}["explanation"] = %42
    check parsePropositionsSchema(doc).error.contains("BAD_SCHEMA")

# ---------------------------------------------------------------------------
# Suite 3 — intake: claims, specId resolution, overlay installation
# ---------------------------------------------------------------------------

suite "ingestPropositionsFile (fixture catalog)":
  test "valid intake installs the runtime overlay (local mode, env unset)":
    delEnv(subjectRepositoryEnv)
    delEnv(subjectCommitEnv)
    let stateDir = freshStateDir("local")
    createDir(stateDir)
    defer: removeDir(stateDir)
    let propsPath = stateDir / "propositions.json"
    writeFile(propsPath, pretty(validPropositionsJson()))
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir,
                                     stateDirOverride = stateDir)
    check res.ok
    check res.value.target == "fixture_gate_subject::gateAccept"
    check res.value.overlaySpecRelPaths == @[fixtureSpecRelPath]
    let overlayPath = stateDir / "specs" / fixtureSpecRelPath
    check fileExists(overlayPath)
    let overlay = parseJson(readFile(overlayPath))
    # local mode: the JSON claim is the recorded claim, accepted as-is
    check overlay{"subject"}{"repository"}.getStr("") == fixtureRepositoryClaim
    # catalog pins are byte-identical — intake never rewrites a pin
    check overlay{"subject"}{"blobSha256"}.getStr("") == committedFixtureBlobSha()
    check overlay{"specId"}.getStr("") == fixtureSpecId
  test "matching subject env accepts intake and stamps the overlay slug":
    # env set ⇒ the JSON claim must equal it (else SUBJECT_MISMATCH, tested
    # below); on agreement the overlay carries the authoritative slug.
    delEnv(subjectCommitEnv)
    putEnv(subjectRepositoryEnv, fixtureRepositoryClaim)
    defer: delEnv(subjectRepositoryEnv)
    let stateDir = freshStateDir("auth")
    createDir(stateDir)
    defer: removeDir(stateDir)
    let propsPath = stateDir / "propositions.json"
    writeFile(propsPath, pretty(validPropositionsJson()))
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir,
                                     stateDirOverride = stateDir)
    check res.ok
    let overlay = parseJson(readFile(stateDir / "specs" / fixtureSpecRelPath))
    check overlay{"subject"}{"repository"}.getStr("") == fixtureRepositoryClaim
    check overlay{"subject"}{"blobSha256"}.getStr("") == committedFixtureBlobSha()
  test "repository env mismatch is SUBJECT_MISMATCH":
    delEnv(subjectCommitEnv)
    putEnv(subjectRepositoryEnv, "other/repo")
    defer: delEnv(subjectRepositoryEnv)
    let stateDir = freshStateDir("mismatch")
    createDir(stateDir)
    defer: removeDir(stateDir)
    let propsPath = stateDir / "propositions.json"
    writeFile(propsPath, pretty(validPropositionsJson()))
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir,
                                     stateDirOverride = stateDir)
    check not res.ok
    check res.error.contains("SUBJECT_MISMATCH")
  test "commit env mismatch is SUBJECT_MISMATCH":
    delEnv(subjectRepositoryEnv)
    putEnv(subjectCommitEnv, "ffffffffffffffffffffffffffffffffffffffff")
    defer: delEnv(subjectCommitEnv)
    let stateDir = freshStateDir("cmismatch")
    createDir(stateDir)
    defer: removeDir(stateDir)
    let propsPath = stateDir / "propositions.json"
    writeFile(propsPath, pretty(validPropositionsJson()))
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir,
                                     stateDirOverride = stateDir)
    check not res.ok
    check res.error.contains("SUBJECT_MISMATCH")
  test "unknown specId is a per-proposition INCAPABLE seed, not a rejection":
    delEnv(subjectRepositoryEnv)
    delEnv(subjectCommitEnv)
    let stateDir = freshStateDir("unsupported")
    createDir(stateDir)
    defer: removeDir(stateDir)
    let propsPath = stateDir / "propositions.json"
    writeFile(propsPath,
      pretty(validPropositionsJson(specId = "SPEC-DOES-NOT-EXIST", id = "prop-x")))
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir,
                                     stateDirOverride = stateDir)
    check res.ok
    check res.value.overlaySpecRelPaths.len == 0
    check res.value.incapableSeeds.len == 1
    check res.value.incapableSeeds[0][0] == "prop-x"
    check res.value.incapableSeeds[0][1] == pcrUnknownSpec
  test "claim-form proposition is accepted with an UNSUPPORTED_LOGIC seed":
    delEnv(subjectRepositoryEnv)
    delEnv(subjectCommitEnv)
    let stateDir = freshStateDir("claim")
    createDir(stateDir)
    defer: removeDir(stateDir)
    let propsPath = stateDir / "propositions.json"
    writeFile(propsPath, pretty(validPropositionsJson(claimForm = true)))
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir,
                                     stateDirOverride = stateDir)
    check res.ok
    check res.value.target == "fixture_gate_subject::gateAccept"
    check res.value.overlaySpecRelPaths.len == 0
    check res.value.incapableSeeds ==
      @[(("prop-1", pcrUnsupportedLogic))]
  test "mixed document: resolvable lane installs its overlay, unknown and claim-form propositions seed INCAPABLE":
    delEnv(subjectRepositoryEnv)
    delEnv(subjectCommitEnv)
    let stateDir = freshStateDir("mixed")
    createDir(stateDir)
    defer: removeDir(stateDir)
    var doc = validPropositionsJson()
    doc{"propositions"}.add(%*{
      "id": "prop-unknown",
      "specId": "SPEC-DOES-NOT-EXIST",
      "target": "fixture_gate_subject::gateAccept",
      "source_location": {"file": "fixture_gate_subject.nim", "line": 21},
      "explanation": "unknown catalog reference"
    })
    doc{"propositions"}.add(%*{
      "id": "prop-claim",
      "logic": "forbid-set-membership",
      "expression": "gateAccept(2) == false",
      "target": "fixture_gate_subject::gateAccept"
    })
    let propsPath = stateDir / "propositions.json"
    writeFile(propsPath, pretty(doc))
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir,
                                     stateDirOverride = stateDir)
    check res.ok
    # the resolvable proposition's overlay installs; the others get no overlay
    check res.value.overlaySpecRelPaths == @[fixtureSpecRelPath]
    check fileExists(stateDir / "specs" / fixtureSpecRelPath)
    check res.value.incapableSeeds ==
      @[(("prop-unknown", pcrUnknownSpec)), (("prop-claim", pcrUnsupportedLogic))]
  test "committed catalog resolves a real config/spec specId":
    delEnv(subjectRepositoryEnv)
    delEnv(subjectCommitEnv)
    let stateDir = freshStateDir("committed")
    createDir(stateDir)
    defer: removeDir(stateDir)
    let propsPath = stateDir / "propositions.json"
    writeFile(propsPath,
      pretty(validPropositionsJson(specId = "SPEC-TOML-D2-AGENT",
                                   target = "toml_serialization/lexer::scanString")))
    # default specDir = the committed config/spec catalog
    let res = ingestPropositionsFile(propsPath, stateDirOverride = stateDir)
    check res.ok
    check res.value.overlaySpecRelPaths == @["toml_d2_agent_spec.json"]
    check fileExists(stateDir / "specs" / "toml_d2_agent_spec.json")
  test "multiple distinct targets are rejected (one prove run per target)":
    delEnv(subjectRepositoryEnv)
    delEnv(subjectCommitEnv)
    let stateDir = freshStateDir("multi")
    createDir(stateDir)
    defer: removeDir(stateDir)
    var doc = validPropositionsJson()
    doc{"propositions"}.add(%*{
      "id": "prop-2",
      "specId": fixtureSpecId,
      "target": "fixture_gate_subject::fixtureControlReject",
      "source_location": {"file": "fixture_gate_subject.nim", "line": 23},
      "explanation": "control carrier"
    })
    let propsPath = stateDir / "propositions.json"
    writeFile(propsPath, pretty(doc))
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir,
                                     stateDirOverride = stateDir)
    check not res.ok
    check res.error.contains("MULTIPLE_TARGETS")
  test "duplicate (specId, target) propositions dedupe to one overlay document":
    delEnv(subjectRepositoryEnv)
    delEnv(subjectCommitEnv)
    let stateDir = freshStateDir("dedupe")
    createDir(stateDir)
    defer: removeDir(stateDir)
    var doc = validPropositionsJson()
    doc{"propositions"}.add(%*{
      "id": "prop-2",
      "specId": fixtureSpecId,
      "target": "fixture_gate_subject::gateAccept",
      "source_location": {"file": "fixture_gate_subject.nim", "line": 21},
      "explanation": "same lane reference under a distinct id"
    })
    let propsPath = stateDir / "propositions.json"
    writeFile(propsPath, pretty(doc))
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir,
                                     stateDirOverride = stateDir)
    check res.ok
    check res.value.overlaySpecRelPaths == @[fixtureSpecRelPath]
    check res.value.propositions.len == 2
    check res.value.incapableSeeds.len == 0
  test "document over 262144 bytes is BAD_SCHEMA":
    delEnv(subjectRepositoryEnv)
    delEnv(subjectCommitEnv)
    let stateDir = freshStateDir("toobig")
    createDir(stateDir)
    defer: removeDir(stateDir)
    let propsPath = stateDir / "propositions.json"
    var doc = validPropositionsJson()
    doc["padding"] = %repeat("p", 262144)
    writeFile(propsPath, pretty(doc))
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir,
                                     stateDirOverride = stateDir)
    check not res.ok
    check res.error.contains("BAD_SCHEMA")
    check res.error.contains("262144")
  test "malformed JSON is BAD_SCHEMA":
    delEnv(subjectRepositoryEnv)
    delEnv(subjectCommitEnv)
    let stateDir = freshStateDir("malformed")
    createDir(stateDir)
    defer: removeDir(stateDir)
    let propsPath = stateDir / "propositions.json"
    writeFile(propsPath, "{oops")
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir,
                                     stateDirOverride = stateDir)
    check not res.ok
    check res.error.contains("BAD_SCHEMA")
  test "missing file is BAD_SCHEMA":
    delEnv(subjectRepositoryEnv)
    delEnv(subjectCommitEnv)
    let res = ingestPropositionsFile("/nonexistent/propositions.json",
                                     specDir = fixtureSpecDir,
                                     stateDirOverride = getTempDir())
    check not res.ok
    check res.error.contains("BAD_SCHEMA")
  test "unset AXIOM_STATE_DIR without override fails closed":
    delEnv(subjectRepositoryEnv)
    delEnv(subjectCommitEnv)
    delEnv("AXIOM_STATE_DIR")
    let propsPath = getTempDir() / "axiom_byoa_intake_nostate_props.json"
    writeFile(propsPath, pretty(validPropositionsJson()))
    defer: removeFile(propsPath)
    let res = ingestPropositionsFile(propsPath, specDir = fixtureSpecDir)
    check not res.ok
    check res.error.contains("AXIOM_STATE_DIR")

# ---------------------------------------------------------------------------
# Suite 4 — loader shadow-merge seam (overlayDir)
# ---------------------------------------------------------------------------

suite "loadExternalSubjectRegistry overlayDir shadow-merge":
  test "committed load is unchanged without overlayDir":
    let res = loadExternalSubjectRegistry(fixtureSpecDir)
    check res.ok
    check res.value.entries.len == 1
    check res.value.entries[0].specId == fixtureSpecId
    check res.value.entries[0].raw{"subject"}{"repository"}.getStr("") ==
      "fixture-only (tests/fixtures/spec_overlays/fixture_gate_subject/ — no real subject tree)"
  test "overlay shadows the same specRelPath":
    let overlayDir = freshStateDir("shadow")
    createDir(overlayDir)
    defer: removeDir(overlayDir)
    var shadowDoc = committedFixture()
    shadowDoc{"subject"}["repository"] = %"shadow/slug"
    writeFile(overlayDir / fixtureSpecRelPath, pretty(shadowDoc))
    let res = loadExternalSubjectRegistry(fixtureSpecDir, overlayDir = overlayDir)
    check res.ok
    # shadowed, NOT duplicated: one entry, overlay document wins
    check res.value.entries.len == 1
    check res.value.entries[0].raw{"subject"}{"repository"}.getStr("") == "shadow/slug"
    check res.value.entries[0].raw{"subject"}{"blobSha256"}.getStr("") ==
      committedFixtureBlobSha()
  test "overlay entry reusing a specId under a new filename is a duplicate-specId rejection":
    let overlayDir = freshStateDir("dupespec")
    createDir(overlayDir)
    defer: removeDir(overlayDir)
    var renamedDoc = committedFixture()
    writeFile(overlayDir / "renamed_fixture.json", pretty(renamedDoc))
    let res = loadExternalSubjectRegistry(fixtureSpecDir, overlayDir = overlayDir)
    check not res.ok
    check res.error.contains("duplicate specId")
  test "overlay entry naming the same subject under a new specId is an overlap rejection":
    let overlayDir = freshStateDir("overlap")
    createDir(overlayDir)
    defer: removeDir(overlayDir)
    var secondDoc = committedFixture()
    secondDoc["specId"] = %"SPEC-FIXTURE-CONSTRUCTED-GATE-2"
    writeFile(overlayDir / "second_fixture.json", pretty(secondDoc))
    let res = loadExternalSubjectRegistry(fixtureSpecDir, overlayDir = overlayDir)
    check not res.ok
    check res.error.contains("same-precedence")
