# G1 — 캐시 공급 운영 복구: 동일 SHA 재등록 실험 기록 (2026-10-16)

> 상태: 1단+2단 실험 완료 후 기록(2026-10-16T03:14Z) — 판정 행은 제2 차량(본 문서 착지 PR) 관측으로 최종 확정. 계획: G1 슬라이스(nova-sam-alexander-doctor-mid-nite.md), 보강 3안전조건 준수. 정체성 조사(agent-t1lqj0kj) 결론: H-A/H-B/H-C 전부 반박 — 최선 설명은 10/12 evaluate 토글 창에서 (repository_id+path) 단위 required-workflow 이벤트 바인딩 사멸(플랫폼 측), 8+회 PUT 무효.
> 롤백 앵커 = 본 문서의 기준 스냅샷(이동하는 main이 아님).

## Ultimate Purpose

신뢰 검증 결과가 필요한 시점에 생성되고, 복구 가능 장애는 자동 복구되며, PR이 무인 큐 착지하는 운영 체계에서 **Admission 성공 → 캐시 공급 → 재사용**의 운영 경로가 실행 ID로 입증되는 것.

## S0 — 기준 상태 (2026-10-16T02:1xZ 관측, /tmp/g1/ 감사 원본)

- **빈 큐**: GraphQL `pullRequests(states:OPEN).totalCount=0`, mergeQueueEntry 보유 PR 0건 — 별도 관측. admission-check in_progress=0 / queued=0 — 별도 관측.
- **org ruleset 24233738 `axiom-admission-gate`** (enforcement=active, 대상 `refs/heads/main` × repo `Axiom`): rules 1건 = workflows rule, 파라미터 `do_not_enforce_on_create:false`, `workflows:[{repository_id:1182157951(Archright/.github), path:.github/workflows/admission-gate.yml, sha:74b415c414c0a501a1df125ad92289f0bac17bde}]`. bypass_actors=[].
  - 핀 sha 74b415c414 = Archright/.github PR #224("ci/g2-admission-pin-rotation-2") 머지 커밋(2026-10-15T20:09:52Z). ruleset updated_at 2026-10-15T20:10:44Z — 핀 회전 직후 재등록 이력. 원문: baseline-24233738.json.
- **repo ruleset 20303214 `main`** (enforcement=active): rules 5건 = deletion / non_fast_forward / pull_request(allowed_merge_methods=[merge], required_approving_review_count=0, …) / **required_status_checks contexts=[admission-check, bsec-integrity] (integration_id 15368=github-actions)** / **merge_queue(max_entries_to_build=2, merge_method=MERGE)**. bypass_actors=[]. 원문: baseline-20303214.json. ※ ruleset 20303214는 repo 소유 — org 스코프 GET은 404.
- **23943917 `landing-integrity`** (org, active): 대조군 — 실험 중 불변(원문 baseline-23943917.json).
- **publisher 워크플로**: `.github/workflows/ci-cache-publisher.yml` @ main, blob sha `a2f3f11f671c19e77e06ad27894d6c41b45ee82f`.
- **최근 publisher 10런** (38809520291, 38807425926, 38807421073, 38805746019, 38805360333, 38805137012, 38805133517, 38804510208, 38804088565, 38803987349): 전부 workflow_run(main) success — 그러나 잡 로그 전수 `[publish-skip] run path '<타 워크플로>' != .github/workflows/admission-gate.yml (orchestrator identity)` — 전부 타-바인딩 skip. 관측된 트리거 경로: closure-watcher / merge-queue-rearm / trusted-writer-set / observation / bsec-integrity / landing-integrity / probe-merge-queue / repository_surface.
- **캐시 스냅샷** (`gh cache list -R Archright/Axiom`, 2026-10-16T02:11Z): `axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-16121bd6325da639210210a19a05007d9d37c6cc` created 2026-10-11T00:52:48Z, lastAccessed 2026-10-16T02:11:07Z (용량 1,082,850,342B). `axiom-a-rt-Linux-…` 키군: 10/15 하루 8회 이상 재생성(각 ~14MB, 착지 시마다) — 재생성 주체는 publisher가 아닌 레인(계보: S3에서 정직 기록).
- **#861 선행 사례** (10/15): 실게이트 런 38787538389(.github/workflows/admission-check.yml — admission-check success 18:58:47Z) → 병합 18:59:14Z. 잡 0개 startup-failure 런 2건(38787537244/38790154599, push 이벤트 중복 발화)은 체크런 미생성 — 게이트 판정과 무관. publisher 3회 발화(18:59:23~39) 전부 타-바인딩 skip.
- **정체성 조사**(agent-t1lqj0kj, H-A 레거시 고아 가설): 본 실험 실행 시점에 보고 미수신 — 해석은 사전 고정 표로만 수행.

## S1 — 1단: 멱등 PUT (2026-10-16T02:16~02:17Z, /tmp/g1/ 감사 원본)

1. 동결 재확인 창: OPEN PR totalCount=1(PR #864, BLOCKED, mergeQueueEntry=null — 큐 미진입) + admission-check in-flight 0 → MG entry 기준 공백 유지.
2. **동결**: PUT /repos/Archright/Axiom/rulesets/20303214 (baseline 본문, merge_queue.max_entries_to_build 2→0) 02:16:17Z → 응답 readback mq=0 → **독립 GET readback mq=0**.
3. **24233738 verbatim PUT**: baseline 본문(서버 전용 필드 id/created_at/updated_at/node_id/_links 제외 — 문서화된 UPDATE 스키마는 workflows rule에 flat `workflows` 배열 사용, apiVersion 2026-03-10) 02:16:39Z → 응답 200.
4. **readback diff**: GET 02:16:50 vs baseline, `updated_at` 제외 diff = **빈 파일(0행)** — sha/enforcement/conditions/bypass/rules 전부 일치. `updated_at`도 갱신 없음(20:10:44Z 유지) → 서버가 완전 no-op으로 처리(동일 내용 재등록).
5. **해제**: PUT (baseline, mq=2) 02:17:03Z → **GET readback mq=2**, baseline 대비 diff(updated_at 제외) = 빈 파일.

## 사전 고정 판정 표 (S2/S3 결과 확정 대기)

| 행 | 조건 | 판정 |
|---|---|---|
| 완료 | 게이트 성공 → publisher가 admission-gate에 바인딩되어 발화 → publish 잡 실수행(공급) → 후속 게이트가 동일 키 restore(재사용) | G1 완료 |
| 미완료 | publisher 발화했으나 skip — 공급 없음 | publisher 내부 조건 조사(재등록 금지) |
| 실험 실패 | 재등록 후에도 미발화 | 아키텍처 대안(repo-native shim·check_run 유래 자극·스케줄 시딩) 별도 설계 승격 |
| 중단 | ruleset readback 예상 불일치 | 즉시 기준 복원·조사 |

**판정**: **실험 실패 — 최종 확정** (2026-10-16T04:03Z). 조건부 행의 관측 조건이 해소됨: 제2 차량 #867의 MG 게이트 완료(03:57:25Z) 후 ~6분 창에서 publisher 4런 전부 타-바인딩(merge-queue-rearm×2 / trusted-writer-set×2) — admission-gate 바인딩 발화 없음. 재등록 후에도 미발화 = 사전 고정 표의 "실험 실패" 행. → 아키텍처 대안(repo-native shim·check_run 유래 자극·스케줄 시딩)은 별도 설계 승인 대상으로 승격. 정체성 조사 권고(지원 티켓 + CREATE/경로 변경 레버)가 후속 설계의 입력.

## S1 관측 — 1단(멱등 PUT) 후 발화 여부 (2026-10-16T02:33~03:12Z)

- **자연 차량 #864**: MG 게이트 런 38839840065 success(02:33:32Z) → 병합 02:33:57Z → 이후 publisher 9런(02:33:40~02:39:18Z, s2_post864_pub_ids) 전부 타-바인딩 skip(trusted-writer-set×3 / merge-queue-rearm / bsec-integrity / repository_surface / observation / landing-integrity) — admission-gate 바인딩 0. 이는 **S1 멱등 PUT 이후 첫 게이트 완료**다.
- 전체 스캔: 핀 회전(10/15T20:10Z) 이후 publisher 39런 전수 바인딩 스캔 — **admission-gate 바인딩 0**(s2_publisher_binding_scan.txt + s2_post864_binding_scan.txt + s2_post866mg_binding_scan.txt). 03:09:09Z의 런 2건(38844074101/38844073851)은 잡 0개·1초 취소 인스턴스(로그 없음 — 관측 불가 플랫폼 노이즈, 바인딩 판정 불가로 무발화 증거에서 제외·기록).
- 결론: 1단(멱등 PUT — readback diff 빈 파일·updated_at 무갱신으로 서버 완전 no-op) 관측 후 **무발화** → 2단 진입.

## S2 — 관측 차량 #866 (2026-10-16T02:53~03:08Z)

- 관측 PR: #866 (docs/g1-cache-supply-experiment, 본 문서 사전 기록본) — `gh pr merge 866`으로 네이티브 MG 큐 진입(02:52Z 전후, mergeQueueEntry MQE_lQDORnV8bc8AAAABIwc1Nc4ABKwzzgNMUlU).
- **MG admission-gate 런 38842738723** (event=merge_group, gh-readonly-queue/main/pr-866-7072f938231f…) — **success 03:08:43Z** → 병합 03:08:51Z.
- gate 완료 후 publisher 대조(03:09:06~09:09Z): 4런 = trusted-writer-set×2 + 취소 2건 — **admission-gate 바인딩 0**(s2_post866mg_binding_scan.txt).

## 2단 — 룰 재생성 (remove→re-add) (2026-10-16T03:13~03:14Z)

- (a) **빈 큐 재확인 + 동결 재적용**: 03:13:10Z OPEN 0건·MG 진행 0건·admission-check in-flight 0 → 03:13:22Z 동결 PUT → GET readback mq=0 (동결 지속 가정 없음 — fresh 적용·판독).
- (b) **독립 차단 3중 입증**(fresh API 판독, s2c_proof_*.json): (i) required_status_checks contexts=[admission-check, bsec-integrity] (integration_id 15368) — 미보고 시 병합 차단(공식: checks Pending → block), (ii) pull_request 규칙(allowed_merge_methods=[merge]; 직접 push 차단), (iii) merge_queue max_entries_to_build=0(동결). 잔여 위험: 초 단위 창의 관리자 UI bypass(공식 문서화된 경로) — 창 최소화로 봉쇄·기록.
- (c) **룰 제거→재등록**: 03:13:54Z workflows 룰 제외 PUT → GET readback rules=0·나머지 필드 diff 없음(nonrules diff exit 0) → **12초 후** 03:14:06Z baseline 본문(룰 포함·sha 74b415c414) verbatim PUT → GET readback **diff=빈 파일**(updated_at만 서버 신규 12:14:06.653+09:00; 나머지 전부 동일).
- (d) **동결 해제**: 03:14:15Z PUT → GET readback mq=2·baseline diff 빈 파일.
- 대조군 23943917: 실험 전후 diff( updated_at 제외) = 빈 파일 — 불변.

## 캐시 상태 (실험 후)

- 03:14Z 스냅샷: axiom-a* 30키 — 실험 창 내 **신규 공급 키 없음**. 대형 키 `axiom-a-Linux-…` (created 2026-10-11T00:52:48Z)의 lastAccessed=2026-10-16T03:04:39Z는 #864 게이트 실행의 소비(구키 재사용)이며 publisher 재공급이 아니다. 원문: s2c_post_experiment_cache_list.json.

## S3 — 공급·소비 3분리

- **불성립** — publisher가 admission-gate 바인딩으로 발화한 런이 0건이므로 ①(발화)부터 성립하지 않고 ②(실제 저장)·③(후속 재사용)은 평가 불가. 구키 소비(#864 게이트의 axiom-a-Linux restore)는 공급 경로와 무관한 기존 소비다.

## 제2 차량 — #867 착지·최종 관측 (2026-10-16T03:39~04:03Z)

- #867(본 문서 1차 확정본) 큐 진입 지연(병렬 슬라이스의 mq=0 동결 창 03:17:58~03:19:42Z에서 auto-merge 평가 유실 추정) → 문서화된 재평가 트리거(close→reopen + auto-merge 재활성화)로 03:39:59Z 큐 진입.
- **MG 게이트 런 38846646087** (gh-readonly-queue/main/pr-867-889c06b10…) — **success 03:57:25Z** → 병합 03:57:17Z. 유의: 이 게이트는 병렬 슬라이스가 03:18:53Z 회전한 **신규 핀 ade11572052d**(.github PR #225 "p3final-mint-pin-rotation") 상태에서 실행 — 즉 무발화 관측은 내 2단 재등록과 병렬 핀 회전 양쪽 이후라는 점이 인과 해석에 그대로 기록된다(아래 인과 제한).
- 착지 후 ~6분 창 publisher 4런(03:57:31~04:00:0x, 38848112307/38848111324/38848928391/38848919807): 전부 타-바인딩(merge-queue-rearm×2 / trusted-writer-set×2) — **admission-gate 바인딩 0**.
- 캐시 재확인: axiom-a* 30키 변화 없음 — 신규 공급 0 (s2f_final_cache_list.json).

## 인과 제한

재등록(또는 핀 회전)과 발화의 성공적 연결은 **이벤트 연결이 달라졌다**는 것까지만 입증한다. 근본 원인 주장은 별도 증거가 필요하다. 본 실험의 무발화 관측에는 두 권한층 변경(내 2단 룰 재생성 74b415c414 유지 + 병렬 슬라이스의 핀 회전 ade11572052d)이 모두 선행했으나 어느 쪽도 delivery를 회복시키지 못했다 — 이는 "PUT/회전류 변경으로는 바인딩이 회복되지 않는다"는 조사 보고서 예측과 일치하는 관측이며, 특정 변경이 무효였다는 원인 규명과는 구별된다.

## 실험 후 권장 후속 (별도 설계 승인 대상 — 본 슬라이스에서 수행 안 함)

- 정체성 조사 권고: GitHub 지원 티켓(160+ 미전달 이벤트·동일 리포지토리 2-워크플로 A/B 재현 증거), ruleset CREATE 기반 full detach/reattach, 워크플로 파일 경로 변경(admission-gate-v2) 등.
- 아키텍처 대안(repo-native shim·check_run 유래 자극·스케줄 시딩) 비교 설계.

---

## 최종 판정 보강 — post-stage-2 3건 무발화 전수·양성 대조 (2026-10-16 amendment, append-only)

> **성격**: 본 절은 위 최종 확정(판정 행 전환·제2 차량 관측 — PR #869로 착지된 amendment)에 대한 **append-only 보강**이다. 판정 자체는 #869 amendment가 확정한 **실험 실패**와 동일하며, 본 절은 (i) post-stage-2 admission-gate 완료 **3건의 전수 열거**(제2 차량 MG 게이트 2건 + PR-event 완료 1건 — #869가 열거하지 않은 3번째 완료 포함), (ii) 발화 회로 생존의 **양성 대조**, (iii) 후속 수단의 승인 경계만 추가한다. 모든 런 ID·시각은 본 amendment 작성 시점 GitHub API 라이브 재검증값(완료 시각 = run updated_at 판독)이다.

**post-stage-2(2단 진입 03:13:10Z 이후) admission-gate 완료 3건 — 전부 publisher admission-gate 바인딩 0**:

| 게이트 완료 | 직후 publisher 관측 | 바인딩 판정 |
|---|---|---|
| 38844756746 (pull_request #867 차량, success, 완료 03:22:19Z) | 38845182961 (생성 03:22:25Z) — 잡 로그 원문 `[publish-skip] run path '.github/workflows/observation.yml' != .github/workflows/admission-gate.yml` | observation 바인딩 skip |
| 38846646087 (MG pr-867, success, 완료 03:56:52Z) | 38848112307/38848111324 (03:57:31-32Z) = merge-queue-rearm/trusted-writer-set만 | 0 — **#867 MERGED 03:57:17Z** |
| 38847179520 (MG pr-868, success, 완료 04:06:18Z) | 38848928391/38848919807 (04:06:55·04:07:00Z) = merge-queue-rearm/TWS만 | 0 — **#868 MERGED 04:06:42Z** |

- **양성 대조(positive control)**: publisher는 타 워크플로 완료 후 **~2초 내** 발화한다 — observation.yml 완료 03:50:32Z → publisher 런 **38847525643** 생성 03:50:34Z(라이브 재검증). 발화 회로·관측 창은 생존 — 소실은 admission-gate에 대한 workflow_run 바인딩뿐이다. 3회 독립 게이트 완료 + 양성 대조로 "발화 회로 전체가 정지했다"는 대립 가설을 배제한다.
- **결론**: PUT 경로의 양 끝 — **멱등 재등록**(readback diff 빈 파일·updated_at 무갱신 = 서버 완전 no-op, 1단)과 **룰 제거→재등록**(서버가 새 updated_at을 발급, 2단) — 모두에서 구독 재부착에 실패한다. 위 판정 행(실험 실패)의 관측 기반을 3건의 독립 완료로 완성한다.
- **인과 제한 (유지)**: 본 관측은 **PUT 경로로의 연결 비복원성만 입증**한다(위 인과 제한 절 서술과 일치 — 2단 재등록과 병렬 핀 회전 ade11572052d 양쪽 이후에도 무발화). 근본 원인 — 10/12 evaluate 토글 창의 (repository_id+path) 단위 required-workflow 이벤트 바인딩 사멸 가설 — 는 여전히 **미증명**이며, 실험 실패는 그 가설과 정합적일 뿐 확증이 아니다.
- **후속 수단 (승인 경계 재확인)**: 위 '실험 후 권장 후속'의 3경로 — ① ruleset DELETE+CREATE 후 fresh registration, ② Archright/.github 워크플로 파일 경로 rename + ruleset path 필드 갱신((repository_id+path) 쌍의 신규 발급), ③ GitHub support ticket(A/B 재현: landing-integrity는 workflow_run 이벤트 수신, admission-gate는 미수신 — 핀 회전(10/15T20:10Z) 이후 누락 이벤트 160+건, 대상 런 ID 일람 38842738723·38846646087·38847179520) — 은 모두 **개별 승인 없이는 착수하지 않는다**(본 amendment에서 실행 없음).
