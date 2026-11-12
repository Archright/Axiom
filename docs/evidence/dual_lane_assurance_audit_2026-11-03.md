# Dual-Lane Assurance Audit — admission 체인 vs axiom-operational-slice 보증 책임 감사 (2026-11-03)

- **방식**: READ-ONLY(실행 의미론 변경 0) — 원본 워크플로·ADR·계약 문서 file:line 대조 + 기존 Census 15배치 원시 데이터 재계산. 서브에이전트 검증 패스 3건(admission 의무·opslice 의무·반사실 산술)의 산출을 본 감사 Reporter가 원본에서 재검증해 재인용했다(핵심 인용 6건 직접 대조 완료).
- **Authority**: merge admission = GitHub(repo ruleset 20303214 + org ruleset 25218071·23943917 + merge queue). 본 감사는 Reporter다(Authority ≠ Adapter — census 각주 계승).
- **판정 단위**: 4분류(DUPLICATE/COMPLEMENTARY/DEPENDENT/UNKNOWN)는 **증명 의무(Proof Obligation) 단위**에 적용한다. 계산(computation) 단위의 중복 표는 입력 물자일 뿐 — 같은 계산을 공유하는 것과 같은 명제를 입증하는 것은 별개다(B-cache가 정확히 그 사례: 동일 payload, 상이 명제).
- **절감 2축**: 실행 비용 절감(러너 점유)과 병합 시간 절감(Native MERGE wall)을 별도로 계산한다(§5). 필수 체크가 전부 성공해야 병합이 허용되므로 wall은 **마지막 필수 체크**가 결정한다 — 임계경로 밖 절감은 병합 시간에 0이다.

## §0 판정 요약

| 항목 | 판정 |
|---|---|
| 레인 간 중복 증명 의무 | **DUPLICATE 0건** — 두 레인은 의무 수준에서 COMPLEMENTARY(§3) |
| 레인 간 소비 의존(DEPENDENT) | 0건 — opslice `needs:` 0·타 워크플로 artifact 다운로드 0; admission 체인도 opslice 산출 불소비 |
| S5 비대칭(opslice는 HIT에서도 재컴파일 med 191s, admission은 HIT 생략) | **CONFIRMED — 단 skip 기계의 비대칭이지 중복 확정이 아님**(§6) |
| 4-binary 재컴파일 제거의 병합 시간 효과 | **0.0s — 15/15 배치**(opslice는 관측 기간 중 단 한 번도 마지막 필수 체크가 아니었음, §5) |
| 실행 비용 절감(러너 점유) | 실측 **2,577s/15배치**([124,202]s, med 191s) — 단 레인 간 소비 계약 부재로 구현 불가(§7 UNKNOWN①) |
| 최종 판정 | **GO 0 / BLOCKED 3 / UNKNOWN 2**(§7) |

핵심 결론: admission 체인은 **MergeAdmissible(B,H,M) 입장 판정**을, opslice는 **G 트리 제품 증명 경로(`ax prove` → Lean 커널 리플레이 → FRESH-SATISFIED)**를 증명한다 — 두 레인이 같은 사실을 반복 입증하지 않는다(§2·§3). 병합 지연은 admission 체인이 15/15 배치에서 지배하므로(census §3), opslice 측 절감은 병합 시간을 1초도 줄이지 못한다. "보증은 유지하면서 같은 일을 두 번 하지 않게 한다"가 목표였다면 — **현재 구조가 이미 그렇다**: 명제 수준 분리(입장 판정 ∥ 제품 증명) + 공급 수준 공유(A/B 캐시·publisher 단일성).

## §1 배경·질의·방법·인용 유효성

**배경**: Node24 Merge-Queue Critical-Path Census(`node24_merge_queue_critical_path_census_2026-11-03.md`, PR #1232·#1233 착지)는 병합 wall med 727s의 임계경로가 admission 체인(15/15)이며 opslice(med 458s, headroom med 240s)이 병렬 필수 경로임을 확정했다. 본 감사는 그 다음 질의를 다룬다: **두 필수 경로가 각각 무엇을 증명하며(Proof Obligation), 동일한 명제+동일한 입력의 반복 계산(DUPLICATE)이 존재하는가.**

**질의 3개**: (Q1) 각 레인의 잡/스텝별 증명 명제·입력 트리·실패 의미론은 무엇인가. (Q2) 의무 단위 4분류에서 DUPLICATE는 몇 건인가. (Q3) 입증된 중복이 있다면 절감 효과는 병합 시간과 실행 비용 각각 얼마인가.

**인용 유효성**: census 스냅샷(`data/ci_provider/census_20261103T025821Z/workflow_defs/`)은 **org 핀 required workflow 2파일만** 포함한다(`admission-gate-v2.yml` 713행, `landing-integrity.yml` 375행 — manifest 기준). `admission-check.yml`·`certificate-mint.yml`·`runner-pool-acceptance.yml`은 repo-native callee로 스냅샷에 없으며, 저장소 작업트리 원문으로 검증했다 — 게이트가 참조하는 callee 핀 `@498c55704552291da926fae6eb34bc5c0c04ec1b`(admission-gate-v2.yml:440·492·549·584·666)에 대해 `git diff 498c5570… -- <file>`이 3파일 모두 공백(바이트 동일)이므로 작업트리 검증 = 핀 정의 검증이다.

**현행 required context 6개**(census manifest `required_gates`): `admission-check`·`bsec-integrity`·`debt-registry-gate`·`generation-acceptance`·`axiom-operational-slice` + `landing-integrity`(org 23943917). gate-v2의 SHA-핀 주체는 org ruleset **25218071 단독**(`docs/spec/admission-generation.md:12·16`)이며 repo ruleset 20303214는 `admission-check` 컨텍스트를 required_status_checks로 **소비**한다(핀하지 않음).

## §2 Phase 1 — 증명 의무 해체

### §2.1 admission 체인 (admission-gate-v2.yml — org 핀 스냅샷)

최종 단언: **required check `admission-check` = 롤업 7잎(anchor-resolve[off-PR skip만 허용] ∧ closure-deriver ∧ attest ∧ mint-prepare ∧ mint-publish ∧ verdict ∧ gateway) conclusion 전부 success**(`admission-gate-v2.yml:671-713`, :694-700) — 핵심 판정은 verdict 스테이지의 `ax merge --dry-run --json` 종료 코드가 순수 술어 **MergeAdmissible(B,H,M)**을 투영한 것(admission-check.yml:2703-2722, "The step exit IS the required check's conclusion" :1920-1921). 임의의 실패·생략(skip은 anchor-resolve의 off-PR 정상 상태 외 전부 차단)·아티팩트 부재·등식 불일치 = 절대 초록이 아니다(fail-closed).

| 잡 (file:line) | 증명 명제 | 입력(B/H/M/G) | 실패 의미론 | 산출물→소비자 |
|---|---|---|---|---|
| anchor-resolve (191-212) | run당 1회 B*(live main tip) 해석 — 준비 전용, 착지 판정 입력 아님(ADR-0027 P4) | live main ref | 해석 실패 = red | B_STAR → 5잡 baseSha(:669) |
| closure-deriver (221-409) | B-고정 hermetic deriver가 B/H[/M] 클로저·pin@H·identity를 all-or-none 도출; MG에서 H:=parent2(G) 리바인드(:298-304), M=merge-tree(B,H)==tree(GITHUB_SHA)(:318-336) | B=B*∥pr.base∥mg.base(:227), H, M | 40-hex·컴파일·등식 깨짐 전부 red | derived-closure → verdict·proof-reconcile |
| attest (430-443→admission-check.yml) | B 빌드·identity·D9·witness(Built-from-B 검증기 — Gate A) | baseSha=B* | callee red → 롤업 차단 | witness → mint·verdict |
| mint-prepare (464-499) | untrusted witness 검증·정규화·canonical cert 서명 | runId/headSha/baseSha | 실패 = NO_CERT → 착지 차단 | subject-certificate → publish(P1)·verdict(--cert) |
| mint-publish (539-556) | P0–P7 전 통과 후 레저 append 정확히-한번(APPEND_COUNT∈{0,1}, certificate-mint.yml:2186-2189) — 런타임 유일 contents:write 보유자(certificate-mint.yml:89·1248; 래퍼층 mint-prepare·publish 양잡 job-level contents:write 선언은 callee 최상위 일치 강제 — gate-v2:456-459) | 동일+witness 재다운로드(P4) | P* fail = 발행 차단 | 레저 항목 → 차후 admission·감사 |
| gateway (574-587→runner-pool-acceptance.yml) | selector exit 0/2 계약(runner-pool:543-573)·decision envelope(mode/shards/landingPolicyFloor — tools/ci/impact_closure_selector.nim:1051-1065)·B-트리 epoch_manifest implementedSlices — 부재 슬라이스 = NO-FIRE fail-closed(admission-check.yml:35-63·280-329) | target_sha=github.sha(:586) | selector 이상 exit = FAIL | ci-select-*·tested-tree-digest → publish P5/P6 |
| verdict (658-669→admission-check.yml:2257-2730) | 5파일 클로저 로드→SL-02 L1/L2→candidate-delta M 재유도(:2584-2651)→`ax merge --dry-run` — **exit = check conclusion** | B·H·M(재유도), cert=artifact∥side-ref ledger(:2687-2694) | NOT-ADMIT = exit 1 = check FAIL | context `admission-check` |

**admission-check.yml 내부**: build-base-artifacts(200-657 — **B 전용 체크아웃** :251-258, manifest 결속 :534-550) · identity(1094-1353 — SUBJECT_HEAD=parent2(G) :1243, merge-tree 등식 :1318-1353) · D9+witness-only(1399-1783 — 서명·네트워크 0 커널 증명) · go-critical-lane 0/1(2890-3663 — B 실행기에 M 오버레이, lane1=proof_integrity·d2_golden·d2_persist) · go-critical-rollup(3684-3706 — worst result만 허용). M 등식은 deriver·attest identity·verdict CD에서 **삼중 검증**되고 mint P5에서 제4층으로 재검증된다(witness.mergeTreeDigest==tree(mergeSha), :1090-1092).

**s5-supply 판정**(admission-check.yml:356-377): 6파일(4 binary+ircheck+fingerprint) 존재·실행가능 ∧ nimcache → `mode=skip`(공급 재사용) / 결핍 → `mode=build`(콜드, fail-closed). [build] 컴파일 블록(:469-489)·nimcache probe(:402)·lake smoke(:438)은 mode==build에서만 실행된다.

### §2.2 opslice (axiom-operational-slice.yml — repo, 180줄)

최종 단언(워크플로 헤더 + ADR-0037): **"prove가 만든 증명서 = Lean 커널이 수용한 증명서"** — G 트리를 증명성 검증 release verifier로 빌드하고, 실제 `ax prove`가 `normalizeMaxWorkers` 선언 후건을 신실행 확립(Lean 커널+Z3 이중, FRESH-SATISFIED)한다. `needs:` 0·타 워크플로 artifact 다운로드 0 — 완전 자기완결.

| 스텝 (file:line) | 증명 명제 | 입력 트리 | 실패 의미론 | 산출물 |
|---|---|---|---|---|
| checkout fetch-depth 0 (36-38) | G 전체 이력 확보 | G | 즉시 실패 | — |
| setup-axiom-toolchain (39-41) | A/B 레이어 복원 — b-key=closure(G)+recipe+a_fp(action.yml:263-302), 복원 시 b-verify+SourceCoherence probe fail-closed(action.yml:435-542·576-667) | G | verify/probe FAIL → 폐기→콜드 | 툴체인+nimcache+4 binary |
| make ci-compile (42-48) | 4 binary를 G에서 ci-compile authority로 재생산 — **AXIOM_S5_BUILD_SKIP 미설정 → 항상 컴파일 분기**(checker.mk:488-492) | G | make 실패 = 잡 실패 | bin/* (스텝 7·8 공급) |
| lake build ircheck (49-56) | 참조 추출기 생산 — 미생산 시 노드 NOT_VERIFIABLE 강등 | G | 즉시 실패 | ircheck |
| wp5 R3 (60-77) | relocation 불변 4관측+경고 0+digest 결속 | G | jq -e 실패 = 즉시 실패 | r3_relocation.json |
| verify-contract-release-e2e-full (78-79) | **제품 증명 사슬**(Makefile:886-939): --check-provenance(:889) → ax prove --target normalizeMaxWorkers(:892) → ax report --json(:893) → verdict/exit 일치(:907-911) → vault cert(:918-921) → cert verify --kernel(:922-923) → run↔cert identity join(:926-928) → FRESH-SATISFIED(:929-931) → report/state 일치(:933-935) → E2E 중 바이너리 해시 불변(:936-937) | G | 어느 단계든 exit≠0 = 잡 실패 | verify_contract_e2e_* |
| run manifest+provenance (92-122) | expected(git+build_env) vs actual(--check-provenance) fail-closed 일치·dirty 거부(:112-113)·4축 단언(gitHead/binSha/engineBuild/buildSourceHash, :116-119) | G | fail() = 즉시 실패 | run-manifest.json |
| DEBT#508 ratchet (123-142) | cold serial↔parallel prove — digest·certificate·exit·timeout 동일 | G | 즉시 실패 | — |
| L4 landing_observe_contract (143-159) | 상태 전이 6종+API-call budget | G | 즉시 실패 | — |
| artifact 업로드 (160-180) | `if: always()` — 실패 증거 보존(삼키지 않음) | — | — | evidence·r3 |

### §2.3 존재 이유 대조 (ADR-0037:10-17)

> "Before this decision, no required check ran the product's own verification path. The four live contexts (admission-check, bsec-integrity, debt-registry-gate, generation-acceptance) enforced admission, ledger, and policy coherence — **none executed `ax prove`**, and `ax cert verify --kernel` was dead code in CI … a PR could land while the proof path it carried was never observed by the authority that admits it."

**기계 확인(전수 검색)**: admission 체인 4파일(admission-gate-v2·admission-check·certificate-mint·runner-pool-acceptance)에서 `ax prove` **0건**·`ax cert verify --kernel` **0건**·`lake build`는 ircheck/스모크 전용(:455·:482·:658·:746). 제품 증명 경로의 유일 required-check 경로는 opslice다(ADR-0037:26-29, ruleset 20303214의 5번째 context, integration_id 15368). 양 레인의 판정 대상이 다르다 — admission: H 후보에 대한 B-검증기의 정적 사슬 / opslice: G 트리의 실제 커널 재실행.

## §3 Phase 2 — 보증 매핑 · 4분류 (증명 의무 단위)

| 증명 의무 | admission 체인 | opslice | 판정 |
|---|---|---|---|
| O1 입장 판정 MergeAdmissible(B,H,M) | verdict(`ax merge --dry-run` exit) | — | **COMPLEMENTARY**(admission 전유) |
| O2 B/H/M 클로저 도출·M==tree(G) 삼중 검증 | deriver·identity·CD | — | COMPLEMENTARY |
| O3 witness·인증서 서명·원장 exactly-once | attest·mint(P0–P7) | — | COMPLEMENTARY |
| O4 GO-critical 테스트 배터리(B 실행기·M 오버레이) | go-critical-lane 0/1 | — | COMPLEMENTARY |
| O5 제품 증명 경로(G): ax prove→kernel 리플레이→FRESH-SATISFIED | —(0건, §2.3) | :78-79 | **COMPLEMENTARY**(opslice 전유) |
| O6 R3·DEBT#508·L4 | — | :60-159 | COMPLEMENTARY |
| O7 **4-binary 검증기 공급** | closure(**B**) — S5 mode=skip 시 캐시 공급+provenance 재단언 | closure(**G**) — ci-compile authority, 무조건 | **COMPLEMENTARY — 입력 트리 상이(B vs G)**. 계산 수준의 공유 가능성은 §6의 미입증 가설 |
| O8 A-layer 툴체인 | 동일 a-key | 동일 a-key | SHARED(인프라 — 의무 아님; scope 네임스페이스 2종 action.yml:199-204) |
| O9 B-layer payload(nimcache·4 binary·ircheck) | closure(B) | closure(G) | SHARED-조건부 — docs/.github-only 배치에서 closure(B)≡closure(G) → 동일 b-key exact-hit. **n=1 실측(#1221)**; 14배치 미추출(§7 UNKNOWN②); src/ 변경 배치는 2키 분기 |

- **DUPLICATE 0건**: 동일 명제+동일 입력의 반복 입증은 의무 수준에서 존재하지 않는다. O7은 같은 4개 바이너리를 생산하지만 신뢰 닻이 상이하다 — admission은 Gate A(검증기는 BASE 빌드 — PR 트리 자기참조 차단, admission-check.yml:5·22-33), opslice는 run manifest의 G-빌드 결속(:116-119).
- **DEPENDENT(레인 간) 0건**: opslice는 admission 산출물을 소비하지 않고(:2.2), admission 체인도 opslice 산출물을 소비하지 않는다(artifact 흐름 전수 분류 — same-run 소비는 전부 admission 체인 내부: derived-closure·base-artifacts·witness·certificate·tested-tree-digest·ci-select-*·go-judgment). 공유는 전부 **제3 writer(ci-cache-publisher, workflow_run 단일 비행)** 경유의 인프라다.
- **b-identity는 소스 SHA가 아니다**(census §5, #1221 3-way 로그): base `aaba7fb3…`와 merge head `a5cfd5bb…`가 다른 SHA여도 의미론적 클로저+레시피+a_fp 다이제스트가 동일하면 동일 b-key(`06b9e0c6…`) exact-hit — 중복 컴파일 0. 재컴파일은 설계된 동작(J3 계약)이다.

## §4 Phase 3 — 실행 그래프 중첩

- **Admission DAG**(census §4 복원): anchor-resolve → closure-deriver → attest(87s med) → go-critical-lane(377s med, 지배) ∥ mint-prepare(34s)·mint-publish(48s)·verdict(110s)·gateway → 7-fold rollup. 잡 wall 합 med 663s [462,777].
- **opslice**: 단일 잡(merge_group 트리거, G 체크아웃) — admission 체인과 **병렬**이며 레인 간 논리 간선 0.
- **공유 인프라**: A-cache(동일 a-key)·B-cache(조건부 동일 b-key)·writer 단일성(`ci-cache-publisher` — 어느 레인도 B를 직접 저장하지 않는다, `cache-save-enabled: 'false'` 전 호출자). **캐시 접근 스코프는 저장소+브랜치 단위이며 워크플로별 신뢰 경계를 플랫폼이 제공하지 않는다**(GitHub Actions 공식 문서 — "Multiple workflow runs in a repository can share caches") — 기계적 공유 ≠ 소비 권한.
- **Resource Contention(그래프 B)은 논리 의존과 별도 유지**: 교차 배치 실행 중첩 4쌍(최장 #1223/#1224 716s)은 census §6에서 관측 가설(인과 미입증)으로 종결됐고 본 감사가 재판정하지 않는다.

## §5 Phase 4 — 절감 2축 (병합 시간 vs 실행 비용)

**방법**: census 원시 `batch_*.jsonl` 15배치에서 배치별 A=admission-gate 성공 잡 최종 완료(임계), O=opslice 완료, c=compile 스텝 실측(`Build the release verifier (ci-compile authority)`)을 재추출하고 `wall Δ = max(A,O) − max(A,O−c)` 반사실을 계산했다(measured·uniform−191s 양변형). 전 값은 census `analysis.json`과 15/15 교차검증 일치(재실행 결정론 — `data/ci_provider/dual_lane_audit_20261103T060040Z/counterfactual.py`).

| 배치 | A 완료 | O 완료 | headroom(s) | O 마지막? | compile 실측(s) | wall Δ |
|---|---|---|---|---|---|---|
| 1214 | 08:47:51Z | 08:45:56Z | 115 | 아니오 | 133 | 0.0 |
| 1215 | 09:05:05Z | 09:02:46Z | 139 | 아니오 | 194 | 0.0 |
| 1216 | 09:51:40Z | 09:47:28Z | 252 | 아니오 | 202 | 0.0 |
| 1217 | 09:36:17Z | 09:32:17Z | 240 | 아니오 | 193 | 0.0 |
| 1218 | 09:42:07Z | 09:40:52Z | 75 | 아니오 | 160 | 0.0 |
| 1219 | 12:49:00Z | 12:45:28Z | 212 | 아니오 | 191 | 0.0 |
| 1220 | 13:49:43Z | 13:45:13Z | 270 | 아니오 | 201 | 0.0 |
| 1221 | 14:00:53Z | 14:00:36Z | **17** | 아니오 | 198 | 0.0 |
| 1222 | 14:42:07Z | 14:35:21Z | 406 | 아니오 | 127 | 0.0 |
| 1223 | 15:10:09Z | 15:04:26Z | 343 | 아니오 | 192 | 0.0 |
| 1224 | 15:11:02Z | 15:05:44Z | 318 | 아니오 | 149 | 0.0 |
| 1225 | 15:35:04Z | 15:30:22Z | 282 | 아니오 | 124 | 0.0 |
| 1226 | 15:57:11Z | 15:56:31Z | 40 | 아니오 | 201 | 0.0 |
| 1227 | 02:29:37Z | 02:23:42Z | 355 | 아니오 | 131 | 0.0 |
| 1228 | 02:35:08Z | 02:32:55Z | 133 | 아니오 | 181 | 0.0 |

- **병합 시간 축**: 개선 배치 **0/15**, 총·중앙값 절감 **0.0s** — opslice는 15/15 배치에서 마지막 필수 체크가 아니었다(최소 우위 #1221 = 17s조차 compile 실측 198s보다 작다). critical_wf = admission-gate 15/15(census와 일치).
- **실행 비용 축**: compile 스텝 15/15 배치 존재([124,202]s, med 191s) — **합 2,577s(≈43.0분)/15배치**(uniform 15×191s 기준 2,865s 환산). 캐시 히트와 무관하게 매 실행 재컴파일(J3: cache is acceleration, never evidence). 배치별 히트/콜드 구분은 원시 jsonl에 스텝 상태가 없어 **UNKNOWN**(exact-hit 로그 원문은 census §5의 #1221만 — 로그는 90일 보존).
- **교차점 산술**: opslice(−c)가 새 임계가 되려면 admission 감축량 > headroom+c — 배치별 역치 **215s(#1221)~535s(#1223), med 406s**. 즉 191s 단축만으로는 역할 교대가 없고, admission이 평균 약 2.1배(406/191) 더 줄어야 opslice가 병합 지연을 지배하기 시작한다. **병합 시간 개선의 유일 경로는 admission 체인 감축이며, 그 시점 이후에만 opslice 절감의 병합 시간 가치가 발현된다.**

## §6 S5 비대칭 가설 — 상태와 중복 승격 조건

**관측된 비대칭 CONFIRMED(정적+런타임)**: 같은 b-identity 창(예: #1221 docs-only 배치)에서 admission 레인은 HIT 공급을 재사용하고(컴파일 0회 — census 15런 전부 mode=skip, [build] 스텝 부재), opslice는 같은 공급을 매 런 재컴파일한다(15/15, med 191s). **이것이 확립하지 않는 것**: 두 레인의 컴파일이 동일 계산의 중복이라는 주장.

**skip 기계 3종(비대칭의 실체)**:

| 메커니즘 | 위치 | 작동 |
|---|---|---|
| ① if-게이트 mode=skip | admission-check.yml:356-377 | s5-supply 판정이 6멤버 존재·실행가능 확인 → mode=skip → [build] 블록(:469-489)·probe·smoke 미실행 |
| ② AXIOM_S5_BUILD_SKIP 플래그 | runner-pool-acceptance.yml:719-730 + checker.mk:488-492 | ifeq → ci-skip-*(각 binary --check-provenance 재단언, fail-closed — checker.mk:499-518). "스킵은 ASSERTION이지 bypass가 아니다"(checker.mk:478-483) |
| ③ opslice | **미배선** | AXIOM_S5_BUILD_SKIP 0건 — checker.mk ifeq가 항상 else(컴파일) 분기 |

**중복 승격(구현 제안 이전)에 필요한 증거 4**: (1) 동일 배치 양 레인 b-identity 로그 대조 — **정밀화(2026-11-03, unknown_closure §2)**: n=1(#1221) → **n=15 완료** — 12/15 cross-lane SAME + 3/15(src 변경 #1220·#1222·#1223) 예고된 2-key 분기(양측 exact-hit=true, 75/75 원문 추출). 단 §6(3)의 "src/ PR은 양 레인 각자 콜드" 예측과 달리 실측은 양측 모두 exact-hit였다(신규 키 엔트리가 이미 존재 — 게시자 체인은 범위 밖); (2) 산출물 동등성(J2 관점) — BuildSourceHash·certificate identity 필드 비교(같은 트리 리빌드도 바이트 비동등 허용, action.yml:601-605); (3) src/ 변경 배치의 2-key 분기 경계 명시(분기 시 후보 자체가 무효 — #1234류 src/ PR은 양 레인 각자 콜드); (4) 미배선 상태의 반사실(ci-skip-*이 G 트리 워크스페이스에서 통과하는지)은 배선 전 관측 불가.

**J계약 2층 분리(감사 확정)**: 기존 J1–J4는 **레인 내부**(후보 적용 전↔후 등가) 재사용 계약이다(`ci_optimization_tcb_judgments.md:13-20` — S5는 §3.1 공급 재사용·"판정은 항상 재계산", :148-155 용어 계약). **레인 간 소비 계약은 존재하지 않는다** — docs/spec·docs/adr·docs/agents 전수 grep 0건(`cross_venue_b_reuse_closure §5`의 "전달 계약 불필요" 판정은 admission 체인 내부 venue 간(PR↔MG) B-reuse에 한정되며 opslice를 당사자로 규정하지 않는다 — "컴파일 gate는 venue=='landing'에서만 열린다"). opsliice가 자체 G-빌드를 캐시 공급으로 대체하려면 **별도 신뢰 계약 + 부정 시험 + 신뢰 표면(인간 아키텍트) 승인**이 필요하며, 그 수립은 본 감사가 아니라 중복 입증 이후 차기 사전등록의 소관이다. 플랫폼은 캐시의 기계적 공유만 허용할 뿐 소비 권한을 부여하지 않는다(§4).

## §7 판정 — GO 0 / BLOCKED 3 / UNKNOWN 2

기준(census §7 계승): 실제 비용 재현 · 임계경로 위치 · 제어 가능성 · 검증 의미론 보존 · 노이즈 대비 효과 · 부정 시험 가능성.

**GO 0건.**

### BLOCKED 3건 (변경하지 않고 종결)

| # | 대상 | 근거 |
|---|---|---|
| ① | 레인 통합·한쪽 제거·판정 재사용 확장 | 양 레인은 COMPLEMENTARY(§3) — 제품 증명 경로와 입장 판정의 분리는 ADR-0037 부정 대조(PR #1041: 후건 위조 → FAILURE → mergeStateStatus BLOCKED)로 실증된 신뢰 구조. 검증 의미론 보존 불가 |
| ② | opslice 비용의 **병합 시간 최적화**로서의 지위 | 임계경로 밖 15/15, Δ=0.0s(§5) — 임계경로 기준 미충족. 실행 비용 전용 가치(2,577s)는 별도 축(UNKNOWN①) |
| ③ | admission 체인 내부 비용 | census §7 BLOCKED ①–⑦ 승계(A-restore·GO tests·mint tail·플랫폼 구간·required 구조 등) — 본 감사는 새 증거 없이 재판정하지 않는다 |

### UNKNOWN 2건 (입증 불가 — 추가 증거 없이 변경 금지)

| # | 항목 | 미입증 내용 |
|---|---|---|
| ① | S5 opslice 확장의 **중복성**(실행 비용 전용 후보) | §6 증거 4항 미확보 + 레인 간 소비 계약 부재. 설사 입증돼도 병합 시간 효과 0(§5)이므로 그 병합-시간 가치는 admission 감축 역치(med 406s) 이후에만 발현 — 세대 설계 주제 이후의 후속 최적화로 기록 |
| ② | #1221 외 14배치의 cross-lane b-identity 일반화 | exact-hit 로그 원문 미추출(배치 jsonl에 캐시 상태 없음) — 조용한 추정 대신 UNKNOWN 유지. **정밀화(2026-11-03, unknown_closure §2)**: **해소** — 75잡 로그 원문 전량 추출: 12/15 SAME + 3/15 예고된 2-key 분기, 75/75 exact-hit=true. 단 (1)만 완료 — 아래 UNKNOWN①은 유지 |

## §8 발견 — 문서 정합성 residuals 5건 (본 감사는 READ-ONLY로 수정하지 않음)

1. **레인 간 계산 공유 SSOT 부재**: "어느 레인이 무엇을 계산하고 무엇을 공유할 수 있는가"를 정의하는 문서가 docs/spec·adr·agents 전역에 없다(§6 전수 grep). 본 보고서(§2·§3)가 첫 매핑 정본이다.
2. **action.yml:22-25 J3 헤더 시대착오**(admission 한정): "the 4 ci-compile binaries are recompiled even on a HIT **today**; census **2026-09-30**" — S5 착지 후 admission 체인은 HIT에서 재컴파일하지 않는다(census 15런 [build] 부재). 스펙 측은 정정 완료(tcb_judgments.md:148-155)되었으나 action 헤더가 뒤처져 있다. 후속: 헤더 1문장 갱신(별도 PR).
3. **opslice:43-47 주석 드리프트**: "on a B-layer cache HIT it skips recompiles and instead re-asserts each restored binary's provenance" — AXIOM_S5_BUILD_SKIP 미배선으로 정적 도달 불가. 괴리 방향이 보수적(주장보다 더 실행)이므로 극장 아님(§0.9). 후속: 주석 정정.
4. **opslice:44 "-d:release … ax/gate_hook/precompile_gates/install_ax_cas" 부정확**: `-d:release`는 `ci-compile-ax`만(checker.mk:530); 나머지 3종은 디폴트 프로파일, LTO는 config.nims:47-56 조건부.
5. **census 스냅샷 admission-gate-v2.yml:61 헤더의 폐기 ruleset ID "24233738"**(→ 현행 25218071, admission-generation.md:12): 스냅샷 원문 보존 원칙상 수정하지 않고 본 감사가 기록한다.

## §9 검증 가능성 (재현)

정본 데이터: `data/ci_provider/dual_lane_audit_20261103T060040Z/`(manifest.json·mapping.json·counterfactual.py — `*.py`는 언어 금지 구조로 `git add -f` 착지, .gitignore:138-142 선례 계승).

```bash
# 1) Phase 4 수치 재현 (census 원시 데이터 — 읽기 전용, 결정론)
cd data/ci_provider/dual_lane_audit_20261103T060040Z && python3 counterfactual.py
# → 15배치 표 + wall Δ 0.0s×15 + compile 합 2,577s + 역치 [215,406,535]s

# 2) callee 인용 유효성 (작업트리 == 핀 정의)
git diff 498c55704552291da926fae6eb34bc5c0c04ec1b -- \
  .github/workflows/admission-check.yml \
  .github/workflows/certificate-mint.yml \
  .github/workflows/runner-pool-acceptance.yml   # → 공백(바이트 동일)

# 3) required 집합·핀 readback (GET-only)
gh api repos/Archright/Axiom/rulesets/20303214 --jq '.rules[] | select(.type=="required_status_checks")'
gh api orgs/Archright/rulesets/25218071 --jq '.rules[].parameters.workflows[] | {path, repository_id, sha}'
gh api orgs/Archright/rulesets/23943917 --jq '.rules[].parameters.workflows[] | {path, repository_id, sha}'
# → sha 7eaa9624… · path .github/workflows/{admission-gate-v2,landing-integrity}.yml · repo_id 1182157951
#    (2026-11-03 교정: org ruleset REST API의 rule type은 "workflows"·매개변수 .parameters.workflows[] —
#     기존 "required_workflow" 경로는 현행 응답에서 빈 출력. SHA·repo_id 판독 결과는 불변)
```

## §10 셀프 한정

- 본 감사는 **Reporter**다 — merge admission authority는 GitHub다. 본 감사는 어떤 required check·워크플로·캐시 계약도 변경하지 않았다(READ-ONLY).
- n=15는 census 진단 코호트(2026-11-02T08:08:28Z~2026-11-03T02:58:21Z 자연 발생 배치)이며 #1166 공식 SLO 판정을 산출·선점하지 않는다 — census §3의 495s 반사실 추정에 대한 정밀화(1문장)를 동반 착지했다(census 보고서 §3).
- cross-lane b-identity 동등성은 **n=1(#1221)** 실측에 기반한다 — 14배치 일반화는 UNKNOWN(§7②).
- 감사 결과가 GO를 낸 경우에도 구현은 별도 사전등록(계약+부정 시험+coherent generation 설계+신뢰 표면 인간 승인)의 소관이다 — 본 감사의 착지는 보고서·데이터까지다(§6 2층 분리 참조).
