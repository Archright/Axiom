{.push raises: [CatchableError].}

## test_reanchor_pin.nim — 재앵커 writer/preflight 계약 테스트.
##
## 여기서 고정하는 것은 세 가지다:
##   1. 판정은 공유 술어(core/policy/rotation_closure_facts) 위에서만 내려진다
##      — 이 도구는 line-set 차이를 분류해 보고할 뿐 새 술어를 만들지 않는다.
##   2. pin은 **ref의 트리**에서 읽는다. 워킹 트리의 미커밋 편집은 판정에
##      섞이지 않는다 (그러면 preflight와 CI의 pin@H가 갈라진다).
##   3. 재작성은 표적 치환이며 JSONC 주석/포맷을 보존하고, 쓰기 전에
##      line-set == derived를 자기검증한다.
##
## Fixture는 isolated temp dir에서만 만든다 — 실제 저장소는 건드리지 않는다
## (test_rotation_pin_anchor_check.nim / test_derive_checker_closure.nim과 같은 정책).

import std/[options, os, osproc, strutils, unittest]

import ci/reanchor_pin
import core/policy/rotation_closure_facts
import core/results

let FixtureDir = getTempDir() / "axiom_reanchor_pin"

const
  PathA = "ci/checker.mk"
  PathB = "tools/ci/derive_checker_closure.nim"
  LineA = "100644 blob a1\t" & PathA
  LineB = "100644 blob b2\t" & PathB
  LineA9 = "100644 blob a9\t" & PathA
  LineB8 = "100644 blob b8\t" & PathB

proc pinDocText(entries: seq[tuple[path, mode, sha: string]];
                keyPresent = true; jsonc = false): string =
  ## trusted_writer_set 문서. keyPresent=false는 genesis 트리 사실,
  ## jsonc=true는 실제 pin 파일처럼 `//` 주석을 담은 형태.
  result = "{\n  \"schemaVersion\": \"axiom.trusted-writer-set.v1\",\n"
  if jsonc:
    result.add "  // 이 주석은 재작성 후에도 보존되어야 한다 (" & PathA & " 언급)\n"
  if keyPresent:
    result.add "  \"trustedCheckerTreeClosure\": {\n"
    for i, e in entries:
      result.add "    \"" & e.path & "\": {\n"
      result.add "      \"mode\": \"" & e.mode & "\",\n"
      result.add "      \"type\": \"blob\",\n"
      result.add "      \"sha\": \"" & e.sha & "\"\n"
      result.add "    }" & (if i == entries.high: "\n" else: ",\n")
    result.add "  }\n"
  result.add "}\n"

proc writeFixture(name, content: string): string =
  createDir(FixtureDir)
  result = FixtureDir / name
  writeFile(result, content)

proc gitIn(dir: string; args: string): int =
  execCmdEx("git -C " & quoteShell(dir) & " " & args)[1]

proc initRepo(name: string): string =
  ## 커밋 하나를 가진 최소 저장소 — pin@ref를 트리에서 읽는지 검증하는 venue.
  result = FixtureDir / name
  removeDir(result)
  createDir(result / "config")
  doAssert gitIn(result, "init -q") == 0

proc commitAll(dir, msg: string): int =
  ## 스테이징까지 포함한 단일 커밋 — 테스트가 매번 add를 잊지 않게 한다.
  if gitIn(dir, "-c user.email=t@example.invalid -c user.name=t add -A") != 0:
    return 1
  gitIn(dir, "-c user.email=t@example.invalid -c user.name=t commit -q -m " & quoteShell(msg))

suite "reanchor_pin — drift 분류 (공유 술어 위)":
  test "no drift → OK":
    let pin = pinDocText(@[(path: PathA, mode: "100644", sha: "a1")])
    let o = evaluateTexts(LineA, pin, "HEAD", false)
    check o.exitCode == ExitOk
    check o.text.startsWith("OK no-drift")
    check o.drift.len == 0

  test "sha 변경 1건 → DRIFT(exit 1), 경로/양쪽 sha 보고":
    let pin = pinDocText(@[(path: PathA, mode: "100644", sha: "a1")])
    let o = evaluateTexts(LineA9, pin, "HEAD", false)
    check o.exitCode == ExitDrift
    check o.drift.len == 1
    check o.drift[0].kind == dkValueChanged
    check o.text.contains("changed " & PathA & " a1 -> a9")

  test "pin에 없는 멤버 → 멤버십 변경(exit 3), 파일 무변경":
    let pin = pinDocText(@[(path: PathA, mode: "100644", sha: "a1")])
    let o = evaluateTexts(LineA & "\n" & LineB, pin, "HEAD", false)
    check o.exitCode == ExitMembershipChange
    check o.text.contains("missing-from-pin " & PathB)
    check o.newPinText.isNone

  test "derived에 없는 pin 멤버 → 멤버십 변경(exit 3)":
    let pin = pinDocText(@[(path: PathA, mode: "100644", sha: "a1"),
                           (path: PathB, mode: "100644", sha: "b2")])
    let o = evaluateTexts(LineA, pin, "HEAD", false)
    check o.exitCode == ExitMembershipChange
    check o.text.contains("pin-only " & PathB)

  test "genesis(pin 키 부재) → 멤버십 변경으로 fail-closed (자동 통과 금지)":
    let pin = pinDocText(@[], keyPresent = false)
    let o = evaluateTexts(LineA, pin, "HEAD", false)
    check o.exitCode == ExitMembershipChange
    check o.text.contains("missing-from-pin " & PathA)

  test "malformed derived / malformed pin은 판정 이전에 exit 2":
    let pin = pinDocText(@[(path: PathA, mode: "100644", sha: "a1")])
    check evaluateTexts("garbage-without-tab", pin, "HEAD", false).exitCode ==
      ExitInputViolation
    check evaluateTexts(LineA, "{ not json", "HEAD", false).exitCode ==
      ExitInputViolation
    check evaluateTexts(LineA, pinDocText(@[(path: PathA, mode: "", sha: "a1")]),
                        "HEAD", false).exitCode == ExitInputViolation

  test "출력 순서는 경로 정렬 (Hash 열거 순서 무관)":
    let pin = pinDocText(@[(path: PathA, mode: "100644", sha: "a1"),
                           (path: PathB, mode: "100644", sha: "b2")])
    let o = evaluateTexts(LineB8 & "\n" & LineA9, pin, "HEAD", false)
    check o.exitCode == ExitDrift
    check o.drift.len == 2
    check o.drift[0].path == PathA
    check o.drift[1].path == PathB

suite "reanchor_pin — 표적 재작성 (JSONC 보존 + 자기검증)":
  test "--write: sha만 갱신하고 주석·포맷은 바이트 보존":
    let pin = pinDocText(@[(path: PathA, mode: "100644", sha: "a1")], jsonc = true)
    let o = evaluateTexts(LineA9, pin, "HEAD", true)
    check o.exitCode == ExitOk
    check o.newPinText.isSome
    let rewritten = o.newPinText.get
    check rewritten.contains("\"sha\": \"a9\"")
    check not rewritten.contains("\"sha\": \"a1\"")
    check rewritten.contains("// 이 주석은 재작성 후에도 보존되어야 한다")
    check rewritten.startsWith("{\n  \"schemaVersion\"")
    check rewritten.endsWith("}\n")
    # 자기검증: 재작성 결과는 no-drift여야 한다
    check evaluateTexts(LineA9, rewritten, "HEAD", false).exitCode == ExitOk

  test "재작성은 멱등 — 두 번째 --write는 drift 0으로 아무것도 쓰지 않는다":
    let pin = pinDocText(@[(path: PathA, mode: "100644", sha: "a1")])
    let once = evaluateTexts(LineA9, pin, "HEAD", true)
    check once.exitCode == ExitOk
    let twice = evaluateTexts(LineA9, once.newPinText.get, "HEAD", true)
    check twice.exitCode == ExitOk
    check twice.newPinText.isNone
    check twice.text.startsWith("OK no-drift")

  test "2건 동시 재작성도 결정론":
    let pin = pinDocText(@[(path: PathA, mode: "100644", sha: "a1"),
                           (path: PathB, mode: "100644", sha: "b2")])
    let a = evaluateTexts(LineA9 & "\n" & LineB8, pin, "HEAD", true)
    let b = evaluateTexts(LineA9 & "\n" & LineB8, pin, "HEAD", true)
    check a.exitCode == ExitOk and b.exitCode == ExitOk
    check a.newPinText.get == b.newPinText.get

  test "mode 변경도 값 갱신으로 처리된다 (멤버십 불변)":
    let pin = pinDocText(@[(path: PathA, mode: "100644", sha: "a1")])
    let o = evaluateTexts("100755 blob a1\t" & PathA, pin, "HEAD", true)
    check o.exitCode == ExitOk
    check o.newPinText.get.contains("\"mode\": \"100755\"")

  test "rewriteEntry: 대상 키가 없으면 추측하지 않고 err":
    let pin = pinDocText(@[(path: PathB, mode: "100644", sha: "b2")])
    let entry = DriftEntry(kind: dkValueChanged, path: PathA,
                           oldLine: LineA, newLine: LineA9)
    check rewriteEntry(pin, entry).isErr

suite "reanchor_pin — CLI 계약":
  test "--ref 누락/미지 옵션/잉여 인자는 exit 2":
    check parseReanchorArgs(@[]).isErr
    check parseReanchorArgs(@["--ref"]).isErr
    check parseReanchorArgs(@["--frobnicate", "x"]).isErr
    check parseReanchorArgs(@["--ref", "H", "extra"]).isErr
    check runReanchor(@[]) == ExitInputViolation

  test "--write는 값 없는 플래그다 (다음 인자를 삼키지 않는다)":
    let a = parseReanchorArgs(@["--write", "--ref", "HEAD"])
    check a.isOk
    check a.get.write
    check a.get.refName == "HEAD"
    let b = parseReanchorArgs(@["--ref", "HEAD", "--write"])
    check b.isOk and b.get.write

  test "저장소가 아닌 경로는 exit 2":
    let notRepo = FixtureDir / "notrepo"
    createDir(notRepo)
    check runReanchor(@["--ref", "HEAD", "--repo", notRepo]) == ExitInputViolation

suite "reanchor_pin — pin@ref는 트리에서 읽는다":
  test "워킹 트리를 더럽혀도 판정은 커밋된 pin을 쓴다":
    let repo = initRepo("treerepo")
    writeFile(repo / "config" / "trusted_writer_set.json",
      pinDocText(@[(path: PathA, mode: "100644", sha: "a1")]))
    check commitAll(repo, "pin a1") == 0
    let derived = writeFixture("derived_a1.txt", LineA)
    # 커밋된 pin은 a1을 앵커한다 → OK
    check runReanchor(@["--ref", "HEAD", "--repo", repo, "--derived", derived]) == ExitOk
    # 워킹 트리만 a9로 오염 — 커밋되지 않았으므로 판정은 여전히 OK여야 한다
    writeFile(repo / "config" / "trusted_writer_set.json",
      pinDocText(@[(path: PathA, mode: "100644", sha: "a9")]))
    check runReanchor(@["--ref", "HEAD", "--repo", repo, "--derived", derived]) == ExitOk

  test "커밋된 pin이 어긋나면 exit 1, --write로 재앵커되고 멱등":
    let repo = initRepo("writerepo")
    writeFile(repo / "config" / "trusted_writer_set.json",
      pinDocText(@[(path: PathA, mode: "100644", sha: "a1")]))
    check commitAll(repo, "pin a1") == 0
    let derived = writeFixture("derived_a9.txt", LineA9)
    check runReanchor(@["--ref", "HEAD", "--repo", repo, "--derived", derived]) == ExitDrift
    check runReanchor(@["--ref", "HEAD", "--repo", repo, "--derived", derived,
                         "--write"]) == ExitOk
    check readFile(repo / "config" / "trusted_writer_set.json").contains("\"sha\": \"a9\"")
    doAssert commitAll(repo, "pin a9") == 0
    check runReanchor(@["--ref", "HEAD", "--repo", repo, "--derived", derived]) == ExitOk

  test "멤버십 변경은 --write여도 파일을 쓰지 않는다":
    let repo = initRepo("membershiprepo")
    writeFile(repo / "config" / "trusted_writer_set.json",
      pinDocText(@[(path: PathA, mode: "100644", sha: "a1")]))
    check commitAll(repo, "pin a1") == 0
    let before = readFile(repo / "config" / "trusted_writer_set.json")
    let derived = writeFixture("derived_ab.txt", LineA & "\n" & LineB)
    check runReanchor(@["--ref", "HEAD", "--repo", repo, "--derived", derived,
                         "--write"]) == ExitMembershipChange
    check readFile(repo / "config" / "trusted_writer_set.json") == before