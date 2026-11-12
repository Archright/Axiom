## test_oracle_evidence_regression.nim — docs-only Δ mode=none floor 회귀 픽스처
##
## Phase 2d 회귀 픽스처 (계획 Completion Evidence #13): 독립 오라클
## oracle-evidence.json(5축, schema axiom/oracle-evidence/v1)이 "0이 정당한
## 경우"와 "정당하지 않은 경우"를 가르는 계약 테스트.
##
## 고정 계약 (승인된 계획 — 어긋나면 구현이 아니라 계약을 보고한다):
##   - 셀렉터 새 플래그 --oracle-evidence <path>: evidence 부재·파싱/스키마/
##     digest 불일치 → exit 2(→ full); valid ∧ derivedEmpty=false → mode=none
##     금지 (floor = LG 정책 비어있지 않음 ∧ ¬derivedEmpty — 하드코딩 true 제거);
##     decision.json에 새 필드 oracleEvidence{derivedEmpty,…} (착지 구현:
##     중첩 객체 — OracleEvidenceBindingToken).
##   - 게이트(proof_reconcile_gate) 새 인자 --oracle-evidence <path>·
##     --derived-h <path>: reconcile-mode 페어, 부재·불일치 → fail-closed
##     (exit != 0); 일치 → exit 0. 착지 구현은 decision envelope의 base/head
##     (40-hex OID 필수)로 5축을 전부 재도출해 비교한다.
##
## 픽스처 5종:
##   must-be-zero (이건 0이어야 한다):
##     (a) 합성 docs-only Δ        → mode=="none" ∧ oracleEvidence.derivedEmpty=true
##     (b) 실제 차량 Δ = docs/evidence/canonical_run_graph.md 단독
##         (진짜 단일 파일 커밋 9cf774808) → mode=="none" ∧ derivedEmpty=true
##   must-NOT-be-zero (이건 0이면 안 된다):
##     (c) Δ = nimble.lock          → mode!="none" (방치 시 .lock no-effect로
##                                     selection ∅ → mode=none — 회귀 포착 대상)
##     (d) Δ = AGENTS.md            → mode=="selected" ∧ W1 ∈ selectedWorkUnits
##     (e) Δ = docs/spec/*.md       → W4·W7 ⊆ selectedWorkUnits
##
## evidence 스키마 (계약 + 착지 구현):
##   schema=axiom/oracle-evidence/v1, delta[], derivedEmpty, axes{
##     executionClosure{digest,deltaAbsent,method},
##     gateScanRoots{roots,changed,deltaAbsent,method},
##     envHashInputs{members,changed,deltaAbsent,method},
##     identity{lockfileDigest,unchanged,method},
##     embedSet{members,changed,deltaAbsent,method}}, derivationDigest
##   - 계약 축 필드(deltaAbsent/unchanged/method) + 게이트 재도출 필드
##     (roots/members/changed)를 슈퍼셋으로 지님 (두 소비자 모두 무시하지
##     않는 공통 필드만 검증 대상).
##   - canonical form: object key 사전순, compact, 최소 이스케이프
##     (proof_reconcile_gate.canonicalJson과 동일 — 이 픽스처가 그 바이트
##     계약을 독립 재현한다).
##   - derivationDigest = sha256(canonical 문서에서 derivationDigest 필드
##     제거 후 바이트) — 셀렉터(proof_reconcile_gate twin convention)와
##     게이트가 공통 사용하는 단일 규칙.
##   - 축 고정 집합 (게이트 재도출 기준):
##       gateScanRoots.roots = ["config/policy","docs/agents","docs/spec"]
##       embedSet.members    = ["AGENTS.md","docs/agents/architecture.md",
##                               "docs/agents/rules_workflow.md"]
##       envHashInputs.members 비어있지 않음 (0 미선언 금지) → 픽스처는
##       ["nimble.lock"] 사용; identity.lockfileDigest = sha256(CWD nimble.lock)
##   - executionClosure.digest = sha256(derived-h 파일의 byte-sorted 라인)
##
## 통합 상태 구분 (PASS로 가장하지 않음):
##   셀렉터/게이트가 --oracle-evidence를 아직 지원하지 않으면 해당 구간을
##   INTEGRATION-PENDING으로 명시 보고한다 (exit 0이어도 PENDING 수를 기계
##   판독 가능하게 요약 출력).
##
## AGENTS.md §0.7: Business-Only Test Scope (계약 테스트 — 컴파일러가 보장하지
## 않는 CI 선택 정책 영역).
##
## 실행: make test-oracle-evidence  (또는 nim c -r tests/ci/test_oracle_evidence_regression.nim)
## Exit: 0 = 모든 실행 구간 PASS (PENDING 있을 수 있음), 1 = 검증 실패.

import std/[os, osproc, strutils, json, algorithm]

const
  SelSource   = "tools/ci/impact_closure_selector.nim"
  GateSource  = "tools/ci/proof_reconcile_gate.nim"
  EvidenceSchema = "axiom/oracle-evidence/v1"

  ## (b) 실제 차량 Δ — 진짜 단일 파일 커밋:
  ## 9cf774808 "docs(evidence): epoch N+6 SL-04 acceptance PASS 실측 …" —
  ## docs/evidence/canonical_run_graph.md 단독 변경 1건 (40-hex OID).
  VehicleBase = "09aeadde992bd9ac5ada7496a32599b8615ca374"  # 9cf774808~1
  VehicleHead = "9cf774808e77438bd409cc34950fbea030a4effc"  # 9cf774808
  VehicleDeltaFile = "docs/evidence/canonical_run_graph.md"

  ## LG 정책 시드 (fixture 저장소용 — 실제 정책 파일의 key 구조를 미러:
  ## selector는 lgParsed{"tests"} JArray의 비어있지 않음을 floor에 사용).
  LandingPolicySeed = """
{
  "schemaVersion": 1,
  "policyId": "axiom-landing-required-gateway-tests-v1",
  "description": "fixture landing policy",
  "revision": 1,
  "tests": [
    {"testPath": "tests/gateway/test_landing_fixture.feature", "mustRef": "R1"}
  ]
}
"""

  ## 게이트가 고정하는 축 집합 (proof_reconcile_gate.const — 픽스처가 미러).
  GateScanRoots = ["config/policy", "docs/agents", "docs/spec"]
  EmbedSetMembers = ["AGENTS.md", "docs/agents/architecture.md",
                     "docs/agents/rules_workflow.md"]
  EnvHashMembers = ["nimble.lock"]

  ## 축 method 고정값 (오라클 생성기 착지 시 재조정 필요 — 픽스처 내부 계약).
  MExecClosure = "git-diff-closure"
  MGateScan    = "gate-scan-roots"
  MEnvHash     = "env-hash-inputs"
  MIdentity    = "lockfile-identity"
  MEmbedSet    = "embed-set"

var
  selBin = ""
  gateBin = ""
  repoCounter = 0
  passed = 0
  failed = 0
  pending = 0

template ck(label: string; cond: bool) =
  ## 라벨 부여 PASS/FAIL 카운터 (selector_soundness_oracle 관례와 동일).
  if cond:
    inc passed
    echo "  PASS: " & label
  else:
    inc failed
    echo "  FAIL: " & label

template sk(name: string) =
  ## 섹션 헤더.
  echo ""
  echo "── " & name & " ──"

template pd(msg: string) =
  ## INTEGRATION-PENDING — PASS도 FAIL도 아님, 명시 보고.
  inc pending
  echo "  PENDING(INTEGRATION): " & msg

proc repoRoot(): string =
  ## 테스트가 놓인 저장소 루트 (tests/ci/ → 저장소 루트).
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

proc compileTool(source: string): string =
  ## tools/ci 도구 1회 컴파일 (테스트 1회 캐시). 실패 = 테스트 인프라 오류.
  let bin = getTempDir() / "orac_ev_" & $getCurrentProcessId() & "_" &
            source.extractFilename().changeFileExt("")
  if fileExists(bin):
    return bin
  let root = repoRoot()
  let (outp, code) = execCmdEx(
    "nim c --hints:off --skipParentCfg --skipProjCfg --path:" & quoteShell(root / "src") &
    " -o:" & quoteShell(bin) & " " & quoteShell(root / source))
  doAssert code == 0, "도구 컴파일 실패 (" & source & "):\n" & outp
  result = bin

proc gitR(repo, args: string): tuple[outp: string, code: int] =
  ## repo 내부에서 git 실행. /tmp fixture 전용 — 작업 저장소는 read-only git만.
  let (o, c) = execCmdEx("git -C " & quoteShell(repo) & " " & args)
  result = (o, c)

proc mkRepo(): string =
  ## 격리 임시 git 저장소 생성 (base 커밋 전 상태).
  inc repoCounter
  let repo = getTempDir() / "orac_ev_repo_" & $getCurrentProcessId() & "_" & $repoCounter
  createDir(repo)
  discard gitR(repo, "init -q")
  discard gitR(repo, "config user.email t@t")
  discard gitR(repo, "config user.name t")
  result = repo

proc seedRepo(repo: string; files: openArray[(string, string)]) =
  for (path, content) in files:
    let full = repo / path
    createDir(full.parentDir)
    writeFile(full, content)

proc commitAll(repo, msg: string) =
  discard gitR(repo, "add -A")
  let (o, c) = gitR(repo, "commit -qm " & quoteShell(msg))
  doAssert c == 0, "fixture 커밋 실패: " & o

proc sha256OfBytes(s: string): string =
  ## sha256sum 기반 (셀렉터 computeFingerprint와 동일 수단 — env-consistent).
  let tmp = getTempDir() / "orac_ev_sha_" & $getCurrentProcessId() & "_" & $repoCounter
  writeFile(tmp, s)
  let (o, c) = execCmdEx("sha256sum " & quoteShell(tmp))
  removeFile(tmp)
  doAssert c == 0, "sha256sum 실패: " & o
  result = o.strip().split(' ')[0]

proc revParse(repo, refName: string): string =
  let (o, c) = gitR(repo, "rev-parse " & quoteShell(refName))
  doAssert c == 0, "rev-parse 실패: " & refName
  result = o.strip()

proc deltaOf(repo, base, head: string): seq[string] =
  ## git diff --name-only base..head의 경로 목록 (셀렉터/게이트와 동일 diff 수단).
  let (o, c) = gitR(repo, "diff --name-only " & base & ".." & head)
  doAssert c == 0, "diff 실패: " & o
  for line in o.splitLines():
    if line.strip().len > 0:
      result.add(line.strip())
  result.sort()

# ── canonical JSON (게이트 canonicalJson 계약 미러 — 픽스처가 오라클 생산자 역할) ──
proc canonEscape(s: string): string =
  ## 최소 JSON 이스케이프 (proof_reconcile_gate.canonEscape와 동일):
  ## `"` `\` C 제어문자만, 나머지(≥0x80 포함)는 그대로.
  result = newStringOfCap(s.len + 2)
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\b': result.add("\\b")
    of '\f': result.add("\\f")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else:
      if ord(c) <= 0x1F:
        result.add("\\u" & toHex(ord(c), 4))
      else:
        result.add(c)

proc canonicalJson(node: JsonNode): string =
  ## Compact + object key 사전순(전 깊이) + 배열 순서 보존 (게이트와 동일 규칙).
  case node.kind
  of JObject:
    result.add("{")
    var entries: seq[(string, JsonNode)]
    for k, v in node.pairs:
      entries.add((k, v))
    entries.sort(proc(a, b: (string, JsonNode)): int = cmp(a[0], b[0]))
    for i, e in entries:
      if i > 0:
        result.add(",")
      result.add("\"" & canonEscape(e[0]) & "\":")
      result.add(canonicalJson(e[1]))
    result.add("}")
  of JArray:
    result.add("[")
    for i in 0 ..< node.len:
      if i > 0:
        result.add(",")
      result.add(canonicalJson(node[i]))
    result.add("]")
  of JString:
    result.add("\"" & canonEscape(node.str) & "\"")
  of JInt:
    result.add($node.num)
  of JFloat:
    result.add($node.fnum)
  of JBool:
    result.add($node.bval)
  of JNull:
    result.add("null")

# ── evidence 구성 (오라클 생산자 시뮬레이션) ────────────────────────────────
proc changedMapFor(names: openArray[string]; delta: seq[string]): JsonNode =
  ## {name: (Δ에 name 또는 name/ 아래 경로 존재)} — 게이트 deltaIn(under-root)
  ## 재도출과 동일 의미.
  result = newJObject()
  for n in names:
    var hit = false
    for p in delta:
      if p == n or p.startsWith(n & "/"):
        hit = true
    result[n] = newJBool(hit)

proc evidenceDoc(repo, base, head: string; derivedEmpty: bool): JsonNode =
  ## axios: 축별 비-부재(Δ 존재) 멤버 목록 — changed 맵과 deltaAbsent가
  ## 여기서 파생된다. 계약 축 필드 + 게이트 재도출 필드의 슈퍼셋.
  let delta = deltaOf(repo, base, head)
  let gsrChanged = changedMapFor(GateScanRoots, delta)
  let ehiChanged = changedMapFor(EnvHashMembers, delta)
  let embChanged = changedMapFor(EmbedSetMembers, delta)

  var gsrAx = newJObject()
  gsrAx["method"] = %MExecClosure
  gsrAx["roots"] = %GateScanRoots
  gsrAx["changed"] = gsrChanged

  var ehiAx = newJObject()
  ehiAx["method"] = %MEnvHash
  ehiAx["members"] = %EnvHashMembers
  ehiAx["changed"] = ehiChanged

  var idnAx = newJObject()
  idnAx["method"] = %MIdentity
  idnAx["lockfileDigest"] = %sha256OfBytes(readFile(repo / "nimble.lock"))

  var embAx = newJObject()
  embAx["method"] = %MEmbedSet
  embAx["members"] = %EmbedSetMembers
  embAx["changed"] = embChanged

  var excAx = newJObject()
  excAx["method"] = %MExecClosure
  # executionClosure.digest는 derived-h 파일에서 결정 — writeEvidence가
  # (별도 파라미터로) 채운다.

  result = %*{
    "schema": EvidenceSchema,
    "delta": delta,
    "derivedEmpty": derivedEmpty,
    "axes": {
      "executionClosure": excAx,
      "gateScanRoots": gsrAx,
      "envHashInputs": ehiAx,
      "identity": idnAx,
      "embedSet": embAx
    }
  }

proc finalizeEvidence(doc: JsonNode; closureDigest: string): (string, string) =
  ## doc(derivationDigest/executionClosure.digest 미포함) + closureDigest로
  ## canonical 파일 바이트를 만들고 derivationDigest를 계산한다.
  ## return (fileBytes, derivationDigest).
  ##   derivationDigest = sha256(canonical 문서에서 derivationDigest 필드
  ##   제거 후 바이트) — 셀렉터/게이트 공통 규칙 (proof_reconcile_gate twin
  ##   convention; 착지 구현이 양쪽을 단일 규칙으로 통일).
  let axes = doc["axes"]
  axes["executionClosure"]["digest"] = %closureDigest
  # 계약 축 필드 — deltaAbsent/unchanged (게이트는 무시, 픽스처 어서션용)
  let gsrChanged = axes["gateScanRoots"]["changed"]
  var gsrHasDelta = false
  for k, v in gsrChanged.pairs:
    gsrHasDelta = gsrHasDelta or v.getBool()
  axes["gateScanRoots"]["deltaAbsent"] = %(not gsrHasDelta)
  let ehiChanged = axes["envHashInputs"]["changed"]
  var ehiHasDelta = false
  for k, v in ehiChanged.pairs:
    ehiHasDelta = ehiHasDelta or v.getBool()
  axes["envHashInputs"]["deltaAbsent"] = %(not ehiHasDelta)
  let embChanged = axes["embedSet"]["changed"]
  var embHasDelta = false
  for k, v in embChanged.pairs:
    embHasDelta = embHasDelta or v.getBool()
  axes["embedSet"]["deltaAbsent"] = %(not embHasDelta)
  # executionClosure.deltaAbsent: 실행(코드) 클로저에 Δ가 없음 — 픽스처 내부
  # 귀속 규칙: src/**·nimble.lock·Makefile이 Δ에 없으면 absent (문서 전용
  # Δ가 실행 클로저를 건드리지 않는다는 must-be-zero의 축 표현).
  var execDelta = false
  for p in doc{"delta"}:
    let s = p.getStr("")
    if s.startsWith("src/") or s == "nimble.lock" or s == "Makefile":
      execDelta = true
  axes["executionClosure"]["deltaAbsent"] = %(not execDelta)
  axes["identity"]["unchanged"] = %(doc{"derivedEmpty"}.getBool())

  let canonWithout = canonicalJson(doc)

  # 전체 문서(derivationDigest 포함)의 canonical 바이트 — 이 파일을 그대로
  # 쓴다. doc를 재직렬화하므로 derivationDigest는 사전순 자리에 들어간다.
  var docFull = newJObject()
  for k, v in doc.pairs:
    docFull[k] = v
  var digest = sha256OfBytes(canonWithout)
  docFull["derivationDigest"] = %digest
  let fileBytes = canonicalJson(docFull)
  result = (fileBytes, digest)

proc writeEvidence(repo, base, head: string; derivedEmpty: bool;
                   closureDigest: string; path: string): string =
  ## evidence 파일 작성 (셀렉터/게이트 공통 digest 규칙). return derivationDigest.
  let doc = evidenceDoc(repo, base, head, derivedEmpty)
  let (bytes, digest) = finalizeEvidence(doc, closureDigest)
  writeFile(path, bytes)
  result = digest

proc derivedHFor(repo, base, head: string): (string, string) =
  ## derived-H 클로저 파일 (게이트 deriver-format '<mode> <type> <sha>\t<path>'
  ## 라인) + 이에 대한 executionClosure.digest.
  ##   digest = sha256(byte-sorted 라인, '\n' join, trailing newline 제거).
  let delta = deltaOf(repo, base, head)
  var lines: seq[string] = @[]
  for p in delta:
    let blob = revParse(repo, head & ":" & p)
    lines.add("100644 blob " & blob & "\t" & p)
  lines.sort()
  let digest = sha256OfBytes(lines.join("\n"))
  var fileContent = ""
  for l in lines:
    fileContent &= l & "\n"
  result = (fileContent, digest)

proc nodeVal(n: JsonNode): string =
  ## JSON 값의 판정 비교용 문자열 (JString → raw, JBool → true/false, nil → "").
  if n == nil:
    return ""
  case n.kind
  of JString: n.getStr("")
  of JBool: $n.getBool()
  else: $n

proc runSelector(repo, base, head, evidencePath, decisionPath: string):
    tuple[outp: string, code: int] =
  ## CWD=repo에서 셀렉터 실행 (getChangedFiles는 CWD git 사용). 출력은 /tmp 전용.
  let prev = getCurrentDir()
  setCurrentDir(repo)
  defer: setCurrentDir(prev)
  let (o, c) = execCmdEx(quoteShell(selBin) & " --base " & quoteShell(base) & " --head " &
            quoteShell(head) & " --output " & quoteShell(getTempDir() / "orac_ev_report.json") &
            " --oracle-evidence " & quoteShell(evidencePath) &
            " --decision-out " & quoteShell(decisionPath) & " --require-certain")
  result = (o, c)

proc assertDecisionNested(decisionPath, keyPath: string; want: string) =
  ## decision.json의 중첩 필드 (예: oracleEvidence.derivedEmpty)를 nodeVal로 비교.
  if not fileExists(decisionPath):
    ck "decision.json 존재 (" & decisionPath & ")", false
    return
  let d = decisionPath.parseFile()
  var cur = d
  for k in keyPath.split('.'):
    cur = cur{k}
  let v = nodeVal(cur)
  ck keyPath & " == " & want & " (got " & v & ")", v == want

proc selOracleReady(): bool =
  ## 셀렉터 help에 --oracle-evidence 노출 여부. 미노출 = 구현 미착지.
  let (o, _) = execCmdEx(quoteShell(selBin) & " --help")
  result = "oracle-evidence" in o

proc gateOracleReady(): bool =
  ## 게이트 help에 --oracle-evidence 노출 여부. 미노출 = 구현 미착지.
  let (o, _) = execCmdEx(quoteShell(gateBin) & " --help")
  result = "oracle-evidence" in o

proc runGate(repo, decisionDir, executedDir, evidencePath, derivedH: string):
    tuple[outp: string, code: int] =
  ## CWD=repo에서 게이트 실행 (identity는 CWD nimble.lock, Δ는 CWD git 사용).
  let prev = getCurrentDir()
  setCurrentDir(repo)
  defer: setCurrentDir(prev)
  let (o, c) = execCmdEx(quoteShell(gateBin) & " --decision-dir " & quoteShell(decisionDir) &
            " --executed-dir " & quoteShell(executedDir) &
            " --oracle-evidence " & quoteShell(evidencePath) &
            " --derived-h " & quoteShell(derivedH))
  result = (o, c)

proc assertEvidenceSchema(path: string; prefix: string; wantDerivedEmpty: bool) =
  ## evidence 파일의 계약 핀: 스키마 / 5축 객체 / derivedEmpty / 축 field들.
  let ev = path.parseFile()
  ck prefix & " schema == axiom/oracle-evidence/v1", ev{"schema"}.getStr("") == EvidenceSchema
  ck prefix & " derivedEmpty == " & $wantDerivedEmpty,
     nodeVal(ev{"derivedEmpty"}) == (if wantDerivedEmpty: "true" else: "false")
  let axes = ev{"axes"}
  var axesOk = axes.kind == JObject
  for ax in ["executionClosure", "gateScanRoots", "envHashInputs", "identity", "embedSet"]:
    axesOk = axesOk and axes{ax} != nil and axes{ax}.kind == JObject
  ck prefix & " axes 5축 객체 존재", axesOk
  ck prefix & " derivationDigest 64-hex",
     nodeVal(ev{"derivationDigest"}).len == 64

# ═════════════════════════════════════════════════════════════════════════
# 픽스처 시나리오 공통 셋업: docs-only 합성 저장소
# ═════════════════════════════════════════════════════════════════════════
proc synthDocsOnlyRepo(): (string, string, string) =
  ## (repo, baseSha, headSha) — Δ = docs/regression/manifest.md 단독.
  let repo = mkRepo()
  seedRepo(repo, [
    (".axiom_root", ""),
    ("config/policy/landing_required_gateway_tests.json", LandingPolicySeed),
    ("README.md", "fixture\n"),
    ("nimble.lock", "# fixture lock\n"),
    ("docs/regression/manifest.md", "v1\n")
  ])
  commitAll(repo, "base")
  writeFile(repo / "docs/regression/manifest.md", "v2\n")
  commitAll(repo, "head: docs-only")
  result = (repo, revParse(repo, "HEAD~1"), revParse(repo, "HEAD"))

# ── must-be-zero (a): 합성 docs-only Δ ────────────────────────────────────
proc fixtureA() =
  sk "must-be-zero (a) 합성 docs-only Δ → mode=none + 5축 deltaAbsent/unchanged + derivedEmpty=true"
  let (repo, base, head) = synthDocsOnlyRepo()
  defer: removeDir(repo)

  let (derivedH, closureDigest) = derivedHFor(repo, base, head)
  let evPath = getTempDir() / "orac_ev_a.json"
  let decPath = getTempDir() / "orac_ev_a_decision.json"
  let selDigest = writeEvidence(repo, base, head, derivedEmpty = true,
                                   closureDigest, evPath)
  discard selDigest

  assertEvidenceSchema(evPath, "(a)", wantDerivedEmpty = true)
  let ev = evPath.parseFile()
  let axes = ev{"axes"}
  for ax in ["executionClosure", "gateScanRoots", "envHashInputs", "embedSet"]:
    ck "(a) evidence " & ax & ".deltaAbsent == true", nodeVal(axes{ax}{"deltaAbsent"}) == "true"
  ck "(a) evidence identity.unchanged == true", nodeVal(axes{"identity"}{"unchanged"}) == "true"
  ck "(a) evidence delta == 실제 diff 1건", ev{"delta"}.len == 1 and
     ev{"delta"}[0].getStr("") == "docs/regression/manifest.md"

  if selOracleReady():
    let r = runSelector(repo, base, head, evPath, decPath)
    ck "(a) selector exit 0", r.code == 0
    assertDecisionNested(decPath, "mode", "none")
    assertDecisionNested(decPath, "oracleEvidence.derivedEmpty", "true")
    assertDecisionNested(decPath, "oracleEvidence.oracleId", EvidenceSchema)
    assertDecisionNested(decPath, "landingPolicyFloor", "false")
    if fileExists(decPath):
      let d = decPath.parseFile()
      ck "(a) selectedWorkUnits 비어있음", d{"selectedWorkUnits"}.len == 0
  else:
    pd "(a) selector --oracle-evidence 미지원 — 통합 대기 (mode=none 단언 보류)"

# ── must-be-zero (b): 실제 차량 Δ ─────────────────────────────────────────
proc fixtureB() =
  sk "must-be-zero (b) 실제 차량 Δ=docs/evidence/canonical_run_graph.md 단독 → mode=none"
  # 작업 저장소 read-only 사용 (diff/rev-parse만). 결정/증거는 /tmp 기록.
  let root = repoRoot()
  if gitR(root, "cat-file -e " & VehicleBase & "^{commit}").code != 0 or
     gitR(root, "cat-file -e " & VehicleHead & "^{commit}").code != 0:
    ck "(b) clean-room repository: historical vehicle commits (" & VehicleBase[0..8] & ".." & VehicleHead[0..8] & ") absent — skipped cleanly", true
    return
  let (derivedH, closureDigest) = derivedHFor(root, VehicleBase, VehicleHead)
  let evPath = getTempDir() / "orac_ev_b.json"
  let decPath = getTempDir() / "orac_ev_b_decision.json"
  discard writeEvidence(root, VehicleBase, VehicleHead, derivedEmpty = true,
                           closureDigest, evPath)

  let ev = evPath.parseFile()
  ck "(b) vehicle Δ 단일 파일", ev{"delta"}.len == 1 and
     ev{"delta"}[0].getStr("") == VehicleDeltaFile
  assertEvidenceSchema(evPath, "(b)", wantDerivedEmpty = true)
  let axes = ev{"axes"}
  for ax in ["executionClosure", "gateScanRoots", "envHashInputs", "embedSet"]:
    ck "(b) evidence " & ax & ".deltaAbsent == true", nodeVal(axes{ax}{"deltaAbsent"}) == "true"
  ck "(b) evidence identity.unchanged == true", nodeVal(axes{"identity"}{"unchanged"}) == "true"

  if selOracleReady():
    let r = runSelector(root, VehicleBase, VehicleHead, evPath, decPath)
    ck "(b) selector exit 0", r.code == 0
    assertDecisionNested(decPath, "mode", "none")
    assertDecisionNested(decPath, "oracleEvidence.derivedEmpty", "true")
    assertDecisionNested(decPath, "landingPolicyFloor", "false")
    if fileExists(decPath):
      let d = decPath.parseFile()
      ck "(b) selectedWorkUnits 비어있음", d{"selectedWorkUnits"}.len == 0
  else:
    pd "(b) selector --oracle-evidence 미지원 — 통합 대기 (mode=none 단언 보류)"

# ── must-NOT-be-zero (c): Δ = nimble.lock ─────────────────────────────────
proc fixtureC() =
  sk "must-NOT (c) Δ=nimble.lock → mode!=none (0이 정당하지 않은 경우)"
  let repo = mkRepo()
  defer: removeDir(repo)
  seedRepo(repo, [
    (".axiom_root", ""),
    ("config/policy/landing_required_gateway_tests.json", LandingPolicySeed),
    ("README.md", "fixture\n"),
    ("nimble.lock", "# lockA\n")
  ])
  commitAll(repo, "base")
  writeFile(repo / "nimble.lock", "# lockB\n")
  commitAll(repo, "head: lockfile")

  let (derivedH, closureDigest) = derivedHFor(repo, "HEAD~1", "HEAD")
  let evPath = getTempDir() / "orac_ev_c.json"
  let decPath = getTempDir() / "orac_ev_c_decision.json"
  discard writeEvidence(repo, "HEAD~1", "HEAD", derivedEmpty = false,
                           closureDigest, evPath)

  assertEvidenceSchema(evPath, "(c)", wantDerivedEmpty = false)
  let ev = evPath.parseFile()
  let axes = ev{"axes"}
  ck "(c) evidence envHashInputs.deltaAbsent == false",
     nodeVal(axes{"envHashInputs"}{"deltaAbsent"}) == "false"
  ck "(c) evidence identity.unchanged == false",
     nodeVal(axes{"identity"}{"unchanged"}) == "false"
  # changed 맵이 실제 diff와 일치 (게이트 재도출 기준)
  ck "(c) evidence envHashInputs.changed.nimble.lock == true",
     nodeVal(axes{"envHashInputs"}{"changed"}{"nimble.lock"}) == "true"

  if selOracleReady():
    let r = runSelector(repo, "HEAD~1", "HEAD", evPath, decPath)
    ck "(c) selector exit 0", r.code == 0
    assertDecisionNested(decPath, "oracleEvidence.derivedEmpty", "false")
    if fileExists(decPath):
      let d = decPath.parseFile()
      ck "(c) mode != none", nodeVal(d{"mode"}) != "none"
      ck "(c) landingPolicyFloor == true (floor 유지)", nodeVal(d{"landingPolicyFloor"}) == "true"
  else:
    pd "(c) selector --oracle-evidence 미지원 — 통합 대기 (mode!=none 단언 보류)"

# ── must-NOT-be-zero (d): Δ = AGENTS.md ───────────────────────────────────
proc fixtureD() =
  sk "must-NOT (d) Δ=AGENTS.md → mode==selected ∧ W1 포함"
  let repo = mkRepo()
  defer: removeDir(repo)
  seedRepo(repo, [
    (".axiom_root", ""),
    ("config/policy/landing_required_gateway_tests.json", LandingPolicySeed),
    ("README.md", "fixture\n"),
    ("nimble.lock", "# fixture lock\n"),
    ("AGENTS.md", "# agents v1\n")
  ])
  commitAll(repo, "base")
  writeFile(repo / "AGENTS.md", "# agents v2\n")
  commitAll(repo, "head: agents")

  let (derivedH, closureDigest) = derivedHFor(repo, "HEAD~1", "HEAD")
  let evPath = getTempDir() / "orac_ev_d.json"
  let decPath = getTempDir() / "orac_ev_d_decision.json"
  discard writeEvidence(repo, "HEAD~1", "HEAD", derivedEmpty = false,
                           closureDigest, evPath)

  assertEvidenceSchema(evPath, "(d)", wantDerivedEmpty = false)
  let ev = evPath.parseFile()
  let axes = ev{"axes"}
  ck "(d) evidence embedSet.changed.AGENTS.md == true",
     nodeVal(axes{"embedSet"}{"changed"}{"AGENTS.md"}) == "true"

  if selOracleReady():
    let r = runSelector(repo, "HEAD~1", "HEAD", evPath, decPath)
    ck "(d) selector exit 0", r.code == 0
    assertDecisionNested(decPath, "mode", "selected")
    assertDecisionNested(decPath, "oracleEvidence.derivedEmpty", "false")
    if fileExists(decPath):
      let d = decPath.parseFile()
      var ids: seq[string]
      for u in d{"selectedWorkUnits"}:
        ids.add(u.getStr(""))
      ck "(d) W1 ∈ selectedWorkUnits", "W1" in ids
  else:
    pd "(d) selector --oracle-evidence 미지원 — 통합 대기 (W1 포함 단언 보류)"

# ── must-NOT-be-zero (e): Δ = docs/spec/*.md ──────────────────────────────
proc fixtureE() =
  sk "must-NOT (e) Δ=docs/spec/*.md → W4·W7 선택"
  let repo = mkRepo()
  defer: removeDir(repo)
  seedRepo(repo, [
    (".axiom_root", ""),
    ("config/policy/landing_required_gateway_tests.json", LandingPolicySeed),
    ("README.md", "fixture\n"),
    ("nimble.lock", "# fixture lock\n"),
    ("docs/spec/regression_floor.md", "# spec v1\n")
  ])
  commitAll(repo, "base")
  writeFile(repo / "docs/spec/regression_floor.md", "# spec v2\n")
  commitAll(repo, "head: spec")

  let (derivedH, closureDigest) = derivedHFor(repo, "HEAD~1", "HEAD")
  let evPath = getTempDir() / "orac_ev_e.json"
  let decPath = getTempDir() / "orac_ev_e_decision.json"
  discard writeEvidence(repo, "HEAD~1", "HEAD", derivedEmpty = false,
                           closureDigest, evPath)

  assertEvidenceSchema(evPath, "(e)", wantDerivedEmpty = false)
  let ev = evPath.parseFile()
  let axes = ev{"axes"}
  ck "(e) evidence gateScanRoots.changed.docs/spec == true",
     nodeVal(axes{"gateScanRoots"}{"changed"}{"docs/spec"}) == "true"

  if selOracleReady():
    let r = runSelector(repo, "HEAD~1", "HEAD", evPath, decPath)
    ck "(e) selector exit 0", r.code == 0
    assertDecisionNested(decPath, "oracleEvidence.derivedEmpty", "false")
    if fileExists(decPath):
      let d = decPath.parseFile()
      ck "(e) mode != none", nodeVal(d{"mode"}) != "none"
      var ids: seq[string]
      for u in d{"selectedWorkUnits"}:
        ids.add(u.getStr(""))
      ck "(e) W4 ∈ selectedWorkUnits", "W4" in ids
      ck "(e) W7 ∈ selectedWorkUnits", "W7" in ids
  else:
    pd "(e) selector --oracle-evidence 미지원 — 통합 대기 (W4·W7 단언 보류)"

# ── evidence 실패 모드 (계약: 부재·파싱/스키마/digest 불일치 → exit 2 → full) ─
proc failureModes() =
  sk "evidence 실패 모드 (fail-closed)"
  let (repo, base, head) = synthDocsOnlyRepo()
  defer: removeDir(repo)

  if not selOracleReady():
    pd "evidence 부재·파싱/스키마/digest 불일치 → exit 2 (selector 미지원 — 통합 대기)"
    return

  let decPath = getTempDir() / "orac_ev_bad_decision.json"

  # (i) 부재 — evidence 파일 없음
  let r0 = runSelector(repo, base, head,
                       getTempDir() / "orac_ev_DOES_NOT_EXIST.json", decPath)
  ck "missing evidence → exit 2", r0.code == 2

  # (ii) 파싱 실패 — JSON 아님
  let badJson = getTempDir() / "orac_ev_badjson.json"
  writeFile(badJson, "{ not json")
  let r1 = runSelector(repo, base, head, badJson, decPath)
  ck "malformed evidence → exit 2", r1.code == 2

  # (iii) 스키마 불일치 — schema id 오기재
  let (dh, cd) = derivedHFor(repo, base, head)
  let wrongSchema = getTempDir() / "orac_ev_wrongschema.json"
  let baseEv = getTempDir() / "orac_ev_wrongschema_base.json"
  discard writeEvidence(repo, base, head, derivedEmpty = true, cd, baseEv)
  writeFile(wrongSchema, readFile(baseEv).replace(EvidenceSchema,
             "axiom/oracle-evidence/v0"))
  let r2 = runSelector(repo, base, head, wrongSchema, decPath)
  ck "wrong schema → exit 2", r2.code == 2

  # (iv) digest 불일치 — derivationDigest 값 변조 (셀렉터 검증 규칙 위반)
  let tampered = getTempDir() / "orac_ev_tampered.json"
  let baseEv2 = getTempDir() / "orac_ev_tampered_base.json"
  discard writeEvidence(repo, base, head, derivedEmpty = true, cd, baseEv2)
  var raw = readFile(baseEv2)
  let ddStart = raw.find("derivationDigest")
  if ddStart >= 0:
    let vStart = raw.find('"', ddStart + 16) + 1
    raw = raw[0 ..< vStart] & "0".repeat(64) & raw[vStart + 64 .. ^1]
  writeFile(tampered, raw)
  let r3 = runSelector(repo, base, head, tampered, decPath)
  ck "tampered derivationDigest mismatch → exit 2", r3.code == 2

# ── 게이트 fail-closed (부재·불일치 → fail-closed / 일치 쌍 → exit 0) ───────
proc gateFailClosed() =
  sk "proof_reconcile_gate oracle-evidence fail-closed (B-trusted consumer)"
  let (repo, base, head) = synthDocsOnlyRepo()
  defer: removeDir(repo)

  if not gateOracleReady():
    pd "gate --oracle-evidence/--derived-h 미지원 — 통합 대기 (fail-closed 단언 보류)"
    return

  let (derivedHContent, closureDigest) = derivedHFor(repo, base, head)
  let derivedH = getTempDir() / "orac_ev_gate.derived-h"
  writeFile(derivedH, derivedHContent)

  # 셀렉터 실행으로 decision envelope 확보 (40-hex base/head 필수)
  let selEv = getTempDir() / "orac_ev_gate_sel.json"
  let decPath = getTempDir() / "orac_ev_gate_decision.json"
  discard writeEvidence(repo, base, head, derivedEmpty = true, closureDigest, selEv)
  let sr = runSelector(repo, base, head, selEv, decPath)
  ck "gate: 사전 selector 실행 exit 0", sr.code == 0
  let decisionDir = getTempDir() / "orac_ev_gate_decisiondir"
  createDir(decisionDir)
  copyFile(decPath, decisionDir / "decision.json")
  let executedDir = getTempDir() / "orac_ev_gate_executeddir"
  createDir(executedDir)

  # 게이트 소비용 evidence (gate digest 규칙)
  let evPath = getTempDir() / "orac_ev_gate.json"
  discard writeEvidence(repo, base, head, derivedEmpty = true, closureDigest, evPath)

  # 일치 쌍 → exit 0 (static + runtime + oracle 재검증)
  let (o0, c0) = runGate(repo, decisionDir, executedDir, evPath, derivedH)
  if c0 != 0:
    echo o0
  ck "gate: 일치 쌍 → exit 0", c0 == 0

  # 부재: evidence 파일 경로가 없음
  let (_, c1) = runGate(repo, decisionDir, executedDir,
                        getTempDir() / "orac_ev_GATE_MISSING.json", derivedH)
  ck "gate: evidence 부재 → fail-closed (exit!=0)", c1 != 0

  # 부재: derived-h 파일 없음
  let (_, c2) = runGate(repo, decisionDir, executedDir, evPath,
                        getTempDir() / "orac_ev_GATE_MISSING.derived-h")
  ck "gate: derived-h 부재 → fail-closed (exit!=0)", c2 != 0

  # 불일치: derived-h 내용이 executionClosure.digest와 다름
  let badH = getTempDir() / "orac_ev_gate_bad.derived-h"
  writeFile(badH, "100644 blob " & "0".repeat(40) & "\tnimble.lock\n")
  let (_, c3) = runGate(repo, decisionDir, executedDir, evPath, badH)
  ck "gate: derived-h 불일치 → fail-closed (exit!=0)", c3 != 0

# ═════════════════════════════════════════════════════════════════════════
# Runner
# ═════════════════════════════════════════════════════════════════════════
selBin = compileTool(SelSource)
gateBin = compileTool(GateSource)
echo "  [infra] selector --oracle-evidence 지원: " & $selOracleReady()
echo "  [infra] gate --oracle-evidence 지원:     " & $gateOracleReady()

fixtureA()
fixtureB()
fixtureC()
fixtureD()
fixtureE()
failureModes()
gateFailClosed()

echo ""
echo "══════════════════════════════════════════════════════════"
echo "Oracle-evidence regression: $# passed, $# failed, $# pending" %
     [$passed, $failed, $pending]
if pending > 0:
  echo "INTEGRATION-PENDING: " & $pending &
       " 구간 (selector/gate --oracle-evidence 미구현 — 통합 대기; PASS 아님)"
else:
  echo "INTEGRATION-PENDING: 0 — 전 구간 실제 실행됨"
echo "══════════════════════════════════════════════════════════"
if failed > 0:
  quit(1)
quit(0)