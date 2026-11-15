## test_go_critical_input_approvals.nim — GO-critical 판정 입력 승인 테이블 계약
##
## 대상: tools/ci/check_evidence_id_contract.nim의 순수 판정 함수들 —
## judgeGoCriticalInput(경로별 B/M blob 판정), parseApprovalTable(테이블
## 파싱·검증), parseLsTree(git ls-tree 레코드 파싱).
##
## WHY (§0.9 — 극장 금지): armed 경로(merge_group 래인의 B/M 트리 비교)는
## 매 merge_group 실행에서 실측된다. 이 테스트가 고정하는 것은 그 armed
## 경로가 합성하는 순수 의미론이다 — 4필수 케이스:
##   (i)   동일 blob 통과 (승인 불필요)
##   (ii)  미승인 변경 FAIL (GO_TEST_HASH_UNAPPROVED)
##   (iii) 승인된 변경 통과 (staged-landing 창)
##   (iv)  추가(미승인)·삭제(무조건) FAIL
## 에 더해: 실제 테이블(data/policy/go_critical_input_approvals.json)이
## 파싱 가능하고 매트릭스 4종을 커버하는지(드리프트 방지), 기형 테이블이
## 전부 fail-closed인지를 단언한다.
##
## 래인 배터리(tools/ci/check_evidence_id_contract.nim runSelfCheck)가
## 같은 의미론을 매 레인 실행에서 입증한다 — 여기는 저장소 표준 단위
## 테스트 지점이다.

import std/[unittest, os, strutils]

import core/results
import ../../tools/ci/check_evidence_id_contract

const
  RepoRoot = currentSourcePath.parentDir().parentDir().parentDir()

const
  MatrixPath = "tests/unit/test_d2_golden.nim"
  GoldenPath = "tests/golden/rem_body.nim"
  BlobB = "ba294f29118f21d84c2609f3170a538888ce27ac"
  BlobM = "1111111111111111111111111111111111111111"
  BlobOther = "2222222222222222222222222222222222222222"

test "(i) 동일 blob 통과 — B의 바이트는 승인 없이 통과":
  check judgeGoCriticalInput(MatrixPath, BlobB, BlobB, @[]) == ""
  check judgeGoCriticalInput(GoldenPath, BlobM, BlobM, @[]) == ""

test "(ii) 미승인 변경 FAIL — 빈 집합·잘못된 승인 모두 거부":
  block:
    let v = judgeGoCriticalInput(MatrixPath, BlobB, BlobM, @[])
    check v.len > 0
    check v.contains(GoTestHashUnapprovedMarker)
  block:
    let v = judgeGoCriticalInput(MatrixPath, BlobB, BlobM, @[BlobOther])
    check v.len > 0
    check v.contains(GoTestHashUnapprovedMarker)

test "(iii) 승인된 변경 통과 — staged-landing 창(구·신 blob 병존)":
  check judgeGoCriticalInput(MatrixPath, BlobB, BlobM, @[BlobB, BlobM]) == ""
  check judgeGoCriticalInput(GoldenPath, BlobB, BlobM, @[BlobM]) == ""

test "(iv) 추가·삭제 FAIL — 추가는 미승인 시, 삭제는 무조건":
  block:
    let v = judgeGoCriticalInput(MatrixPath, "", BlobM, @[])
    check v.len > 0
    check v.contains(GoTestHashUnapprovedMarker)
  block:
    let v = judgeGoCriticalInput(GoldenPath, BlobB, "", @[BlobB])
    check v.len > 0
    check v.contains(GoTestHashUnapprovedMarker)
  # 승인된 추가는 통과한다 — 추가 승인은 (iv)의 통과 측면:
  check judgeGoCriticalInput(MatrixPath, "", BlobM, @[BlobM]) == ""

test "실제 테이블: 파싱 성공 + 매트릭스 4종 커버 + 스키마 문자열":
  let tablePath = RepoRoot / GoCriticalApprovalTablePath
  check fileExists(tablePath)
  let text = readFile(tablePath)
  let r = parseApprovalTable(text)
  check r.isOk
  if r.isOk:
    for t in GoCriticalMatrixTests:
      let approved = approvalFor(r.get, t)
      check approved.len >= 1
      check blobAt(@[], t).len == 0  # blobAt: 부재 = ""
  check text.contains("\"" & GoCriticalApprovalSchema & "\"")

test "테이블 기형: 전부 fail-closed":
  check parseApprovalTable("{bad").isErr
  check parseApprovalTable("{}").isErr
  block:
    let outOfScope = """{"schema":"go-critical-input-approvals/v1","description":"x","entries":[{"path":"src/main.nim","approvedBlobs":["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]}]}"""
    check parseApprovalTable(outOfScope).isErr
  block:
    let badHex = """{"schema":"go-critical-input-approvals/v1","description":"x","entries":[{"path":"tests/golden/rem_body.nim","approvedBlobs":["zz"]}]}"""
    check parseApprovalTable(badHex).isErr
  block:
    let wrongSchema = """{"schema":"go-critical-input-approvals/v0","description":"x","entries":[]}"""
    check parseApprovalTable(wrongSchema).isErr

test "ls-tree 파싱: blob 보존·tree skip·기형 거부":
  block:
    let ok = parseLsTree("100644 blob " & BlobB & "\ttests/golden/rem_body.nim\n" &
      "040000 tree " & BlobM & "\ttests/golden/base36_subject\n")
    check ok.isOk
    if ok.isOk:
      check ok.get.len == 1
      check ok.get[0].path == "tests/golden/rem_body.nim"
      check ok.get[0].oid == BlobB
  check parseLsTree("no-tab-line\n").isErr

test "스코프 판정: 매트릭스·최상위 golden만, 하위 디렉터리는 제외":
  for t in GoCriticalMatrixTests:
    check inApprovalScope(t)
  check inApprovalScope("tests/golden/rem_body.nim")
  check not inApprovalScope("tests/golden/base36_subject/rem_body.nim")
  check not inApprovalScope("tests/golden/base36_subject")
  check not inApprovalScope("tests/golden/notes.txt")
  check not inApprovalScope("src/main.nim")
  check not inApprovalScope("tests/unit/other_test.nim")
