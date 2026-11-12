## INV-9 forbidden-claim sentence scanner — test matrix.
##
## Covers (per the ADR-0030 U2 closure contract):
##   negative  — every forbidden sentence in the closed vocabulary is detected
##               inside certificate-payload fields (leanProposition / leanSource
##               / reason / nested paths) and raw text;
##   positive  — the contract's bounded claim shape ("verified w.r.t. the
##               extracted representation under a Qualified extractor"), the
##               certified-subset terminology, the fixed reason lexicon and a
##               real-shaped certificate payload all pass;
##   allowlist — the file+symbol+ruleId+contentHash canonical anchor matches
##               exactly, and any tamper/drift re-arms the finding;
##   tamper    — editing a sanctioned occurrence breaks the content hash;
##   fail-closed — missing/unreadable/malformed targets exit 2 (never skip),
##               via end-to-end runs of the CLI runner;
##   real surfaces — the repository's actual certificate data roots scan clean
##               (test-side INV-9 assertion).

import std/[unittest, json, strutils, os, osproc, sequtils]
import verification/forbidden_claim_scan

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = parentDir(dir)
    if parent == dir:
      doAssert false, "repo root (.axiom_root) not found from " & getCurrentDir()
    dir = parent

suite "INV-9 closed vocabulary":

  test "vocabulary is the closed 4-rule set derived from the contracts":
    check forbiddenClaimRules.len == 4
    check forbiddenClaimRules[0].ruleId == "INV9-NIM-SEM-CERT"
    check forbiddenClaimRules[0].phrase == "Nim semantics certified"
    check forbiddenClaimRules[1].ruleId == "INV9-TCB-FINAL-CLOSURE"
    check forbiddenClaimRules[1].phrase == "최종 TCB 폐쇄"
    check forbiddenClaimRules[2].ruleId == "INV9-RUST-SEM-CERT"
    check forbiddenClaimRules[2].phrase == "Rust semantics certified"
    check forbiddenClaimRules[3].ruleId == "INV9-SOURCE-SEM-CERT"
    check forbiddenClaimRules[3].phrase == "source semantics certified"
    for rule in forbiddenClaimRules:
      check rule.contract.len > 0

suite "INV-9 negative detection (forbidden sentence -> finding)":

  test "each forbidden sentence is detected in plain text":
    for rule in forbiddenClaimRules:
      let findings = findForbiddenClaims(rule.phrase)
      check findings.len == 1
      check findings[0].ruleId == rule.ruleId
      check findings[0].phrase == rule.phrase
      check findings[0].line == 1
      check findings[0].offset == 0

  test "forbidden sentence mid-sentence is detected":
    let findings = findForbiddenClaims(
      "Release notes: the pipeline now proves Rust semantics certified for all subjects.")
    check findings.len == 1
    check findings[0].ruleId == "INV9-RUST-SEM-CERT"

  test "line reporting is deterministic across newlines":
    let findings = findForbiddenClaims("first\n\nNim semantics certified\ntrailer")
    check findings.len == 1
    check findings[0].line == 3

  test "certificate payload fields are scanned with field-path symbols":
    let payload = parseJson("""{
      "schemaVersion": "axiom.certificate.v3",
      "reason": "Nim semantics certified",
      "leanProposition": "theorem t: True",
      "attestation": {"claimDigest": "x", "note": "최종 TCB 폐쇄"},
      "entries": [{"reason": "source semantics certified"}]
    }""")
    let findings = scanCertPayload(payload)
    check findings.len == 3
    check findings.anyIt(it.symbol == "reason" and it.ruleId == "INV9-NIM-SEM-CERT")
    check findings.anyIt(it.symbol == "attestation.note" and
      it.ruleId == "INV9-TCB-FINAL-CLOSURE")
    check findings.anyIt(it.symbol == "entries[0].reason" and
      it.ruleId == "INV9-SOURCE-SEM-CERT")

  test "multiple occurrences of the same sentence are each reported":
    let findings = findForbiddenClaims(
      "Rust semantics certified; therefore Rust semantics certified.")
    check findings.len == 2

suite "INV-9 positive cases (bounded/legitimate claims pass)":

  test "ADR-0030 D3 bounded claim shape passes":
    check findForbiddenClaims(
      "verified w.r.t. the extracted representation under a Qualified extractor"
    ).len == 0

  test "certified-subset terminology passes":
    check findForbiddenClaims(
      "the declared Rust certified subset (docs/spec/rust_certified_subset.md)"
    ).len == 0
    check findForbiddenClaims(
      "Certified subject (Model B) — certified subset of Nim"
    ).len == 0

  test "Qualified-frontend status sentence passes":
    check findForbiddenClaims(
      "Nim frontend is Qualified (verified 아님) — certification_continuity_contract.md §3"
    ).len == 0

  test "fixed reason lexicon tokens pass":
    for reason in ["uap-lean-verified", "dual-verified", "claim-derived",
                   "evidence-corrected", "awaiting-leanstral-proof-synthesis"]:
      check findForbiddenClaims(reason).len == 0

  test "contract §2 certificate semantic sentence (snapshot) passes":
    let section2 = "이 certificate는 pinned frontend(Nim 2.2.10)가 산출한 " &
      "선언된 subset의 canonical AST에 대해, kernel-executed 독립 reference " &
      "extractor와 Nim extractor의 합의 IR의 denotation 위에서, 정책이 요구한 " &
      "proposition을 pinned Lean kernel이 증명했음을 증명한다."
    check findForbiddenClaims(section2).len == 0

  test "real-shaped certificate payload passes clean":
    let payload = parseJson("""{
      "schemaVersion": "axiom.certificate.v3",
      "reason": "dual-verified",
      "leanProposition": "axiom_continuity_probe_sanity",
      "leanSource": "theorem axiom_continuity_probe_sanity (x : Int) : True := by trivial",
      "claim": {"type": "subject-continuity", "status": "certGreen"},
      "solverStatus": "unsat"
    }""")
    check scanCertPayload(payload).len == 0

suite "INV-9 matching discipline (word boundary, case-sensitive)":

  test "identifier-char neighbours cancel the match":
    check findForbiddenClaims("XRust semantics certified").len == 0
    check findForbiddenClaims("Rust semantics certifiedX").len == 0
    check findForbiddenClaims("Nim semantics uncertified").len == 0
    check findForbiddenClaims("aresource semantics certified").len == 0

  test "punctuation and whitespace are boundaries":
    check findForbiddenClaims("(Rust semantics certified)").len == 1
    check findForbiddenClaims("\"Rust semantics certified.\"").len == 1

  test "case-sensitive: lowercased paraphrase is not matched (closed set)":
    check findForbiddenClaims("rust semantics certified").len == 0
    check findForbiddenClaims("RUST SEMANTICS CERTIFIED").len == 0

suite "INV-9 allowlist discipline (file+symbol+ruleId+contentHash)":

  test "exact anchor match allowlists the finding":
    let payload = parseJson("""{"reason": "Nim semantics certified"}""")
    let findings = scanCertPayload(payload)
    check findings.len == 1
    let f = findings[0]
    let entry = ClaimAllowlistEntry(
      file: "data/trusted/certificates/fx.json", symbol: "reason",
      ruleId: f.ruleId, contentHash: findingContentHash(f),
      note: "sanctioned quotation (contract row citation)")
    check isAllowlisted(f, "data/trusted/certificates/fx.json", entry)
    check allowlistedCount(findings, "data/trusted/certificates/fx.json",
                           @[entry]) == 1

  test "tamper (edited value) breaks the content hash and re-arms the finding":
    let payload = parseJson("""{"reason": "Nim semantics certified"}""")
    var f = scanCertPayload(payload)[0]
    let entry = ClaimAllowlistEntry(
      file: "fx.json", symbol: "reason", ruleId: f.ruleId,
      contentHash: findingContentHash(f))
    check isAllowlisted(f, "fx.json", entry)
    f.value = "Nim semantics certified!"
    check not isAllowlisted(f, "fx.json", entry)
    check allowlistedCount(@[f], "fx.json", @[entry]) == 0

  test "symbol drift and rule drift do not allowlist":
    let payload = parseJson("""{"reason": "Rust semantics certified"}""")
    let f = scanCertPayload(payload)[0]
    let entry = ClaimAllowlistEntry(
      file: "fx.json", symbol: "reason", ruleId: f.ruleId,
      contentHash: findingContentHash(f))
    check isAllowlisted(f, "fx.json", entry)
    check not isAllowlisted(f, "other.json", entry)
    var driftedSymbol = entry
    driftedSymbol.symbol = "leanSource"
    check not isAllowlisted(f, "fx.json", driftedSymbol)
    var wrongRule = entry
    wrongRule.ruleId = "INV9-NIM-SEM-CERT"
    check not isAllowlisted(f, "fx.json", wrongRule)

suite "INV-9 real repository surfaces (test-side assertion)":

  test "default certificate-payload roots exist and scan clean":
    # Tracked (committed) surfaces must exist in any checkout.
    let root = findRepoRoot()
    for dir in ["data/trusted/subjects", "data/trusted/evidence",
                "data/certification", "data/attestations"]:
      let full = root / dir
      check dirExists(full)
    # Runtime state (untracked, minted by attest/journal runs) is scanned
    # when present; a fresh checkout legitimately has neither.
    var scannedAny = false
    for dir in ["data/trusted/certificates", "data/trusted/subjects",
                "data/trusted/evidence", "data/trusted/journal",
                "data/certification", "data/attestations"]:
      let full = root / dir
      if not dirExists(full):
        continue
      var probe: seq[string] = @[]
      for f in walkDirRec(full):
        probe.add(f)
      for f in probe:
        scannedAny = true
        let content = readFile(f)
        if f.splitFile.ext == ".json":
          let parsed = parseJson(content)
          check scanCertPayload(parsed).len == 0
        else:
          check findForbiddenClaims(content).len == 0
    check scannedAny

  test "shipped allowlist parses, is schema-valid, and anchors live findings":
    let root = findRepoRoot()
    let raw = parseFile(root / "tools/ci/inv9_forbidden_claim_allowlist.json")
    check raw.kind == JArray
    for item in raw.items:
      check item.kind == JObject
      for key in ["file", "symbol", "ruleId", "contentHash"]:
        check item.hasKey(key)
        check item[key].getStr().len > 0
      check item["contentHash"].getStr().len == 64
      var knownRule = false
      for rule in forbiddenClaimRules:
        if item["ruleId"].getStr() == rule.ruleId:
          knownRule = true
      check knownRule
      # anchor must be live: the sanctioned occurrence must still exist
      # (rescan-on-run mitigation, theater_allowlist_stability.md)
      let target = root / item["file"].getStr()
      check fileExists(target)
      var live = false
      if target.splitFile.ext == ".json":
        for f in scanCertPayload(parseFile(target)):
          if f.symbol == item["symbol"].getStr() and
              f.ruleId == item["ruleId"].getStr() and
              findingContentHash(f) == item["contentHash"].getStr():
            live = true
      else:
        let content = readFile(target)
        for f in findForbiddenClaims(content):
          if f.ruleId == item["ruleId"].getStr():
            var probe = PayloadFinding(symbol: "text", ruleId: f.ruleId,
              phrase: f.phrase, value: content, offset: f.offset, line: f.line)
            if findingContentHash(probe) == item["contentHash"].getStr():
              live = true
      check live

suite "INV-9 CLI runner end-to-end (fail-closed, exit codes)":

  const e2eDir = "build/inv9_e2e"

  var gCliBin = ""

  proc buildCli(root: string): string =
    ## Compile the CLI once per test-binary run (suite is one process).
    if gCliBin.len > 0:
      return gCliBin
    let binPath = root / e2eDir / "check_inv9_forbidden_claims"
    let cmd = "nim c --hints:off -d:danger --nimcache:" &
      (root / e2eDir / "nimcache") & " -o:" & binPath &
      " tools/ci/check_inv9_forbidden_claims.nim"
    let built = execCmdEx(cmd, workingDir = root)
    check built.exitCode == 0
    gCliBin = binPath
    return binPath

  proc runCli(binPath: string; root: string; args: varargs[string]):
      tuple[text: string; code: int] =
    var cmd = binPath
    for a in args:
      cmd.add(" " & a)
    let raw = execCmdEx(cmd, workingDir = root)
    return (text: raw.output, code: raw.exitCode)

  setup:
    let root = findRepoRoot()
    createDir(root / e2eDir)

  test "clean legitimate payload exits 0":
    let bin = buildCli(root)
    writeFile(root / e2eDir / "clean.json", """{
      "schemaVersion": "axiom.certificate.v3",
      "reason": "dual-verified",
      "leanProposition": "axiom_continuity_probe_sanity"
    }""")
    let r = runCli(bin, root, e2eDir / "clean.json")
    check r.code == 0
    check r.text.contains("PASS")

  test "forbidden claim in payload exits 1 with INV9-FAIL":
    let bin = buildCli(root)
    writeFile(root / e2eDir / "dirty.json", """{
      "reason": "Rust semantics certified"
    }""")
    writeFile(root / e2eDir / "empty_allowlist.json", "[]")
    let r = runCli(bin, root, "--allowlist", e2eDir / "empty_allowlist.json",
                   e2eDir / "dirty.json")
    check r.code == 1
    check r.text.contains("INV9-FAIL")
    check r.text.contains("INV9-RUST-SEM-CERT")
    check r.text.contains(e2eDir / "dirty.json")

  test "correct allowlist entry exits 0 with INV9-ALLOW":
    let bin = buildCli(root)
    let value = "Rust semantics certified"
    let payloadPath = root / e2eDir / "sanctioned.json"
    writeFile(payloadPath, "{\"reason\": \"" & value & "\"}")
    let findings = scanCertPayload(parseJson(
      readFile(payloadPath)))
    check findings.len == 1
    let entry = %*[
      {"file": e2eDir / "sanctioned.json", "symbol": "reason",
       "ruleId": findings[0].ruleId,
       "contentHash": findingContentHash(findings[0]),
       "note": "e2e fixture"}
    ]
    writeFile(root / e2eDir / "anchor.json", $entry)
    let r = runCli(bin, root, "--allowlist", e2eDir / "anchor.json",
                   e2eDir / "sanctioned.json")
    check r.code == 0
    check r.text.contains("INV9-ALLOW")

  test "tampered sanctioned occurrence re-arms the finding (exit 1)":
    let bin = buildCli(root)
    let value = "Nim semantics certified"
    let payloadPath = root / e2eDir / "tampered.json"
    writeFile(payloadPath, "{\"reason\": \"" & value & "\"}")
    let findings = scanCertPayload(parseJson(readFile(payloadPath)))
    let entry = %*[
      {"file": e2eDir / "tampered.json", "symbol": "reason",
       "ruleId": findings[0].ruleId,
       "contentHash": findingContentHash(findings[0])}
    ]
    writeFile(root / e2eDir / "anchor2.json", $entry)
    writeFile(payloadPath, "{\"reason\": \"" & value & " for the subset\"}")
    let r = runCli(bin, root, "--allowlist", e2eDir / "anchor2.json",
                   e2eDir / "tampered.json")
    check r.code == 1
    check r.text.contains("INV9-FAIL")

  test "missing scan target exits 2 (fail-closed, never skip)":
    let bin = buildCli(root)
    writeFile(root / e2eDir / "empty_allowlist.json", "[]")
    let r = runCli(bin, root, "--allowlist", e2eDir / "empty_allowlist.json",
                   e2eDir / "no_such_file.json")
    check r.code == 2
    check r.text.contains("INV9-ERROR")

  test "malformed certificate JSON exits 2 (fail-closed)":
    let bin = buildCli(root)
    writeFile(root / e2eDir / "malformed.json", "{not json")
    writeFile(root / e2eDir / "empty_allowlist.json", "[]")
    let r = runCli(bin, root, "--allowlist", e2eDir / "empty_allowlist.json",
                   e2eDir / "malformed.json")
    check r.code == 2
    check r.text.contains("INV9-ERROR")

  test "missing allowlist exits 2 (fail-closed config)":
    let bin = buildCli(root)
    writeFile(root / e2eDir / "clean2.json", "{\"reason\": \"dual-verified\"}")
    let r = runCli(bin, root, "--allowlist", e2eDir / "no_allowlist.json",
                   e2eDir / "clean2.json")
    check r.code == 2

  test "default allowlist + default roots run from repo root exits 0":
    let bin = buildCli(root)
    let r = runCli(bin, root)
    check r.code == 0
    check r.text.contains("PASS")
