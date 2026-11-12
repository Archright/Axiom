# L3 후속 증거 — UNKNOWN①② 해소·§5 정정·WP-B2 종결 (2026-11-03)

- **문서 종류**: docs/evidence — 읽기 전용 **후속 증거 보고**. 코드·워크플로우·게이트·판정 의미론 변경 0. 본 보고서는 판정을 만들지 않는다(Reporter — merge admission authority = GitHub).
- **방식**: L3 감사(`admission_chain_l3_dependency_audit_2026-11-03.md`, PR #1242 착지)의 UNKNOWN 2항·§5 추정·로드맵 L2를 **백그라운드 병렬 서브에이전트 4건**으로 조사하고, 각 산출을 본 Reporter가 원본(census jsonl·잡 로그·공식 문서)에서 재검증해 재인용했다(dual-lane 감사:3 스타일 계승 — Authority ≠ Adapter, AGENTS.md §2.3).
- **코호트**: census 진단 코호트 15배치(#1214–#1228) **재사용(읽기 전용 재계산)** — 새 CI 실행을 만들지 않았다(인위적 표본 생산 금지). 본 수치는 진단 계층이며 공식 SLO 모집단(#1166 동결 계약)과 무관하다.
- **데이터**: `data/ci_provider/l3_followup_20261103T095002Z/` — `artifact_transport.json`(S-2)·`toolchain_extract_evidence.json`(S-3)·`manifest.json`(소스·도구·에이전트 매핑·재검증 기록).

## §0 판정 요약

| 항목 (L3 감사 상 위치) | 결과 | 근거 |
|---|---|---|
| §6.4 UNKNOWN① 동시실행 큐 리스크 | **부분 해소** — 메커니즘 확정·한도 실측 변수 잔존 | 공식 문서: 한도 도달 시 신규 잡은 **큐잉, 실패 아님**; 큐는 run 스코프 아님. 정량 변수(플랜 티어·가동률)는 API 미노출 → 구현 사전등록에서 측정 4항(§1) |
| §6.4 UNKNOWN② 신규 아티팩트 전송 오버헤드 | **해소** — 475레코드 실측, +2s 수당 **중앙값 등가로 타당** | §2: 소형 부류 1s/홉·업로드+다운로드 체인 med 2s — 수당과 정확히 일치; tail 최악 +4s |
| §5 toolchain 이중 모드 "캐시 on/off 상태 차(추정)" | **가설 기각·원인 정정** — extract(tar) 단계 러너 VM 변동 | §3: A-cache 히트 15/15 동일 키·아카이브(~1161MB); 이중 모드는 tar -xf 단계 — warm 22.4s vs cold 50.2s(26s 공극). 물리 하위 원인 UNKNOWN |
| 로드맵 L2 / census UNKNOWN③ — WP-B2/A-restore 축소 | **BLOCKED 종결** — 4축 재판정, 재심사 조건 3 | §4: 축소 스코프는 nim 미커버 → attest red; 12–15s < 노이즈 ~23s; 커버 게이트 부재 |

효과 게이트·판정 의미론은 변경하지 않는다 — 본 보고서는 L3 감사의 UNKNOWN을 근거로 닫고, 잘못된 추정(§5)을 관측으로 정정한다. 구현은 여전히 별도 사전등록의 소관이다.

## §1 S-1 — 동시실행 큐 리스크 (UNKNOWN① 부분 해소)

**질의**: 신규 병렬 잡 job2a의 3번째 toolchain restore가 GitHub Actions 동시실행 한도에 닿아 lane·다른 잡을 지연시킬 수 있는가.

**메커니즘 (공식 문서 확정 — Context7 `/websites/github_en_actions`)**:
- 한도 도달 시 신규 잡은 **큐에 진입할 뿐 실패하지 않는다**("any new jobs will start to enter a queue" — View current jobs).
- 큐는 **run에 스코프되지 않는다** — 형제 잡과 타 run의 잡이 동등하게 지연될 수 있다.
- 따라서 리스크의 성격은 **required check 적색화가 아니라 wall 지연**이다. L3 감사의 은폐 판정(15/15)이 잡 wall 대기 포함이라는 점은 이 메커니즘과 정합적이다.

**한도 경로 (현행 GHEC 에포크)**: 계정(플랜) 수준 동시 잡 한도 — Free 20 / Pro 40 / Team 60 / Enterprise 500. Ubicloud 폴백 = idle 러너 대기(24h 잔류 시 실패). 실행 시점의 실제 가동률·계정 큐 길이·순서는 **API에 노출되지 않는다**(미관측 변수로 유지).

**저장소 사실**: `admission-check.yml`은 concurrency 그룹 없음(B3 제거로 제거됨). 27 워크플로 중 18개가 concurrency 선언, `queue: max`는 `ci-provider-router:103` 유일. 러너: `runs-on: fromJSON(vars.CI_RUNNER_MAP).x64`(admission-check.yml:677) — CI_RUNNER_MAP은 org 변수, 현행 `mode=ghec, x64→ubuntu-24.04, generation=15`.

**구현 사전등록에서의 측정 4항 (L3-GO 사전등록 설계 입력)**: (1) 관측 최대 동시 잡 vs 플랜 한도, (2) created→started 갭 중 큐 대기 분해(census §4.4 방법론), (3) Ubicloud 러너 수, (4) attest 창 최대 동시 잡의 여유(headroom). **정밀화(2026-11-03, unknown_closure §1)**: (1)(2)(4)를 동결 코호트에서 진단 측정 완료 — 최대 동시 잡 15(< 최소 티어 20)·갭 med 3s [2,39] 큐 병목 징후 없음·headroom 5–10(Free 기준); (3)은 현행 GHEC 에포크에서 호스팅 러너만 관측(Ubicloud 0). 이 값은 진단 추정이며, 사전등록의 확증 관측(착지 후 신규 런)은 그대로 필수다.

## §2 S-2 — 신규 아티팩트 전송 오버헤드 (UNKNOWN② 해소)

**질의**: MOVED 잡 산출물(identity env·D9 evidence·SUBJECT_ID)의 artifact 업로드/다운로드 비용 — L3 모델은 +2s 수당(보수 고정값)만 있었다.

**실측 (census 15배치 재계산 — 스텝 wall = completed−started, 스킵 제외, ±1s)**: 전송 스텝 31종 + 의사 1종(P3), 실행 레코드 475건, 타임스탬프 결측 0.

| 부류 | n | med/홉 | 범위 | 대표 스텝 |
|---|---|---|---|---|
| 소형(KB급 JSON/텍스트) | 330 | **1s** | [0,6] | witness/evidence/judgment 업로드 1s [1-2]·lane 판정 다운로드 1s [0-2]·API witness 재다운 1s [0-1] |
| 대형 | 145 | **4s** | [1,12] | base-built 업로드 6s [5-7]/다운 2-3s·nimcache 6s [4-9]·bootstrap 업로드 10s [7-12] |

배치당 전송 총량: med **72s** [57–79]. 메커니즘: `actions/upload-artifact@v7`·`download-artifact@v8`(mint 4종만 REST API). bootstrap 업로드 스킵 5배치(#1214·#1218·#1221·#1224·#1226 — bootstrap 공급 재사용 HIT, **GO REUSED 4배치와는 다른 집합**).

**+2s 수당 판정: 중앙값 등가로 타당(과소 아님)**
- 업로드+다운로드 체인 med **2s**·mean ~2.4s — 수당과 정확히 일치.
- 구조적으로 MOVED 산출물은 소형 부류다(identity env는 job outputs로 0 artifact 비용). witness/evidence/judgment 홉은 매 배치 이미 실행 중이며, MOVED 잡은 신규 홉을 만들지 않고 기존 홉(생성 1 + 소비 1)을 재배치한다.
- tail: 최악 관측 쌍 4s(#1224 `Upload tested-tree-digest` 6s — 소형 업로드 산발 지연). 엄격 최대 피복 수당은 +4s.
- **경계 조건**: 판정은 MOVED 산출물이 소형 부류에 머무는 동안만 유효 — 대형 payload(nimcache 6s·base-built 6s·bootstrap 10s급)가 되면 +2s는 3–5배 과소.

전체 데이터·판정 근거 전문: `data/ci_provider/l3_followup_20261103T095002Z/artifact_transport.json`.

## §3 S-3 — toolchain 이중 모드 원인 (§5 추정 정정)

**질의**: L3 감사 §5의 "toolchain 이중 모드(추정: 캐시 on/off 상태 차)" — job2 toolchain warm 43–50s ×9 vs cold 69–76s ×6.

**판정: 캐시 on/off 가설 기각.** 잡 로그 15배치 전수(gh api GET, job_id는 데이터 파일 기록)에서:

- **A-cache 히트 15/15 — 모든 cold 배치도 Cache hit.** 키·아카이브가 15배치 전부 동일(`axiom-a-Linux-8497f84b…-e881beabc…-c3b6ac…`, ~1161MB/1217679791B). miss·축출·restore-key 폴백 0. A_VERIFY OK 15/15(nim=2.2.10 lean=4.33.0 z3=4.13.3), B-cache exact-hit 15/15.
- **이중 모드의 실제 위치는 actions/cache extract(tar -xf cache.tzst) 단계**: warm 22.1–22.9s(9배치, med 22.4) vs cold 49.1–52.8s(6배치, med 50.2) — 22.9와 49.1 사이 값 없음(26s 공극), extract 차(≈27s) ≈ toolchain 스텝 이중 모드 간격(26s). 나머지 구간(setup+다운로드+B-복원)은 단봉(warm 20.2–27.6s·cold 19.9–24.9s 겹침).
- **동일 아카이브·동일 키·동일 러너 이미지(ubuntu-24.04, provisioner 20261021.618)에서 잡별 2.2배 tar 차이** = 러너 VM 수준 변동 — 플랫폼 사유, Axiom 제어 밖.

**교란 배除**: 배치 중첩(4쌍 중 3쌍 C×W — #1223 cold와 #1224 warm이 53초 큐 진입 차로 사실상 동시 실행, 676s 최장 중첩 — 전역 상태/시간대 효과의 결정적 반례)·시간 교차(09:32 C → 09:38 W → 09:47 C)·GO 코호트(REUSED 4 = W·W·C·W 혼재)·레인 비대칭(양 레인이 양 모드 포함, 표본 비대칭)·다운로드 속도(최속 다운 #1221이 최저 extract — 역상관 반례) 전부 기각.

**공식 문서 맥락(Context7 캐시 문서)**: 축출(7일 무접근·10GB LRU)은 본 코호트 미발생; merge_group 실행은 기본 브랜치 스코프 캐시 공유(15/15 히트와 정합); restore 지연에 SLA 없음 — 잡 수준 extract 변동은 플랫폼 영역.

**잔여 UNKNOWN**: extract 이중 모드의 물리 하위 원인(러너 CPU 세대·저장 클래스·steal) — 로그·API에 러너 하드웨어 식별자가 없다. warm 군집의 극도로 타이트한 분포(σ≈0.3s)는 이산적 VM 수준 속성을 시사하나(징후, 증명 아님) 그 이상 귀속하지 않는다.

**함의**: 원인 귀속만 수행 — 최적화 제안이 아니다. restore/extract 동작 변경은 별도 사전등록 소관. 향후 job2a toolchain restore는 동일한 잡별 VM 추첨에서 값을 얻으므로, 그 복원 시간 추정은 이중 모드 분포(med 22.4/50.2)를 모델링해야 한다.

전체 배치 표(job2_tc·mode·dl·extract·lane0/1/bbase_tc·job_id 15배치): `toolchain_extract_evidence.json`.

## §4 S-4 — WP-B2/A-restore 스코프 축소 재판정 (로드맵 L2 폐쇄 — BLOCKED)

**질의**: A-restore 스코프 축소(~12–15s, 17–32s 외삽 밴드)가 안전한 최적화 후보인가.

**4축 재판정 — BLOCKED (종결)**:
1. **의미론**: attest는 `provision-scope: 'full'`을 요구(admission-check.yml:858-860·:877 — core_purity_gate의 nim 성분). 축소 스코프 `{~/.elan, ~/.local/bin}`는 **nim을 커버하지 않는다** → 단독 축소는 attest를 적색화한다. 2-part 변경 중 ①(base artifact 멤버 이동)은 검증되지 않았다.
2. **효과**: 12–15s < 노이즈 바 ~23s(`arestore:51`). 17–32s 밴드는 미측정 외삽.
3. **게이트**: 이 후보를 커버하는 동결 게이트가 없다 — B4 사전등록 §3.2:299는 "탈락(조건부 재후보)"로 기록, B2′ v2는 B3 publisher 축 전용(진행 중 창 [11-02T07:57:49Z, 11-08T07:57:49Z)).
4. **메커니즘**: mechanism-2 변형이 아니다(독립 메커니즘 — 단 2-part 변경 전체에 대해서만).

**재심사 조건 3 (모두 충족 시에만 신규 후보)**: (a) 축소 스코프 복원 wall 실측 선행(별도 사전등록, "(a) 착지 후"=11-08 이후)·(b) core_purity_gate 이동의 trustSurface 경로 + attest nim-무실행 증명·(c) 판정 게이트 no-peeking 동결.

**신선도 주**: action.yml 캐시 핀은 #1199 분석(291cb2f0) 후 c24e812a3에서 v4→v6.1.0으로 회전 — 본 인용 file:line은 현재 트리에서 재확인한 값이다.

## §5 구현 사전등록에 대한 함의

- **L3-GO 이동 슬랩 사전등록의 설계 입력 확대**: (1) +2s 수당은 중앙값 등가로 유효하나 tail +4s·대형 payload 경계 조건을 명시해야 한다(§2). (2) job2a toolchain restore 시간은 이중 모드 분포(med 22.4/50.2)에서 추첨된다 — 반사실 은폐 판정의 수당 산정에 이 분포를 반영해야 한다(§3). (3) 큐 리스크 측정 4항을 사전등록 관측 계획에 포함해야 한다(§1).
- **로드맵 L2 폐쇄**: WP-B2는 BLOCKED로 종결 — 재심사 조건 3이 성립하기 전까지 재개 금지. census UNKNOWN③도 폐쇄.
- **L3 감사 §6.4의 상태 갱신**: UNKNOWN① 부분 해소·UNKNOWN② 해소 — 본 보고서 착지와 함께 L3 감사 본문에 정밀화 주를 in-place로 추가한다(census:63 정밀화 선례 계승). UNKNOWN③(코호트 외 일반화)은 유지된다.
- **변경되지 않는 것**: L3 효과 게이트(동결 단일 공식)·witness BLOCKED·GO 판정의 "구현 승인 아닌 사전등록 자격" 지위·모든 검증 의미론.

## §6 재현 명령 (전수 GET-only·읽기 전용)

**S-2 — 전송 비용 (census jsonl 재계산)**:

```bash
# A. 스텝별 전송 비용 전수 (32행 표 생성)
cat data/ci_provider/census_20261103T025821Z/batch_*.jsonl | jq -s -r '
  [ .[] | select(.type=="job") | .job_name as $j | .steps[]
    | select(.name | test("Upload |Download base-built|Download lane-|Fetch subject-certificate|Load derived-closure sets|Artifact retrieval|Consume admission B-built|artifact-id download|Bin/ax 준비|actions/upload-artifact"))
    | select(.conclusion != "skipped")
    | select(.started_at != null and .completed_at != null)
    | {job:$j, step:.name, wall:((.completed_at|fromdateiso8601) - (.started_at|fromdateiso8601))} ]
  | group_by([.job,.step])
  | map({job:.[0].job, step:.[0].step, n:length,
         med:(map(.wall)|sort|.[(length/2|floor)]),
         min:(map(.wall)|min), max:(map(.wall)|max),
         mean:((map(.wall)|add/length*10|round)/10)}) | sort_by(-.med)[]
  | "\(.med)s [\(.min)-\(.max)] n=\(.n) mean=\(.mean)s\t\(.job)\t\(.step)"'

# B. 배치별 총량 + 소형/대형 분리
cat data/ci_provider/census_20261103T025821Z/batch_*.jsonl | jq -s -r '
  def SMALLW: test("Download lane-|Upload judgment files|Upload admission records|Upload evidence record|Upload judgment record|Upload verdict log|Upload decision record|Upload reconcile verifier|Upload tested-tree-digest|Upload observer payload|Upload merge-group payload artifact|Upload derived-closure|Upload R3 relocation|Upload subject-certificate|Fetch subject-certificate|Artifact retrieval|artifact-id download|Bin/ax 준비|Load derived-closure sets|actions/upload-artifact");
  [ .[] | select(.type=="job") | .pr as $b | .job_name as $j | .steps[]
    | select(.name | test("Upload |Download base-built|Download lane-|Fetch subject-certificate|Load derived-closure sets|Artifact retrieval|Consume admission B-built|artifact-id download|Bin/ax 준비|actions/upload-artifact"))
    | select(.conclusion != "skipped")
    | select(.started_at != null and .completed_at != null)
    | .name as $s
    | {b:$b, s:$s, w:((.completed_at|fromdateiso8601) - (.started_at|fromdateiso8601)),
       cls:(if ($s|SMALLW) then "small" else "large" end)} ]
  | group_by(.b)
  | map({batch:.[0].b, total:(map(.w)|add), small:(map(select(.cls=="small")|.w)|add),
         large:(map(select(.cls=="large")|.w)|add)})
  | .[] | "\(.batch)\ttotal=\(.total)\tsmall=\(.small)\tlarge=\(.large)"'
```

**S-3 — toolchain 이중 모드 (잡 로그 원문)**:

```bash
# (1) 배치별 toolchain 스텝 시간 (정본 jsonl → cold/warm 분할 재현)
cd data/ci_provider/census_20261103T025821Z && for b in 1214..1228; do
  jq -r --arg b "$b" 'select(.type=="job") | . as $j | ($j.steps // []) as $steps |
    ($steps | map(select(.name | endswith("setup-axiom-toolchain"))) | .[0]) as $tc |
    select($tc != null and $tc.started_at != null and $tc.completed_at != null) |
    [$b, $j.job_name, (($tc.completed_at|sub("\\.[0-9]+Z$";"Z")|strptime("%Y-%m-%dT%H:%M:%SZ")|mktime) -
      ($tc.started_at|sub("\\.[0-9]+Z$";"Z")|strptime("%Y-%m-%dT%H:%M:%SZ")|mktime))] | @tsv' batch_$b.jsonl; done

# (2) job2 잡 로그 전수 (GET-only, --allow-escape-sequences 필수; job_id는 toolchain_extract_evidence.json 기록)
gh api repos/Archright/Axiom/actions/jobs/<job_id>/logs --allow-escape-sequences > /tmp/l3_job2_logs/job2_<pr>.log

# (3) 캐시 증거 행 추출 (히트/미스·검증·extract 구간)
grep -a "Cache hit for: axiom-a-\|Cache not found\|Cache Size: ~1161\|Cache restored successfully\|/usr/bin/tar -xf\|AXIOM_CACHE_A_VERIFY: OK —\|AXIOM_CACHE_B_RESTORE: exact-hit\|AXIOM_CACHE_B_VERIFY: RESULT OK\|Version: 2026\|Image: ubuntu" job2_<pr>.log
# extract(s) = "Cache restored successfully"(A) − "Cache Size" ; dl(s) = "Cache Size" − "Cache hit"
```

## §7 셀프 한정 (규율 선언)

- 본 보고서의 모든 수치는 **진단 코호트 15배치의 탐색적 추정**이다 — 확증적 성능 주장이 아니며(관측 후 고정 규율, `e3_measurement_contract_2026-10-11.md:13`), #1166 공식 SLO 모집단·판정창과 무관하다.
- 물리 하위 원인(§3)·플랜 티어·가동률(§1)은 UNKNOWN으로 유지한다 — 미관측 변수를 조용한 추정으로 채우지 않는다.
- 4건 전부 원인 귀속·측정·판정이며 **구현을 포함하지 않는다** — L3-GO 구현·캐시 재사용 확대·restore 변경은 각각 별도 사전등록(계약 + 부정 시험 + coherent generation + 신뢰 표면 인간 승인)의 소관이다.
- 서브에이전트 4건의 산출은 핵심 수치(S-2 배치별 총량 15행·S-3 extract 3배치 #1221/#1224/#1216)를 Reporter가 원본에서 직접 재검증한 뒤 재인용했다.
