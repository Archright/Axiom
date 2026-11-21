## test_publication_gate_tools.nim — publication-integrity 평가기 실패-경로 계약
##
## 대상: tools/ci/publication_{provenance_validator,license_eval,secret_eval,
## dependency_eval,sbom_eval,script_eval,report}.nim — the gate's FAIL/UNKNOWN paths.
##
## WHY (§0.8/§0.9 — 죽은 게이트·극장 금지): 정상 트리에서의 PASS는 실제
## 워크플로가 매 PR 입증한다. 이 테스트가 입증하는 것은 "게이트가 거부할 수
## 있다"다 — 정상 fixture까지 거부하면 죽은 게이트, 잘못된 fixture를 하나라도
## 통과시키면 극장. 각 평가기의 폐쇄 판정 집합을 음성·양성 쌍으로 고정한다:
##
##   provenance : 미선언 파일 FAIL(무 catch-all) / exclude-후-무재선언 FAIL / 최소 정상 PASS
##   license    : DENY 가족 원자 미 attribution FAIL / noise 저작권 위반 아님 /
##                폐쇄 분류 어휘 위반 UNKNOWN / 정상 PASS
##   secret     : baseline 밖 신규 핑거프린트 FAIL / baseline 일치 PASS
##   dependency : exit 100 FAIL / 미매핑 exit UNKNOWN / exit 128 PASS(선언 한계)
##   sbom       : 공허·결측 SPDX FAIL / 정상 PASS
##   report     : sub-job failure FAIL / skipped UNKNOWN / 보고서 누락 UNKNOWN / 전부 성공 PASS
##   script-scan: Korean added line FAIL / English-only PASS / invalid UTF-8
##                UNKNOWN / policy parse error UNKNOWN / pure rename PASS /
##                exempt-path change PASS
##
## 평가기는 프로덕션 경로 그대로 빌드해(osproc nim c, 워크플로와 동일 플래그)
## fixture 입력으로 실행한다 — 재구현 아님.

import std/[unittest, json, os, osproc, strutils, sequtils]

const
  RepoRoot = block:
    var r = currentSourcePath()
    for _ in 0 ..< 3:
      r = r.parentDir()
    r
  ScriptPolicy = RepoRoot / "compliance/policy/script-scan-policy.yml"
  ## UTF-8 bytes of the Korean fixture word (Hangul syllables). Written as
  ## escapes so this source file itself stays inside the script allowlist.
  KoreanFixture = "\xEC\x95\x88\xEB\x85\x95\xED\x95\x98\xEC\x84\xB8\xEC\x9A\x94"
  Tools = [
    ("vsi_provenance", "tools/ci/publication_provenance_validator.nim"),
    ("vsi_license_eval", "tools/ci/publication_license_eval.nim"),
    ("vsi_secret_eval", "tools/ci/publication_secret_eval.nim"),
    ("vsi_dependency_eval", "tools/ci/publication_dependency_eval.nim"),
    ("vsi_sbom_eval", "tools/ci/publication_sbom_eval.nim"),
    ("vsi_report", "tools/ci/publication_report.nim"),
    ("vsi_attestor", "tools/ci/publication_attestor.nim"),
    ("vsi_script_eval", "tools/ci/publication_script_eval.nim"),
  ]

var bins: array[Tools.len, string]

proc buildAll() =
  ## Production build path (the workflow's exact flags and nimcache) for the
  ## eight evaluators. A build failure is a test failure (fail-closed, not skip).
  putEnv("AXIOM_HERMETIC_BUILDING", "1")
  for i, t in Tools:
    let outp = RepoRoot / "build" / t[0]
    let cmd = "nim c --hints:off --warnings:off --path:. --path:src " &
      "--nimcache:" & (RepoRoot / "build/nimcache" / t[0]) &
      " -o:" & quoteShell(outp) & " " & quoteShell(RepoRoot / t[1])
    let r = execCmdEx(cmd, workingDir = RepoRoot)
    if r.exitCode != 0:
      let tail = if r.output.len > 1500: r.output[^1500..^1] else: r.output
      echo "BUILD FAIL (" & t[0] & "): " & tail
      quit(1)
    bins[i] = outp

proc run(bin: string, args: openArray[string]): tuple[code: int, output: string] =
  var cmd = quoteShell(bin)
  for a in args:
    cmd.add(" " & quoteShell(a))
  let r = execCmdEx(cmd)
  (r.exitCode, r.output)

proc fixtureDir(name: string): string =
  result = getTempDir() / ("pubtest_" & $getCurrentProcessId() & "_" & name)
  createDir(result)

buildAll()

suite "provenance — no catch-all, exclude is a hole unless re-declared":

  test "minimal valid tree PASSES (dead-gate guard)":
    let d = fixtureDir("prov_ok")
    let repo = d / "repo"
    createDir(repo / "src")
    writeFile(repo / "a.txt", "fixture\n")
    writeFile(repo / "src/x.nim", "discard\n")
    for args in [@["init", "-q"], @["config", "user.email", "t@t"],
                 @["config", "user.name", "t"], @["add", "-A"],
                 @["commit", "-q", "-m", "fixture"]]:
      discard execCmdEx("git " & args.join(" "), workingDir = repo)
    writeFile(d / "origin.yml", """
schemaVersion: "1"
declarations:
  - path: "a.txt"
    origin: "ORIGINAL"
    copyright: "Fixture Author"
    license: "LicenseRef-Axiom-SAL-1.0"
  - path: "src/**"
    origin: "ORIGINAL"
    copyright: "Fixture Author"
    license: "LicenseRef-Axiom-SAL-1.0"
""")
    let r = run(bins[0], ["--origin", d / "origin.yml",
                          "--policy", RepoRoot / "compliance/policy/provenance-policy.yml",
                          "--license-policy", RepoRoot / "compliance/policy/license-policy.yml",
                          "--repo-root", repo,
                          "--out", d / "report.json"])
    check r.code == 0
    check "PASS" in r.output

  test "undeclared file FAILS (no catch-all)":
    let d = fixtureDir("prov_hole")
    let repo = d / "repo"
    createDir(repo)
    writeFile(repo / "declared.txt", "fixture\n")
    writeFile(repo / "undeclared.txt", "fixture\n")
    for args in [@["init", "-q"], @["config", "user.email", "t@t"],
                 @["config", "user.name", "t"], @["add", "-A"],
                 @["commit", "-q", "-m", "fixture"]]:
      discard execCmdEx("git " & args.join(" "), workingDir = repo)
    writeFile(d / "origin.yml", """
schemaVersion: "1"
declarations:
  - path: "declared.txt"
    origin: "ORIGINAL"
    copyright: "Fixture Author"
    license: "LicenseRef-Axiom-SAL-1.0"
""")
    let r = run(bins[0], ["--origin", d / "origin.yml",
                          "--policy", RepoRoot / "compliance/policy/provenance-policy.yml",
                          "--license-policy", RepoRoot / "compliance/policy/license-policy.yml",
                          "--repo-root", repo,
                          "--out", d / "report.json"])
    check r.code == 1
    check "FAIL" in r.output
    let rep = parseJson(readFile(d / "report.json"))
    check rep{"undeclared"}.getElems().mapIt(it.getStr()) == @["undeclared.txt"]

  test "excluded file without re-declaration stays a hole (FAIL)":
    let d = fixtureDir("prov_exclude")
    let repo = d / "repo"
    createDir(repo / "src")
    writeFile(repo / "src/x.nim", "discard\n")
    for args in [@["init", "-q"], @["config", "user.email", "t@t"],
                 @["config", "user.name", "t"], @["add", "-A"],
                 @["commit", "-q", "-m", "fixture"]]:
      discard execCmdEx("git " & args.join(" "), workingDir = repo)
    writeFile(d / "origin.yml", """
schemaVersion: "1"
declarations:
  - path: "src/**"
    origin: "ORIGINAL"
    copyright: "Fixture Author"
    license: "LicenseRef-Axiom-SAL-1.0"
    exclude:
      - "src/x.nim"
""")
    let r = run(bins[0], ["--origin", d / "origin.yml",
                          "--policy", RepoRoot / "compliance/policy/provenance-policy.yml",
                          "--license-policy", RepoRoot / "compliance/policy/license-policy.yml",
                          "--repo-root", repo,
                          "--out", d / "report.json"])
    check r.code == 1
    let rep = parseJson(readFile(d / "report.json"))
    check rep{"undeclared"}.getElems().mapIt(it.getStr()) == @["src/x.nim"]

  test "forbidden content in a tracked text file FAILS":
    let d = fixtureDir("prov_forbid_text")
    let repo = d / "repo"
    let probePath = "/home/" & "wintrover"
    createDir(repo / "src")
    writeFile(repo / "src/leaked.nim", "# path: " & probePath & "/secret/file.nim\ndiscard\n")
    for args in [@["init", "-q"], @["config", "user.email", "t@t"],
                 @["config", "user.name", "t"], @["add", "-A"],
                 @["commit", "-q", "-m", "fixture"]]:
      discard execCmdEx("git " & args.join(" "), workingDir = repo)
    writeFile(d / "origin.yml", """
schemaVersion: "1"
declarations:
  - path: "src/**"
    origin: "ORIGINAL"
    copyright: "Fixture Author"
    license: "LicenseRef-Axiom-SAL-1.0"
""")
    let r = run(bins[0], ["--origin", d / "origin.yml",
                          "--policy", RepoRoot / "compliance/policy/provenance-policy.yml",
                          "--license-policy", RepoRoot / "compliance/policy/license-policy.yml",
                          "--repo-root", repo,
                          "--out", d / "report.json"])
    check r.code == 1
    let rep = parseJson(readFile(d / "report.json"))
    check rep{"forbiddenContentViolations"}.getElems().len == 1
    check "src/leaked.nim" in rep{"forbiddenContentViolations"}[0].getStr()

  test "forbidden content hidden inside a tracked .tar.gz archive FAILS":
    let d = fixtureDir("prov_forbid_tar")
    let repo = d / "repo"
    let probePath = "/home/" & "wintrover"
    let allowedDir = repo / "experiments/act2-wp-toml-b1-input-integrity"
    createDir(allowedDir)
    let stageDir = d / "stage"
    createDir(stageDir)
    writeFile(stageDir / "inner.txt", "compiled from " & probePath & "/workspace\n")
    discard execCmdEx("tar -czf " & quoteShell(allowedDir / "probe.tar.gz") &
      " -C " & quoteShell(stageDir) & " inner.txt")
    for args in [@["init", "-q"], @["config", "user.email", "t@t"],
                 @["config", "user.name", "t"], @["add", "-A"],
                 @["commit", "-q", "-m", "fixture"]]:
      discard execCmdEx("git " & args.join(" "), workingDir = repo)
    writeFile(d / "origin.yml", """
schemaVersion: "1"
declarations:
  - path: "experiments/**"
    origin: "ORIGINAL"
    copyright: "Fixture Author"
    license: "LicenseRef-Axiom-SAL-1.0"
""")
    let r = run(bins[0], ["--origin", d / "origin.yml",
                          "--policy", RepoRoot / "compliance/policy/provenance-policy.yml",
                          "--license-policy", RepoRoot / "compliance/policy/license-policy.yml",
                          "--repo-root", repo,
                          "--out", d / "report.json"])
    check r.code == 1
    let rep = parseJson(readFile(d / "report.json"))
    check rep{"forbiddenContentViolations"}.getElems().len == 1
    check ("archive contains " & probePath) in rep{"forbiddenContentViolations"}[0].getStr()

  test "tracked .log file or archive outside allowed prefix FAILS":
    let d = fixtureDir("prov_forbid_path")
    let repo = d / "repo"
    createDir(repo / "src")
    writeFile(repo / "src/debug.log", "clean log text\n")
    let stageDir = d / "stage"
    createDir(stageDir)
    writeFile(stageDir / "clean.txt", "clean archive text\n")
    discard execCmdEx("tar -czf " & quoteShell(repo / "src/extra.tar.gz") &
      " -C " & quoteShell(stageDir) & " clean.txt")
    for args in [@["init", "-q"], @["config", "user.email", "t@t"],
                 @["config", "user.name", "t"], @["add", "-A"],
                 @["commit", "-q", "-m", "fixture"]]:
      discard execCmdEx("git " & args.join(" "), workingDir = repo)
    writeFile(d / "origin.yml", """
schemaVersion: "1"
declarations:
  - path: "src/**"
    origin: "ORIGINAL"
    copyright: "Fixture Author"
    license: "LicenseRef-Axiom-SAL-1.0"
""")
    let r = run(bins[0], ["--origin", d / "origin.yml",
                          "--policy", RepoRoot / "compliance/policy/provenance-policy.yml",
                          "--license-policy", RepoRoot / "compliance/policy/license-policy.yml",
                          "--repo-root", repo,
                          "--out", d / "report.json"])
    check r.code == 1
    let rep = parseJson(readFile(d / "report.json"))
    let viols = rep{"forbiddenPathViolations"}.getElems().mapIt(it.getStr())
    check "src/debug.log" in viols
    check "src/extra.tar.gz" in viols

suite "license — denied families need attribution; noise is not a holder":

  const
    OriginYml = """
schemaVersion: "1"
declarations:
  - path: "src/**"
    origin: "ORIGINAL"
    copyright: "Fixture Author"
    license: "LicenseRef-Axiom-SAL-1.0"
"""
    AttributionYml = """
schemaVersion: "1"
attributions:
  - file: "src/quoted.md"
    classification: "documentary-mention"
    evidence: "fixture"
    licenses:
      - "GPL-3.0-only"
"""

  proc writeScan(d, body: string) =
    writeFile(d / "scan.json",
      """{"files": [{"type": "file", "path": "root/src/y.nim",
  "license_detections": [], "copyrights": []}, """ & body & "]}")

  test "denied-family atom without attribution FAILS":
    let d = fixtureDir("lic_gpl")
    writeFile(d / "origin.yml", OriginYml)
    writeFile(d / "attribution.yml", """
schemaVersion: "1"
attributions:
  - file: "src/elsewhere.md"
    classification: "documentary-mention"
    evidence: "fixture (different file — must NOT account y.nim)"
    licenses:
      - "GPL-3.0-only"
""")
    writeScan(d, """{"type": "file", "path": "root/src/y.nim",
  "license_detections": [{"license_expression_spdx": "GPL-3.0-only"}],
  "copyrights": []}""")
    let r = run(bins[1], ["--scan", d / "scan.json",
                          "--policy", RepoRoot / "compliance/policy/license-policy.yml",
                          "--origin", d / "origin.yml",
                          "--attribution", d / "attribution.yml",
                          "--strip-prefix", "root",
                          "--out", d / "report.json"])
    check r.code == 1
    let rep = parseJson(readFile(d / "report.json"))
    check rep{"licenseViolations"}[0]{"deniedFamily"}.getBool() == true

  test "denied-family atom WITH (file, atom) attribution PASSES":
    let d = fixtureDir("lic_gpl_ok")
    writeFile(d / "origin.yml", OriginYml)
    writeFile(d / "attribution.yml", AttributionYml)
    writeScan(d, """{"type": "file", "path": "root/src/quoted.md",
  "license_detections": [{"license_expression_spdx": "GPL-3.0-only"}],
  "copyrights": []}""")
    let r = run(bins[1], ["--scan", d / "scan.json",
                          "--policy", RepoRoot / "compliance/policy/license-policy.yml",
                          "--origin", d / "origin.yml",
                          "--attribution", d / "attribution.yml",
                          "--strip-prefix", "root",
                          "--out", d / "report.json"])
    check r.code == 0
    check "PASS" in r.output

  test "(c) inc noise carries no holder (not a violation)":
    let d = fixtureDir("lic_noise")
    writeFile(d / "origin.yml", OriginYml)
    writeFile(d / "attribution.yml", AttributionYml)
    writeScan(d, """{"type": "file", "path": "root/src/y.nim",
  "license_detections": [],
  "copyrights": [{"copyright": "(c) inc", "start_line": 1}]}""")
    let r = run(bins[1], ["--scan", d / "scan.json",
                          "--policy", RepoRoot / "compliance/policy/license-policy.yml",
                          "--origin", d / "origin.yml",
                          "--attribution", d / "attribution.yml",
                          "--strip-prefix", "root",
                          "--out", d / "report.json"])
    check r.code == 0
    let rep = parseJson(readFile(d / "report.json"))
    check rep{"noiseDetections"}.getInt() == 1
    check rep{"copyrightViolations"}.len == 0

  test "classification outside the closed vocabulary is UNKNOWN":
    let d = fixtureDir("lic_vocab")
    writeFile(d / "origin.yml", OriginYml)
    writeFile(d / "attribution.yml", """
schemaVersion: "1"
attributions:
  - file: "src/quoted.md"
    classification: "made-up-class"
    evidence: "fixture"
""")
    writeScan(d, """{"type": "file", "path": "root/src/y.nim",
  "license_detections": [], "copyrights": []}""")
    let r = run(bins[1], ["--scan", d / "scan.json",
                          "--policy", RepoRoot / "compliance/policy/license-policy.yml",
                          "--origin", d / "origin.yml",
                          "--attribution", d / "attribution.yml",
                          "--strip-prefix", "root",
                          "--out", d / "report.json"])
    check r.code == 2

suite "secret — a new fingerprint always FAILS":

  test "fingerprint outside baseline FAILS":
    let d = fixtureDir("sec_new")
    writeFile(d / "history.json",
      """[{"Fingerprint": "deadbeef:newfile:generic-api-key:1",
          "RuleID": "generic-api-key", "File": "newfile",
          "StartLine": 1}]""")
    writeFile(d / "tree.json", "[]")
    writeFile(d / "baseline.json",
      """{"_meta": {"schemaVersion": 1}, "historyFindings": [], "treeFindings": []}""")
    let r = run(bins[2], ["--history", d / "history.json",
                          "--tree", d / "tree.json",
                          "--baseline", d / "baseline.json",
                          "--policy", RepoRoot / "compliance/policy/security-policy.yml",
                          "--out", d / "report.json"])
    check r.code == 1

  test "baselined fingerprint PASSES":
    let d = fixtureDir("sec_ok")
    writeFile(d / "history.json",
      """[{"Fingerprint": "deadbeef:newfile:generic-api-key:1",
          "RuleID": "generic-api-key", "File": "newfile",
          "StartLine": 1}]""")
    writeFile(d / "tree.json", "[]")
    writeFile(d / "baseline.json",
      """{"_meta": {"schemaVersion": 1},
          "historyFindings": [
            {"fingerprint": "deadbeef:newfile:generic-api-key:1",
             "classification": "synthetic-test-fixture", "rule": "generic-api-key",
             "file": "newfile", "line": 1}],
          "treeFindings": []}""")
    let r = run(bins[2], ["--history", d / "history.json",
                          "--tree", d / "tree.json",
                          "--baseline", d / "baseline.json",
                          "--policy", RepoRoot / "compliance/policy/security-policy.yml",
                          "--out", d / "report.json"])
    check r.code == 0

  test "spanFingerprint matches across commit SHA rotation and FAILS on same-line column collision":
    let d = fixtureDir("sec_span")
    writeFile(d / "baseline.json",
      """{"_meta": {"schemaVersion": 1},
          "historyFindings": [
            {"fingerprint": "1111111111111111111111111111111111111111:data/inv.json:generic-api-key:1",
             "spanFingerprint": "data/inv.json:generic-api-key:1:1:10:50",
             "classification": "identifier-false-positive",
             "rule": "generic-api-key",
             "file": "data/inv.json",
             "line": 1,
             "startColumn": 10,
             "endColumn": 50}],
          "treeFindings": []}""")
    writeFile(d / "tree.json", "[]")
    # 1) Same span under a brand-new root commit SHA -> PASS
    writeFile(d / "history_rotated.json",
      """[{"Fingerprint": "2222222222222222222222222222222222222222:data/inv.json:generic-api-key:1",
          "RuleID": "generic-api-key", "File": "data/inv.json",
          "StartLine": 1, "EndLine": 1, "StartColumn": 10, "EndColumn": 50}]""")
    let rPass = run(bins[2], ["--history", d / "history_rotated.json",
                              "--tree", d / "tree.json",
                              "--baseline", d / "baseline.json",
                              "--policy", RepoRoot / "compliance/policy/security-policy.yml",
                              "--out", d / "report_pass.json"])
    check rPass.code == 0

    # 2) Same file & same line (line 1) at a DIFFERENT column span -> FAIL (no line-only collision)
    writeFile(d / "history_collision.json",
      """[{"Fingerprint": "1111111111111111111111111111111111111111:data/inv.json:generic-api-key:1",
          "RuleID": "generic-api-key", "File": "data/inv.json",
          "StartLine": 1, "EndLine": 1, "StartColumn": 60, "EndColumn": 95}]""")
    let rFail = run(bins[2], ["--history", d / "history_collision.json",
                              "--tree", d / "tree.json",
                              "--baseline", d / "baseline.json",
                              "--policy", RepoRoot / "compliance/policy/security-policy.yml",
                              "--out", d / "report_fail.json"])
    check rFail.code == 1

suite "dependency — exit-code adjudication is closed":

  test "exit 100 FAIL / unmapped exit UNKNOWN / exit 128 PASS":
    let d = fixtureDir("dep")
    writeFile(d / "osv.json", """{"results": []}""")
    let common = @["--report", d / "osv.json",
                   "--policy", RepoRoot / "compliance/policy/security-policy.yml",
                   "--out", d / "report.json"]
    check run(bins[3], @["--exit-code", "100"] & common).code == 1
    check run(bins[3], @["--exit-code", "77"] & common).code == 2
    check run(bins[3], @["--exit-code", "128"] & common).code == 0

suite "sbom — vacuous or malformed SPDX never passes":

  test "empty SPDX object FAILS; valid SPDX PASSES":
    let d = fixtureDir("sbom")
    writeFile(d / "empty.json", "{}")
    writeFile(d / "valid.json",
      """{"spdxVersion": "SPDX-2.3", "name": "fixture",
          "packages": [{"SPDXID": "SPDXRef-Package-1"}], "files": []}""")
    let common = @["--policy", RepoRoot / "compliance/policy/security-policy.yml"]
    check run(bins[4], @["--report", d / "empty.json"] & common &
      @["--out", d / "r1.json"]).code == 1
    check run(bins[4], @["--report", d / "valid.json"] & common &
      @["--out", d / "r2.json"]).code == 0

suite "report — venue gate, skipped is UNKNOWN, failure is FAIL, missing report is UNKNOWN":

  const
    Dims6 = ["secret-scan", "license-scan", "dependency-scan", "provenance",
             "sbom", "script-scan"]
    TestHead = "ffff0000ffff0000ffff0000ffff0000ffff0000"

  proc writeDimensions(d: string) =
    for dim in Dims6:
      var node = %*{"dimension": dim, "verdict": "PASS", "tool": "fixture"}
      if dim == "script-scan":
        node["binding"] = %*{"headSha": TestHead}
      writeFile(d / (dim & ".json"), $(node))

  test "landing venue fail-closed matrix":
    let d = fixtureDir("rep_landing")
    writeDimensions(d)
    let common = @["--venue", "merge_group",
                   "--out", d / "gate.json",
                   "--head-sha", TestHead,
                   "--tree-sha", "0000ffff0000ffff0000ffff0000ffff0000ffff",
                   "--policy-file", RepoRoot / "compliance/policy/license-policy.yml",
                   "--policy-file", ScriptPolicy] &
      (Dims6.mapIt("--report" & "=" & it & "=" & (d / it & ".json")))
    var allOk: seq[string] = @[]
    for dim in Dims6:
      allOk.add("--job" & "=" & dim & "=success")
    # 1) everything success → PASS
    check run(bins[5], common & allOk).code == 0
    # 2) one failure → FAIL
    check run(bins[5], common & (allOk.mapIt(
      if it.endsWith("secret-scan=success"): "--job=secret-scan=failure" else: it))).code == 1
    # 3) one skipped → UNKNOWN (the platform skipped-is-success trap)
    check run(bins[5], common & (allOk.mapIt(
      if it.endsWith("license-scan=success"): "--job=license-scan=skipped" else: it))).code == 2
    # 4) a dimension report file missing → UNKNOWN
    removeFile(d / "sbom.json")
    check run(bins[5], common & allOk).code == 2
    # 5) a script-scan FAIL report is authoritative even when the sub-job
    #    result is success
    writeDimensions(d)
    writeFile(d / "script-scan.json",
      $(%*{"dimension": "script-scan", "verdict": "FAIL",
           "binding": {"headSha": TestHead}}))
    check run(bins[5], common & allOk).code == 1
    # 6) a script-scan report bound to another commit is not this gate's verdict
    writeFile(d / "script-scan.json",
      $(%*{"dimension": "script-scan", "verdict": "PASS",
           "binding": {"headSha": "0000000000000000000000000000000000000000"}}))
    check run(bins[5], common & allOk).code == 1
    # 7) a script-scan report with no commit binding → UNKNOWN
    writeFile(d / "script-scan.json",
      $(%*{"dimension": "script-scan", "verdict": "PASS"}))
    check run(bins[5], common & allOk).code == 2
    # 8) a report whose dimension identity contradicts its slot → UNKNOWN
    writeFile(d / "script-scan.json",
      $(%*{"dimension": "sbom", "verdict": "PASS",
           "binding": {"headSha": TestHead}}))
    check run(bins[5], common & allOk).code == 2
    # 9) the same binding expressed as commitSha is accepted
    writeFile(d / "script-scan.json",
      $(%*{"dimension": "script-scan", "verdict": "PASS",
           "binding": {"commitSha": TestHead}}))
    check run(bins[5], common & allOk).code == 0

  test "preflight venue requires exactly {secret-scan}":
    let d = fixtureDir("rep_preflight")
    writeDimensions(d)
    let preJobs = @["--job=secret-scan=success", "--job=license-scan=skipped",
                    "--job=dependency-scan=skipped", "--job=provenance=skipped",
                    "--job=sbom=skipped", "--job=script-scan=skipped"]
    let preBase = @["--venue", "pull_request",
                 "--out", d / "gate.json",
                 "--head-sha", TestHead,
                 "--tree-sha", "0000ffff0000ffff0000ffff0000ffff0000ffff",
                 "--policy-file", RepoRoot / "compliance/policy/license-policy.yml",
                 "--policy-file", ScriptPolicy,
                 "--report", "secret-scan=" & (d / "secret-scan.json")]
    # 1) the declared preflight set, all success → PASS
    check run(bins[5], preBase & preJobs).code == 0
    # 2) required dimension skipped → UNKNOWN
    check run(bins[5], preBase & preJobs.mapIt(
      if it.endsWith("secret-scan=success"): "--job=secret-scan=skipped" else: it)).code == 2
    # 3) a NON-required dimension reporting success may never contribute credit → FAIL
    check run(bins[5], preBase & preJobs.mapIt(
      if it.endsWith("license-scan=skipped"): "--job=license-scan=success" else: it)).code == 1
    # 4) an out-of-venue report that was ACTUALLY PRODUCED is gating drift →
    #    UNKNOWN, never silently ignored. The signal is the file existing: the
    #    workflow passes all six --report paths as one static list on every
    #    venue, so argument presence alone is not drift (measured run
    #    44857335107 job 136702863663).
    check run(bins[5], preBase & preJobs &
      @["--report", "license-scan=" & (d / "license-scan.json")]).code == 2
    # 5) the SAME argument pointing at a path that was never produced (a
    #    skipped dimension uploads no artifact) is NOT drift → PASS. This is
    #    the measured live shape of a correctly gated preflight.
    let absent = d / "never-produced"
    check fileExists(absent / "license-scan.json") == false
    check fileExists(absent / "dependency-scan.json") == false
    check fileExists(absent / "provenance.json") == false
    check fileExists(absent / "sbom.json") == false
    check fileExists(absent / "script-scan.json") == false
    check run(bins[5], preBase & preJobs &
      @["--report", "license-scan=" & (absent / "license-scan.json"),
        "--report", "dependency-scan=" & (absent / "dependency-scan.json"),
        "--report", "provenance=" & (absent / "provenance.json"),
        "--report", "sbom=" & (absent / "sbom.json"),
        "--report", "script-scan=" & (absent / "script-scan.json")]).code == 0
    # 6) script-scan is NOT in the preflight set either
    check run(bins[5], preBase & preJobs.mapIt(
      if it.endsWith("script-scan=skipped"): "--job=script-scan=success" else: it)).code == 1

  test "venue is required and closed":
    let d = fixtureDir("rep_venue")
    writeDimensions(d)
    let base = @["--out", d / "gate.json",
                 "--head-sha", TestHead,
                 "--tree-sha", "0000ffff0000ffff0000ffff0000ffff0000ffff"]
    # no --venue → rejected input (UNKNOWN), never a pass
    check run(bins[5], base).code == 2
    # an event this workflow does not run on → FAIL (no venue, no verdict)
    check run(bins[5], @["--venue", "push"] & base).code == 1

suite "script-scan — added-line Unicode Script allowlist is fail-closed":
  ## Scratch git repos, no network: the evaluator runs against real diffs.
  ## The production policy pins ripgrep 14.1.0; an unavailable rg is a suite
  ## FAILURE, never a silent skip.

  let rgBin = findExe("rg")

  block:
    if rgBin.len == 0:
      echo "FATAL: ripgrep not found on PATH — the script-scan suite refuses to skip"
      quit(1)

  proc gitIn(repo: string, args: seq[string]) =
    var cmd = "git -c user.email=fixture@example.com -c user.name=Fixture " &
      "-c commit.gpgsign=false"
    for a in args:
      cmd.add(" " & quoteShell(a))
    let r = execCmdEx(cmd, workingDir = repo)
    if r.exitCode != 0:
      echo "FIXTURE GIT FAIL: " & cmd & "\n" & r.output
      quit(1)

  proc revParse(repo, rev: string): string =
    let r = execCmdEx("git rev-parse " & rev, workingDir = repo)
    if r.exitCode != 0:
      echo "FIXTURE GIT FAIL: git rev-parse " & rev & "\n" & r.output
      quit(1)
    r.output.strip()

  proc commitAll(repo, msg: string) =
    gitIn(repo, @["add", "-A"])
    gitIn(repo, @["commit", "-q", "-m", msg])

  proc seedRepo(name: string): tuple[repo, base: string] =
    ## The base commit tracks the policy's exact exempt path: the evaluator's
    ## exempt-path liveness check is itself fail-closed.
    let d = fixtureDir("script_" & name)
    let repo = d / "repo"
    createDir(repo / "data/i18n")
    writeFile(repo / "data/i18n/ko.json", "{\"greeting\": \"hello\"}\n")
    writeFile(repo / "src.txt", "english baseline\n")
    gitIn(repo, @["init", "-q"])
    commitAll(repo, "base")
    (repo, revParse(repo, "HEAD"))

  proc runScript(repo, base, head, policy, outPath: string):
      tuple[code: int, output: string] =
    run(bins[7], @["--policy", policy,
                   "--rg", rgBin,
                   "--head", head,
                   "--base", base,
                   "--repo-root", repo,
                   "--out", outPath])

  test "Korean added line FAILS and reports the offending code point":
    let (repo, base) = seedRepo("ko")
    writeFile(repo / "korean.txt", "hello\n" & KoreanFixture & "\n")
    commitAll(repo, "add korean")
    let head = revParse(repo, "HEAD")
    let outPath = repo.parentDir / "report.json"
    let r = runScript(repo, base, head, ScriptPolicy, outPath)
    if r.code != 1:
      echo "script-scan expected FAIL, got " & $r.code & ":\n" & r.output
    check r.code == 1
    check "FAIL" in r.output
    let rep = parseJson(readFile(outPath))
    check rep{"dimension"}.getStr() == "script-scan"
    check rep{"verdict"}.getStr() == "FAIL"
    let binding = rep{"binding"}
    check binding != nil
    check binding{"headSha"}.getStr() == head
    let codePoints = rep{"violations"}.getElems().mapIt(it{"codePoint"}.getStr())
    check "U+C548" in codePoints
    check "U+B155" in codePoints
    check "U+D558" in codePoints

  test "English-only added lines PASS":
    let (repo, base) = seedRepo("en")
    writeFile(repo / "english.txt", "plain ASCII text\nsecond line\n")
    commitAll(repo, "add english")
    let head = revParse(repo, "HEAD")
    let outPath = repo.parentDir / "report.json"
    let r = runScript(repo, base, head, ScriptPolicy, outPath)
    if r.code != 0:
      echo "script-scan expected PASS, got " & $r.code & ":\n" & r.output
    check r.code == 0
    let rep = parseJson(readFile(outPath))
    check rep{"verdict"}.getStr() == "PASS"
    check rep{"violations"}.getElems().len == 0

  test "invalid UTF-8 added line is UNKNOWN, never a pass":
    let (repo, base) = seedRepo("utf8")
    writeFile(repo / "broken.txt", "bad \xFF byte\n")
    commitAll(repo, "add invalid utf8")
    let head = revParse(repo, "HEAD")
    let outPath = repo.parentDir / "report.json"
    let r = runScript(repo, base, head, ScriptPolicy, outPath)
    if r.code != 2:
      echo "script-scan expected UNKNOWN, got " & $r.code & ":\n" & r.output
    check r.code == 2
    let rep = parseJson(readFile(outPath))
    check rep{"verdict"}.getStr() == "UNKNOWN"
    check rep{"unknowns"}.getElems().len > 0

  test "policy parse error is UNKNOWN and writes no report":
    let (repo, base) = seedRepo("policy")
    writeFile(repo / "english.txt", "plain ASCII text\n")
    commitAll(repo, "add english")
    let head = revParse(repo, "HEAD")
    let badPolicy = repo.parentDir / "bad-policy.yml"
    writeFile(badPolicy,
      "schemaVersion: \"1\"\n" &
      "dimension: script-scan\n")
    let outPath = repo.parentDir / "report.json"
    let r = runScript(repo, base, head, badPolicy, outPath)
    check r.code == 2
    check "POLICY ERROR" in r.output
    check fileExists(outPath) == false

  test "pure rename PASSES (debt stays in place)":
    let (repo, base) = seedRepo("rename")
    gitIn(repo, @["mv", "src.txt", "renamed.txt"])
    commitAll(repo, "rename")
    let head = revParse(repo, "HEAD")
    let outPath = repo.parentDir / "report.json"
    let r = runScript(repo, base, head, ScriptPolicy, outPath)
    if r.code != 0:
      echo "script-scan expected PASS on rename, got " & $r.code & ":\n" & r.output
    check r.code == 0
    let rep = parseJson(readFile(outPath))
    check rep{"verdict"}.getStr() == "PASS"
    check rep{"renamedPaths"}.getElems().mapIt(it.getStr()).anyIt(
      "src.txt -> renamed.txt" in it)

  test "exempt-path change PASSES":
    let (repo, base) = seedRepo("exempt")
    writeFile(repo / "data/i18n/ko.json", "{\"greeting\": \"" & KoreanFixture & "\"}\n")
    commitAll(repo, "i18n")
    let head = revParse(repo, "HEAD")
    let outPath = repo.parentDir / "report.json"
    let r = runScript(repo, base, head, ScriptPolicy, outPath)
    if r.code != 0:
      echo "script-scan expected PASS on exempt path, got " & $r.code & ":\n" & r.output
    check r.code == 0
    let rep = parseJson(readFile(outPath))
    check rep{"verdict"}.getStr() == "PASS"
    check "data/i18n/ko.json" in
      rep{"exemptedChangedPaths"}.getElems().mapIt(it.getStr())

suite "attestor — out-of-tree SHA-bound attestation rejects stale commit/tree SHAs":

  test "issues ELIGIBLE when 6 checks + 5 dimensions match (commit, tree) and FAILS verify on SHA drift":
    let d = fixtureDir("att")
    let commitSha = "aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000"
    let treeSha = "bbbb1111bbbb1111bbbb1111bbbb1111bbbb1111"
    let gateReport = %*{
      "schemaVersion": 1,
      "gate": "publication-integrity",
      "verdict": "PASS",
      "binding": {
        "commitSha": commitSha,
        "treeSha": treeSha,
      },
      "dimensions": [
        {"dimension": "secret-scan", "verdict": "PASS"},
        {"dimension": "license-scan", "verdict": "PASS"},
        {"dimension": "dependency-scan", "verdict": "PASS"},
        {"dimension": "provenance", "verdict": "PASS"},
        {"dimension": "sbom", "verdict": "PASS"},
      ],
      "blockers": [],
      "unresolvedUnknowns": [],
      "unresolvedUnknownCount": 0,
    }
    writeFile(d / "gate.json", gateReport.pretty() & "\n")
    let checksArgs = @[
      "--require-check", "admission-check=SUCCESS",
      "--require-check", "axiom-operational-slice=SUCCESS",
      "--require-check", "bsec-integrity=SUCCESS",
      "--require-check", "debt-registry-gate=SUCCESS",
      "--require-check", "generation-acceptance=SUCCESS",
      "--require-check", "publication-integrity=SUCCESS",
    ]
    let issueRes = run(bins[6], @[
      "--mode", "issue",
      "--commit", commitSha,
      "--tree", treeSha,
      "--gate-report", d / "gate.json",
      "--out", d / "attestation.json",
    ] & checksArgs)
    check issueRes.code == 0
    let attJson = parseJson(readFile(d / "attestation.json"))
    check attJson{"verdict"}.getStr() == "ELIGIBLE"
    check attJson{"targetCommitSha"}.getStr() == commitSha
    check attJson{"targetTreeSha"}.getStr() == treeSha

    # Exact (commit, tree) verifies ELIGIBLE (code 0)
    let verifyOk = run(bins[6], @[
      "--mode", "verify",
      "--attestation", d / "attestation.json",
      "--expected-commit", commitSha,
      "--expected-tree", treeSha,
    ])
    check verifyOk.code == 0

    # Advancing commit SHA by 1 bit invalidates the attestation (code 1)
    let verifyStaleCommit = run(bins[6], @[
      "--mode", "verify",
      "--attestation", d / "attestation.json",
      "--expected-commit", "aaaa0000aaaa0000aaaa0000aaaa0000aaaa0001",
      "--expected-tree", treeSha,
    ])
    check verifyStaleCommit.code == 1
    check "STALE_ATTESTATION_SHA_MISMATCH" in verifyStaleCommit.output

    # Mutating tree SHA by 1 bit invalidates the attestation (code 1)
    let verifyStaleTree = run(bins[6], @[
      "--mode", "verify",
      "--attestation", d / "attestation.json",
      "--expected-commit", commitSha,
      "--expected-tree", "bbbb1111bbbb1111bbbb1111bbbb1111bbbb1110",
    ])
    check verifyStaleTree.code == 1
    check "STALE_ATTESTATION_SHA_MISMATCH" in verifyStaleTree.output
