# node24 mint tail 내부 비용 분해 (certificate-mint tail decomposition) — 2026-11-02

> **종류**: 성분 분해 분석 기록 (component decomposition analysis) — node24 신세대(ciGeneration N+8) merge_group 배치의 **mint tail**(`mint-prepare` + `mint-publish` 직렬 2잡) 내부 step 비용 귀속. 선행 문서 `docs/evidence/node24_merge_group_job_decomposition_2026-11-02.md` §5/§6-3이 "대상 잡 범위 밖 — 내부 비용 미분해, 후속 조사 입력"으로 남긴 영역의 후속 조사다. 본 문서는 코드·워크플로·게이트·판정 의미론을 변경하지 않는다(관측·분석만 — GET-only).
> **Date**: 2026-11-02 · **Branch**: docs-only PR(`docs/evidence/` 착지 — 관측 종결 문서 5건 동반: 본 문서·캐시 회전 관찰(`actions_cache_rotation_observation_2026-11-02.md`)·SLO 상태 스냅샷(`slo_status_snapshot_2026-11-02.md`)·교차-venue 종결(`cross_venue_b_reuse_closure_2026-11-02.md`)·판정창 사전등록(`slo_judgment_window_prereg_2026-11-02.md`)) · **Scope**: 본 문서 1건(`docs/evidence/node24_mint_tail_decomposition_2026-11-02.md`) — 코드·워크플로·게이트·핀·도구 변경 0건. docs-only 비행 → trust surface 아님(정상 merge queue 경로).
> **권위**: 런/잡/스텝 존재·타임스탬프·결론 = GitHub Actions REST API(GET-only, jobs 조회 `filter=latest` 명시, 표본 전부 `run_attempt=1`; 잡 수준 wall·직렬 구간의 권위는 목록이 아니라 단일 GET — 선행 문서 §7-2 규약 준수). 런→head 매핑(§2) = run 객체 단일 GET(`head_sha`·`created_at`·`head_branch` — 2026-11-02 GET-only 검증, §8-3b 재현). 워크플로·액션 동작 정의 = org 저장소 콘텐츠 GET(`Archright/.github` admission-gate-v2.yml@main blob `0ef1a441`, `Archright/Axiom` certificate-mint.yml@498c5570 blob `6e6e5b03`, setup-axiom-toolchain action.yml@498c5570). 본 문서는 Reporter다 — 병합 판정 권위(GitHub ruleset·merge queue)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).
> **측정 기준**: api-second-granularity(±1 s) · step wall = `completed_at − started_at` epoch 차감(jq `fromdateiso8601` — 선행 문서와 동일 계보) · skipped 판별자 = `conclusion == "skipped"`(스테이지 매트릭스 반대 레그 — '실행 안 됨' 마킹, 타임스탬프 역전 quirk 재확인: `mint-prepare / publish` 등 skipped 잡은 completed < started) · mint tail 직렬 구간(span) = attest/admission-check 종료 → mint-publish 종료(잡 간 gap 포함) · n=5·런별 1표본(분포 추정 아님 — mean/sd 참고용만).
> **외부 문서**: GitHub 공식 문서 — jobs/steps API 스키마·시각 semantics, actions/cache/restore 동작, upload-artifact 동작. 출처는 §7에 기록.
> **판정**: BLOCKED — **입증된 낭비 0건(확정)**. BLOCKED는 작업 실패가 아니라 관측 범위 안에서 **확정된(determined) 운영 결과**다: 현재 관측 범위에서 검증 신뢰성을 보존하면서 제거할 수 있다고 증명된 비용이 없다. 불필요한 검증을 제거하지 않았고, CAS ledger append도 보존했다. 근거·레버별 접촉 지점 = §6.

---

## §1 배경과 질의

선행 보고서(node24 merge_group 잡 분해, 2026-11-02 착지)가 남긴 후속 질의: mint tail = `mint-prepare` 50/45 s + `mint-publish` 48/43 s, 크리티컬 패스 직렬 88~98 s(런 wall의 13.6~19.1%) — **"ADR-0022 §D5-3 인증서 파이프라인, 내부 비용 미분해"**. 본 조사의 질의: (a) mint tail이 실제로 무엇을 하는가(workflow 정의로 확인), (b) 그 구간의 내부 비용을 step 단위로 귀속(측정), (c) 검증 결과를 바꾸지 않고 제거 가능한 "입증된 낭비"가 있는가(판정 — 없으면 "입증된 낭비 0건"으로 **BLOCKED 확정 종결**; BLOCKED는 작업 실패가 아니라 관측 범위의 확정 결과다 — §6).

정의 판독 결과 선요약(§3 근거): mint tail = **인증서 발급 파이프라인**이다 — `mint-prepare` = read tier(witness 검증·정규화·subject-certificate 생성), `mint-publish` = write tier(독립 바인딩 검증 + CAS ledger append 4종 — git-ref exactly-once fail-closed). `verdict` 잡은 `needs: [mint-prepare, closure-deriver, anchor-resolve]`로 **mint-publish와 병렬**이 정의된 구조다.

## §2 표본 — 선언된 선택 규칙·열거

**표본 선언(먼저)**: 본 조사의 표본 5런(816·818·821·823·824)은 **post-window 진단 표본**이다. Stage 4 동결 관측창(선행 문서 `[2026-11-02T08:12:08.926Z, 09:13:00Z]`, 공식 모집단 **n=2 — 이미 폐쇄**)과 **명확히 구분**한다. 본 표본은 동결창 모집단의 연장·재집계가 아니라 본 문서 §2가 스스로 선언한 규칙에 따른 별개 진단 표본이며, **동결창 데이터를 사후 편입하지 않았다** — 동결창 공식 수치를 본 분해에 합산·재계산·수정하지 않는다(합산 n=7 주장 없음). 816·818은 창 시각 안에 있지만 본 문서에서 그 지위는 동결창 공식 모집단이 아니라 폐쇄된 창 이후의 진단 재사용이고, 선행 기록 값(런 wall 등) 인용은 계보 대조(§8-2 sha256 일치)일 뿐 모집단 편입이 아니다.

**표본 선택 규칙(선언)**: **Node 24 세대 착지(2026-11-02T08:12:08.926Z — 양 org ruleset 재핀 readback 중 늦은 쪽, 선행 문서 §2와 동일 하한) 이후, 관측 상한(2026-11-02T10:34:14Z, 열거 실행 시각)까지 관측 가능한 admission-gate(`admission-gate-v2.yml`) merge_group 런 전수**. 체리피킹 없음, 제외 0건.

**열거 명령·결과**: `gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=%3E%3D2026-11-02T08:12:09Z&per_page=100"` → merge_group 전체 `total_count=40`(5 배치 × 8 워크플로 — 08:39·08:54·09:24·09:33·09:39 배치. 선행 문서의 "창 내 16건 = 2 배치"와 정합), 그중 `path=admission-gate-v2` 5건. 전부 `conclusion=success`·`run_attempt=1`·진행 중·큐잉 런 없음.

**검증된 런→head 매핑(run 객체 단일 GET — `head_sha`·`created_at`; §8-3b로 재현)**:

| merge_group run | run id | 시작(UTC) | head |
|---|---|---|---|
| #816 | 41414648142 | 2026-11-02T08:39:20Z | 9381cb3a5 |
| #818 | 41416443711 | 2026-11-02T08:54:19Z | 4c19fa9b6 |
| #821 | 41420386024 | 2026-11-02T09:24:30Z | 0ebe84493 |
| #823 | 41421620938 | 2026-11-02T09:33:20Z | 8d6dbf6b8 |
| #824 | 41422458822 | 2026-11-02T09:39:30Z | a241012ed |

- **#823 비고**: head_branch는 `gh-readonly-queue/main/pr-1218-0ebe84493…` — sha 성분은 **직전 엔트리 #821의 머지 결과(체인 베이스)**다.
- **head_branch sha 성분 ≠ 런 head(5런 전수 확인)**: merge queue 런의 `head_branch` sha 성분은 큐 체인에서 **직전 엔트리의 머지 결과(체인 베이스)**를 넣는다 — 818의 브랜치 sha = #816 머지 결과 9381cb3a5, 821 = #818의 4c19fa9b6, 823 = #821의 0ebe84493, 824 = #823의 8d6dbf6b8(816 = 8c46c4ea…, 당 배치 이전 베이스). 런의 실제 head는 run 객체 `head_sha`다(위 표). 이에 따라 "배치 head = head_branch sha 성분" 해석은 폐기하며, head_branch 문자열 자체는 API 관측 사실로 §8-3b에서 재확인 가능하다.

**표본 부속 관측값(n=5 — 런 wall·jobs 원시 지문)**:

| run# | run id | PR(큐 브랜치) | 런 wall | jobs 원시(bytes) | jobs sha256(접두) |
|---|---|---|---|---|---|
| 816 | 41414648142 | #1214 | 512 s(선행 문서) | 63,142 | `869b5ad2…`(선행 기록 대조 일치) |
| 818 | 41416443711 | #1215 | 647 s(선행 문서) | 65,808 | `bdb73823…`(선행 기록 대조 일치) |
| 821 | 41420386024 | #1217 | 708 s(단일 GET) | 65,808 | `d103dda7…` |
| 823 | 41421620938 | #1218 | 528 s(단일 GET) | 63,142 | `00362a4c…` |
| 824 | 41422458822 | #1216 | 731 s(단일 GET) | 65,808 | `0c4f5c48…` |

- **코호트 표지(비권위 참고)**: jobs 원시 바이트 길이가 823=816(63,142)·821/824=818(65,808)과 각각 일치한다. 이것은 잡 구성(레인 실행/재사용 분기 등)이 동일함을 시사하는 표지일 뿐이며, 판정 basis(REUSED/EXECUTED)의 권위는 레인 판정 아티팩트다 — 본 조사는 mint tail 분해에 코호트 귀속이 불필요하므로 basis 판독을 수행하지 않았다(§4에서 step 구조가 5런 전부 동일 골격임을 직접 확인 — 코호트 무관 구조).
- **jobs `filter=latest` 명시** — 재실행 이전 시도 조용히 제외 방지(선행 문서 §7-3 규약). 5런 전부 attempt=1이라 차이 없음.

## §3 mint tail 구조 식별 — workflow 정의가 말하는 것

**한 줄 요약(정의 판독 — §1 선요약의 근거)**: mint tail = 인증서 발급 파이프라인 — `mint-prepare` = read tier(witness 검증·정규화·subject-certificate 생성) → `mint-publish` = write tier(독립 바인딩 검증 + CAS ledger append 4종 — git ref exactly-once fail-closed). `verdict` = mint-publish와 병렬(`needs: [mint-prepare, closure-deriver, anchor-resolve]`).

**래퍼 DAG**(`Archright/.github` admission-gate-v2.yml@main, blob `0ef1a441`, 713행):

- `mint-prepare`(:464) — `uses: Archright/Axiom/.github/workflows/certificate-mint.yml@498c55704552291da926fae6eb34bc5c0c04ec1b`, `with: stage: prepare`, **`needs: [attest, anchor-resolve]`** — `attest`(= admission-check.yml stage:attest)가 업로드한 witness·base-artifacts 아티팩트를 run-scoped REST API로 소비하기 위한 데이터 인과 간선(주석 :453-470 "no poll/retry… dropping the edge would race the producers and fail-closed nondeterministically"). permissions `contents: write + actions: read + pull-requests: read`. `if: !cancelled()`(attest 실패 때도 증명 권위로서 실행 — NO_CERT 기아 방지).
- `mint-publish`(:539) — 동일 callee, `stage: publish`, **`needs: [mint-prepare, gateway, anchor-resolve]`** — 같은 run의 `subject-certificate-<run_attempt>` 아티팩트 소비(SL-12→SL-04 데이터 인과) + gateway lane 종결 후 평가 선언(주석 :507-531 — 간선 부재가 실측 레이스 사고(run 37569755722, MINT_PUB_JOBS fail-closed)의 원인이었음 — 간선은 의존관계 선언이지 타이밍 회피가 아님).
- `verdict`(:658) — **`needs: [mint-prepare, closure-deriver, anchor-resolve]` — mint-publish를 needs하지 않는다**. 주석 :644-647 "mint-publish는 원장 append(P7)만 수행하므로 verdict에 줄 입력이 없다(publish→verdict는 스케줄링 산물)". 따라서 **verdict ∥ mint-publish 병렬**이 정의된 구조다. publish 성공 요구는 최종 aggregate `admission-check`(7-fold needs :673)가 직접 보유.
- 실측 정합: 5런 전부 `attest/admission-check 종료 → gap 3~6 s → mint-prepare → gap 3~13 s → mint-publish 기동`이며 verdict는 mint-prepare 종료 후 3~5 s 뒤 병렬 기동(821·823·824에서 verdict가 mint-publish보다 먼저 기동 — needs 정의와 정확히 일치).

**callee 본문**(`Archright/Axiom/.github/workflows/certificate-mint.yml@498c5570`, blob `6e6e5b03`, 2,672행) — mint tail이 실제로 하는 일:

- **prepare leg(read tier — job `prepare`, :183, `if: inputs.stage == 'prepare'`)**: ① 실행 venue 해석·활성화 가드(workflow_call 재검증) ② B/H 도출(run API + PR API — M 체크아웃 없음) ③ B 트리 checkout(trusted config/tree, fetch-depth 1) ④ epoch manifest scope 게이트(`scope_sl12`) ⑤ **`[mint] Consume admission B-built bin/ax`** — attest stage의 build-base-artifacts 아티팩트 수송(build_sha==B + sha256 pin) ⑥ TrustedWriterSet@B·PR identity·provenance 대조 ⑦ witness 아티팩트 수송·병합 트리 identity·**witness 검증·정규화(B-built ax — `signWitness(witness)`의 유일 입력)** ⑧ **subject-certificate 생성(digest+manifest)·아티팩트 업로드**(`actions/upload-artifact@cf430e03` v7.0.2, trusted-name). = **인증서 발급(mint)의 서명·발행 절반**.
- **publish leg(write tier — job `publish`, :1240, `if: inputs.stage == 'publish'`)**: ① B checkout(로컬 액션 해석 + B-pinned 정합용 — H 체크아웃·빌드 없음) ② scope 게이트(`scope_sl04`·`scope_sl0713`·`scope_sl15`) ③ **(P1)~(P4) [X]1~3 인증서 유효성 바인딩 검증** — 아티팩트 identity(run-scoped + artifact-id download)·파일 digest(cert_sha256 대조 + build_sha==B)·필드 바인딩(subjectId/baseSha/headSha/certTree/evidenceDigest == 재유도값) ④ (P5)/(P6) [B2] 데이터 인과 — canonical tree identity(testedTreeDigest == tree(github.sha) == cert.certTree)·gateway lane 결론+시간 인과(jobs API) ⑤ **(P7) D6 + FF-CAS 3분기 reconciliation — cert ledger append(exactly-once)** ⑥ **(P7b)/(P7c)/(P7c-x) SL-15 evidence/judgment/extension(×3) CAS ledger append(exactly-once)** — `bin/ax cert|evidence ledger-append`가 git ref(예: `refs/heads/axiom/evidence-cas`)에 GITHUB_TOKEN으로 기록; 선-list·선-verify·append·경합 시 재조회 reconciliation, 손상·불일치 = fail-closed. = **발행된 인증서의 독립 검증·원장 기록 절반**.
- **setup-axiom-toolchain 호출 양상**: 양 레그 모두 `cache-save-enabled: 'false'`·`provision-scope: 'runtime'`·`cache-build-source: B`(:602-607, :1300-1305) — **restore-only reader**("cache = acceleration, never evidence"; B-built ax의 libpcre3 dlopen 요구 대응 — 695108a27 선례 주석). 캐시 저장 설계상 없음(아래 관찰 참고).
- **관찰(정의 정적 판독 — 비용 효과 측정 없음)**: composite action.yml(:329-332 A-layer restore, :395-398 B-layer restore, :959 A-layer save)에서 A-layer save의 `if:`는 `inputs.keygen-only != 'true' && steps.a-restore.outputs.cache-hit != 'true' && (lock-complete || inputs.provision-scope == 'runtime')`로 **`cache-save-enabled` 입력을 조건에서 참조하지 않는다**(입력 선언 :99, 본문 참조 0건 — 전파 grep으로 확인). 즉 mint의 `cache-save-enabled: 'false'`는 A-layer save 게이트에 결속돼 있지 않다. 다만 save는 `continue-on-error`·first-save-wins·"acceleration never evidence" 계약 하에 있고, 본 관측 채널(jobs API steps[])로는 composite 내부에서 save가 발화했는지조차 관측 불가라 **런타임 효과는 UNKNOWN**이다(§4 관측 한계, §6.1 비판정 기록).

## §4 스텝별 분해 — 측정 사실 | 원인 판정 2칸 분리

**원칙(문서 전체 적용)**: 스텝·잡·gap의 **wall 시간은 측정 사실**이다. 그 시간의 **소비처**(검증·다운로드·캐시 복원·플랫폼 동작)는 증거가 있을 때만 **원인 판정**하며, 증거가 없으면 **UNKNOWN**으로 기록한다 — 측정값으로 원인을 추정해 채우지 않는다. 이하 모든 절이 이 2칸 분리([측정 사실] | [원인 판정])를 유지하고, UNKNOWN 항목은 §9에 집계된다.

**분류 축(선행 문서 등록 축 준용 + 문서화 확장)**:

- `verif-path` = 필수 검증·판정 경로·식별(venue 해석, 활성화 가드, B/H 도출, identity/provenance 대조, witness 검증, [X]1~3 바인딩, [B2] tree identity·lane 결론)
- **`verif-ledger`(본 조사 신설·문서화 확장)** = 필수 증명·원장 기록(D6 cert ledger append, SL-15 evidence/judgment CAS append — exactly-once fail-closed 쓰기)
- `env-cache` = 환경·캐시(setup-axiom-toolchain — restore-only composite, 내부 복원/검증 분리는 관측 불가)
- `env-workspace` = 환경·작업공간(Checkout B, [slice-engine] Load epoch manifest — 선행 문서 등록 매핑 유지)
- `env-platform` = Set up job / Complete job / Post(플랫폼 부가 스텝 — 공식 문서로 부가 스텝임 확인, §7)
- `transport` = 아티팩트 수송(Consume B-built bin/ax, (3) Artifact retrieval, (5)/(5b) upload, (P1) artifact-id download, (P3) Bin/ax 준비 — 이름에 Download/Upload가 없는 수송형 스텝의 확장 포함, 명시)
- `verif-exec` = 0 s(mint 잡에는 GO tests·evidenceId 배터리가 없다) · `경합`·`불필요한 반복`·`UNKNOWN` = §4.3/§4.4/§6에서 증거와 함께 명시.

### §4.1 prepare leg — 잡·스텝 wall(s, 5런)

**[측정 사실]** 잡 wall 50/45/53/35/46 s(816/818/821/823/824 순, 이하 동일). 주요 스텝:

| 스텝 | 816 | 818 | 821 | 823 | 824 | 분류 |
|---|---|---|---|---|---|---|
| Run ./.github/actions/setup-axiom-toolchain | 13 | 24 | 22 | 13 | 17 | env-cache |
| [mint] Consume admission B-built bin/ax | 4 | 4 | 4 | 4 | 3 | transport |
| Checkout B only | 3 | 5 | 6 | 5 | 4 | env-workspace |
| (5b) Upload subject-certificate artifact | 3 | 3 | 3 | 2 | 2 | transport |
| (0) Activation guard / (1) Derive B/H / (2a-c) / (3) / (3b) / (4) / (5) / venue / manifest | 각 ≤1 | 각 ≤1 | 각 ≤1 | 각 ≤1 | 각 ≤1 | verif-path·transport |
| steps_sum | 27 | 41 | 39 | 31 | 30 | — |

**[원인 판정]** setup 13~24 s = restore-only composite(libpcre3 정합용 런타임 스코프) — 내부에서 A-layer 캐시 HIT/MISS·도구 검증이 차지하는 비중은 로그 접근 차단으로 **UNKNOWN**(선행 문서가 이미 같은 영역을 A-restore BLOCKED 선례(#1192)로 종결). 수송 2종(7~8 s) = fail-closed provenance pin(build_sha==B·sha256)이 결합된 필수 수송. 검증 스텝 전체가 개별 ≤1 s — prepare leg의 검증 자체는 비용이 아니다. 잡 wall 대비 미커버리(아래 §4.3 gap)가 벽의 유의한 몫.

### §4.2 publish leg — 잡·스텝 wall(s, 5런)

**[측정 사실]** 잡 wall 48/43/48/35/53 s. 주요 스텝:

| 스텝 | 816 | 818 | 821 | 823 | 824 | 분류 |
|---|---|---|---|---|---|---|
| (P7c-x) extension judgment records append ×3 | 6 | 11 | 11 | 5 | 10 | verif-ledger |
| (P7b) evidence record append | 6 | 4 | 4 | 4 | 4 | verif-ledger |
| (P7) D6 cert ledger append | 5 | 4 | 4 | 4 | 3 | verif-ledger |
| (P7c) judgment record append | 3 | 5 | 4 | 1 | 4 | verif-ledger |
| Run ./.github/actions/setup-axiom-toolchain | 9 | 9 | 13 | 9 | 9 | env-cache |
| Checkout B only | 3 | 3 | 3 | 4 | 4 | env-workspace |
| (P1) artifact identity download | 2 | 0 | 2 | 1 | 1 | transport |
| (P2)(P3)(P4)(P5)(P6)(P0) | 각 ≤2 | 각 ≤1 | 각 ≤1 | 각 ≤2 | 각 ≤1 | verif-path |
| steps_sum | 39 | 42 | 46 | 33 | 39 | — |

**[원인 판정]** **verif-ledger 4스텝 합계 15~24 s가 publish leg의 최대 성분** — D6/SL-15 exactly-once CAS append로, 각 스텝은 선-list·선-verify·append(+경합 시 reconciliation)의 git ref API 왕복을 수행한다(certificate-mint.yml :2145-2190, :2222-, :2383-, :2530-). P7c-x는 확장 판정 레코드 3건을 **직렬** append한다(×3 표기 — 818·821에서 11 s). 이것은 검증 결과를 바꾸지 않고 제거 가능한 낭비가 아니라 **증명 기록 그 자체**(fail-closed 원장 쓰기)다. 직렬화의 사유도 정의에 있다: FF-CAS exactly-once는 git ref 선형성 전제 — 병렬 append는 ref 경합 레이스를 만든다(설계 판정이지 측정이 아님 — 본 관측 채널로는 내부 API 왕복 수 관측 불가). setup 9~13 s = §4.1과 동일 UNKNOWN 내부. 수송(P1) ≤2 s.

### §4.3 gap 분해 — 플랫폼 스케줄링·미커버리

**[측정 사실]** 10잔의 head gap(잡 started→첫 스텝)·tail gap(말단 스텝 종료→잡 completed)·잡 간 gap:

| 런 | prepare head | prepare tail | publish head | publish tail | 잡 내 gap 합 | gap1(attest→prepare) | gap2(prepare→publish) | gap3(publish→최종) |
|---|---|---|---|---|---|---|---|---|
| 816 | 11 | 12 | 1 | 8 | 32 | 5 | 3 | 3 |
| 818 | 1 | 3 | 1 | 0 | 5 | 3 | 3 | 4 |
| 821 | 11 | 3 | 1 | 1 | 16 | 3 | 13 | 3 |
| 823 | 1 | 3 | 1 | 1 | 6 | 4 | 4 | 12 |
| 824 | 11 | 5 | 12 | 2 | 30 | 6 | 3 | 3 |

- **head gap 11 s가 prepare에서 3런(816·821·824) 반복**, 824 publish에서도 12 s. 잡마다 상이한 ephemeral runner 배정 관측(예: 816 = 1000038708/1000038709, 824 = 1000038896/1000038897 — 전부 `runner_group_id=0` GitHub-hosted).
- **tail gap**: 816 prepare **12 s**·publish **8 s** — "Complete job" 스텝 종료 후 잡 completed_at까지의 시간. 다른 런은 0~5 s.

**[원인 판정]** head gap = **러너 부트/배정 지연**(플랫폼 동작 — 선행 문서 §4.4와 동일 귀속; 특정 잡에 고정되지 않음 — 818·823은 1 s로 뒤집힘)이지 검증·경합 아니다. 잡 간 gap = needs 종결 후 다음 잡의 러너 배정(플랫폼). tail gap(816의 12+8 s)의 원인은 **UNKNOWN** — 로그·체크런 세부에 접근할 수 없어 잡 teardown/로그 수송 지연 등 대안 설명을 배제할 증거가 없다(측정 사실은 확실: 스텝 타임스탬프 밖 존재). 경합: 동시 실행 구조가 없고(직렬 2잡) 자원 공유 신호(동일 runner_id·캐시 키·lock 오류) 없음 — **입증 0건**.

### §4.4 불필요한 반복 — 판정

- **prepare↔publish 간 인증서 아티팩트 왕복(업로드→다운로드)은 설계상 검증이다**: publish leg (P1)~(P4)는 prepare가 방금 업로드한 `subject-certificate`를 **저장소 경유로 재판독해 독립 바인딩 검증**([X]1~3)한다 — 단일 writer·다중 검증자 구조의 fail-closed 확인이며 우회 시 검증 의미론 변경(Out of Scope). 제거 후보 아님.
- **setup-axiom-toolchain의 2회 실행**(양 레그 각 9~24 s): 레그가 서로 다른 ephemeral runner(관측: 잡별 상이 runner_name)라 per-runner 프로비전이 필요한 구조 — CACHE ISOLATION 전제(선행 문서 §4.5와 동일). 동일 runner 재사용은 플랫폼·격리 설계 변경(계약 영역)이라 본 축에서 제거 후보 아님.
- **스텝 중복 0건 관측**: 5런 × 2잡에서 스텝 골격(17+19스텝, skipped preflight 레그 2종 포함) 동일 — 코호트 무관 구조. 미실행(skipped) 스텝 = venue 분기 설계(PR=preflight 전용 — MG에서는 '실행 안 됨'), 낭비 아님.

## §5 원인 분류 집계 — mint tail 직렬 구간 전체(5런, gap 포함)

**[측정 사실]** 직렬 구간(attest 종료→publish 종료, 잡 간 gap 포함)과 성분:

| 런 | 직렬 구간(s) | 런 wall(s) | 점유 | = steps(66·83·85·64·69) + 잡 내 gap + 잡 간 gap |
|---|---|---|---|---|
| 816 | **106** | 512 | 20.7% | 66 + 32 + 8 |
| 818 | **94** | 647 | 14.5% | 83 + 5 + 6 |
| 821 | **117** | 708 | 16.5% | 85 + 16 + 16 |
| 823 | **78** | 528 | 14.8% | 64 + 6 + 8 |
| 824 | **108** | 731 | 14.8% | 69 + 30 + 9 |
| **합** | **503** | — | — | 367 + 89 + 47 |

직렬 구간은 런 wall의 **14.5~20.7%**(78~117 s/런)다.

**[측정 사실 — 총량 등식]**: 5런 직렬 구간 총합 **503 s = 잡 wall 합 456 s + 잡 간 gap 합 47 s**다. 잡 wall 합 456 s는 그 안에 **잡 내 gap 89 s**를 포함한다(잡 wall 456 = steps 367 + 잡 내 gap 89 — 부록 A 전 잔 ±0 s 정합). 즉 367 + 89 + 47 = 503.

**분류 집계(5런 합계 503 s 기준)**:

| 분류 | 합(s) | 점유 | 구성 |
|---|---|---|---|
| env-cache(restore-only setup ×2/런) | 138 | 27.4% | 9~24 s/잡 — 내부 분리 UNKNOWN |
| **verif-ledger(CAS append ×4/런)** | 103 | 20.5% | 15~24 s/런 — P7 3~5·P7b 4~6·P7c 1~5·P7c-x 5~11 |
| 잡 내 gap(head+tail) | 89 | 17.7% | 러너 배정 + 816 tail 20 s(원인 UNKNOWN) |
| transport(artifact 왕복) | 43 | 8.5% | 6~10 s/런 |
| env-workspace(Checkout B ×2 + manifest) | 41 | 8.2% | 3~6 s/잡 |
| verif-path(가드·identity·바인딩·[B2]) | 30 | 6.0% | 전 스텝 ≤2 s |
| 잡 간 gap(2곳/런) | 47 | 9.3% | 3~13 s |
| env-platform(Set up/Complete/Post) | 12 | 2.4% | 0~2 s/잡 |

(교차검증: 분류 합 367 s = steps_sum 합 367 s 일치; 367+89+47 = 503 s 일치.)

**4그룹 요약(§6 판정의 등가 분할)**:

| 그룹 | 합(s) | 점유 | 구성 |
|---|---|---|---|
| env-cache(restore-only setup ×2/런) | 138 | 27.4% | 내부 분리 UNKNOWN(로그 차단) |
| **verif-ledger(CAS append ×4/런)** | 103 | 20.5% | exactly-once fail-closed 원장 쓰기 |
| gap(잡 내 89 + 잡 간 47) | 136 | 27.0% | 러너 배정·스케줄링 — 816 tail 20 s는 원인 UNKNOWN |
| 수송·워크스페이스·검증·플랫폼 | 126 | 25.1% | transport 43 + env-workspace 41 + verif-path 30 + env-platform 12 |

(교차검증: 138 + 103 + 136 + 126 = 503 s 일치.)

## §6 후보 레버 평가 — 판정

**문턱(선행 문서 §5 준용)**: 효과 크기 > 노이즈(provider 스윙 ~23 s 선례) · 계약 무손상 · 최소 diff · 부정 시험 가능 · n=5이나 코호트·런별 1표본이라 사후 Before/After 입증 불가 — 후보는 사전에 "입증된 낭비"여야 한다.

| 레버 | 기제(실측) | 검증·계약 접촉 | 판정 |
|---|---|---|---|
| verif-ledger(CAS append 4종) 병렬화·배치 | 103 s(20.5%) — P7c-x는 3건 직렬 append | exactly-once FF-CAS의 git ref 선형성 전제·D6/SL-15 증명 기록 자체 — 제거·재정렬은 판정 증거 순서 변경(Out of Scope; J1-J4급 계약 작업 전제) | **탈락(의미론 보호)** |
| setup-axiom-toolchain 단축 | 138 s(27.4%) — 내부 분리 UNKNOWN(로그 차단) | restore-only reader·libpcre3 필수 정합(제거 시 B-built ax dlopen 실패 위험 — 695108a27 선례) + A-restore BLOCKED 선례(#1192)와 동일 영역·동일 계약 | **탈락(선례 BLOCKED + 내부 UNKNOWN)** |
| prepare→publish 직렬 간선 제거 | 잡 간 gap+publish leg를 prepare와 병렬화하면 이론상 수십 s | publish는 prepare의 subject-certificate를 소비(데이터 인과) + gateway 결론 사후 평가 — 간선 부재는 실측 레이스 사고(run 37569755722)로 fail-closed 오검증 발생 이력 | **탈락(정합성 파괴 — 사고 재발)** |
| 인증서 아티팩트 왕복(P1~P4) 생략 | ≤2 s/런(P1만) — 이득 미미 | [X]1~3 독립 바인딩 검증 = publish leg의 존재 이유 | **탈락(의미론 보호·효과 미달)** |
| transport·verif-path·env-workspace 축소 | 합 114 s(22.7%)이나 런당 6~10 s 단위로 잘게 분산 | fail-closed provenance pin·trusted-name 결합 수송 | **탈락(효과 < 노이즈 ~23 s)** |
| 러너 배정·tail gap(head 11 s ×3런, 816 tail 20 s) | gap 136 s(27.0%) — 가장 큰 가변 영역으로 보임 | GitHub-hosted ephemeral 배정·잡 teardown — 워크플로 편집으로 제거 불가, tail gap 원인은 **UNKNOWN**(로그 접근 차단) | **대상 없음(플랫폼·UNKNOWN)** |
| `cache-save-enabled` 미참조 입력(정적 관찰) | 런타임 효과 측정 0(관측 채널 제약) | composite save 게이트가 입력을 참조하지 않는 것은 정적 사실이나, 발화 여부·효과 모두 UNKNOWN — 입증된 낭비 아님. 런타임 save는 자체 계약(continue-on-error·first-save-wins·acceleration never evidence) 하에 있음 | **후보 아님(증거 불충분 — 관찰로만 기록)** |

**판정: BLOCKED — 입증된 낭비 0건(확정 — determined outcome)**. 이 판정은 작업 실패로 기록하지 않고 **확정된 운영 결과로 기록한다**: **현재 관측 범위에서 검증 신뢰성을 보존하면서 제거할 수 있다고 증명된 비용이 없다.** **불필요한 검증을 제거하지 않았고, CAS ledger append도 보존했다.**

근거: mint tail 503 s(5런 합)은 ① 필수 증명·원장 기록(103 s — fail-closed exactly-once CAS append), ② 필수 검증 경로(30 s — [X]1~3·[B2]·가드·identity, 전부 ≤2 s 단위), ③ 문서화된 restore-only 환경(138 s — 내부 UNKNOWN, A-restore BLOCKED 선례 영역), ④ fail-closed 수송(43 s), ⑤ 플랫폼 스케줄링·미커버리(136 s — 워크플로 편집 불가 영역 + 원인 UNKNOWN 20 s)로 전부 귀속된다. 노이즈 문턱(~23 s)을 상회하는 제거 가능 성분은 관측되지 않았고, **모든 구조 레버(간선 제거 포함)는 검증 의미론에 접촉한다** — verdict와 mint-publish 사이 간선 구조(병렬 유지·간선 부여/제거 모두)는 검증 순서·정합성의 일부이며, 레이스 사고 run 37569755722와 직결된다(§3 래퍼 주석 :507-531 — mint-publish 쪽 간선 부재가 MINT_PUB_JOBS fail-closed 오검증 사고를 낳은 실측 이력; 각 레버의 접촉 지점은 위 표와 §3 정의 인용으로 명시). 이것은 실패가 아니라 결정 가능한 운영 결과다(선행 문서 §6-1 종결 조건 준용). 부수 관찰 2건은 §6.1에 비판정 기록으로 남긴다.

**노이즈 대비 참고(비판정)**: 823(528 s)은 5런 최단 mint 구간(78 s)을 보였다 — REUSED 추정 표지(원시 바이트 길이 = 816과 동일)와 방향이 일치하지만, basis 미판독이라 코호트 귀속 주장은 하지 않는다.

### §6.1 부수 관찰 2건(비판정 — 기록만)

org 표면(`Archright/.github` 래퍼·callee 워크플로) **무변경 원칙**에 따라 아래 2건은 **기록만** 하고, 어떤 조치(수정 PR·이슈·게이트·핀 변경)도 수행하지 않는다.

| # | 관찰 | 내용 | 판정 접촉 |
|---|---|---|---|
| ① | composite 워크플로의 `cache-save-enabled` 입력이 **save 게이트에서 미참조** | setup-axiom-toolchain action.yml의 A-layer save `if:`(:959 근방)는 `keygen-only`·`a-restore.cache-hit`·`lock-complete`/`provision-scope`만 검사하고 `cache-save-enabled` 입력(선언 :99, 본문 참조 0건 — 전파 grep)을 참조하지 않음(§3 관찰). mint가 `cache-save-enabled: 'false'`를 넘겨도 A-layer save 게이트에 결속돼 있지 않다 | **런타임 효과 UNKNOWN** — 본 관측 채널(jobs API steps[])로 composite 내부 save 발화 여부·효과 관측 불가(§9-②). 입증된 낭비 아님(§6 후보 표 "후보 아님") |
| ② | 래퍼 주석의 callee pin 불일치 표기 | 래퍼(admission-gate-v2.yml) 주석 기재 "@d117ae8e2, epoch N+7 현행" vs 실제 `uses:` pin `@498c5570`(§3) | **비용 영향 없음** — 동작 정의의 권위는 `uses:` pin이며 주석·pin의 표기 불일치는 문서 정합성 관찰. 기록만 |

두 관찰 모두 본 문서의 BLOCKED 확정 판정을 변경하지 않는다(①은 효과 UNKNOWN이라 입증된 낭비가 될 수 없고, ②는 비용 영향 0이다).

## §7 외부 공식 문서 확인(출처 명시)

| 확인 항목 | 출처 | 확인 내용 |
|---|---|---|
| jobs/steps API 스키마·시각 | docs.github.com "REST API endpoints for workflow jobs"(FetchURL 직접 인출, apiVersion 2022-11-28) | job 객체에 `started_at`/`completed_at`, `steps[]`에 `number·name·status·conclusion·started_at·completed_at` — 초(second) 그래니러러티 공식 스키마. 본 조사의 wall 산출 방식과 일치 |
| "Set up job"/"Complete job" | docs.github.com "Using workflow run logs"(Context7 `/websites/github_en_actions`) | GitHub가 잡마다 부가하는 스텝 — 관측된 env-platform 12 s가 워크플로 정의가 아닌 플랫폼 부가분임을 확인 |
| actions/cache/restore 동작 | Context7 `/actions/cache`(공식 README·autodocs) | restore-only 액션 — post step 없음·아무것도 저장 안 함; `cache-hit`은 exact key match만 true. mint composite이 restore-only 설계임과 정합 |
| upload-artifact 동작 | Context7 `/actions/upload-artifact` | 업로드 즉시 `artifact-id`·digest 출력, Artifacts REST API로 소비 — prepare(5b)→publish(P1)의 run-scoped 소비 패턴과 정합 |

## §8 검증 가능성(GET-only 재현 — 동일 입력 → 동일 결과)

```bash
# 0) 시각 기준점
date -u   # 관측 상한 = 2026-11-02T10:34:14Z (열거 실행 시각)

# 1) 표본 열거(전수 — Q16 준수: total_count 확인)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=%3E%3D2026-11-02T08:12:09Z&per_page=100" \
  --jq '"total_count=\(.total_count)", (.workflow_runs[] | select(.path | test("admission-gate-v2")) |
        [.id, .run_number, .created_at, .conclusion, (.run_attempt|tostring), (.head_branch | split("/")[-1][0:9])] | @tsv)'
# → total_count=40, admission-gate 5건: 816·818·821·823·824 (전부 success·attempt=1)

# 2) jobs 원시 수집(단일 GET — 권위; filter=latest 명시)
for id in 41414648142 41416443711 41420386024 41421620938 41422458822; do
  gh api "repos/Archright/Axiom/actions/runs/$id/jobs?filter=latest" > /tmp/admission_gate_${id}_jobs.json
done
sha256sum /tmp/admission_gate_*_jobs.json
# 869b5ad2…(816) bdb73823…(818) d103dda7…(821) 00362a4c…(823) 0c4f5c48…(824) — 816/818은 선행 문서 기록과 일치(계보 검증)

# 3a) 런 wall(단일 GET)
for id in 41420386024 41421620938 41422458822; do
  gh api "repos/Archright/Axiom/actions/runs/$id" \
    --jq '[.id,.run_number,.created_at,.run_started_at,.updated_at,.conclusion] | @tsv'
done

# 3b) 런→head 매핑(§2 표·"head_branch sha 성분 ≠ 런 head" 재현 — run 객체 단일 GET)
for id in 41414648142 41416443711 41420386024 41421620938 41422458822; do
  gh api "repos/Archright/Axiom/actions/runs/$id" \
    --jq '[.id,.run_number,.head_sha,.created_at,.head_branch] | @tsv'
done

# 4) mint 잡 스텝 원값(부록 A·부록 B의 원천)
jq -r '.jobs[] | select(.name | test("^mint-")) | select(.conclusion == "success") |
  .name + " (wall " + (((.completed_at|fromdateiso8601) - (.started_at|fromdateiso8601))|tostring) + "s)\n" +
  ([.steps[] | "| \(.number) | \(.name) | \(.conclusion) | " +
   (if .started_at and .completed_at
    then (((.completed_at|fromdateiso8601) - (.started_at|fromdateiso8601))|tostring) + "s"
    else "—" end)] | join("\n")) + "\n"' /tmp/admission_gate_<RUN_ID>_jobs.json

# 5) 잡 gap·steps_sum(head = 첫 스텝 시작까지, tail = 말단 스텝 종료 이후)
jq -r '.jobs[] | select(.name | test("^mint-")) | select(.conclusion == "success") |
  {job:.name, wall:((.completed_at|fromdateiso8601)-(.started_at|fromdateiso8601)),
   head_gap_s:((.steps[0].started_at|fromdateiso8601)-(.started_at|fromdateiso8601)),
   tail_gap_s:((.completed_at|fromdateiso8601) - ([.steps[] | select(.completed_at) | (.completed_at|fromdateiso8601)] | max)),
   steps_sum:([.steps[] | select(.started_at and .completed_at) |
     ((.completed_at|fromdateiso8601)-(.started_at|fromdateiso8601))] | add)}' /tmp/admission_gate_<RUN_ID>_jobs.json

# 6) 분류 집계(§4 분류 축 — /tmp/mint_classify.jq verbatim, §8말미)
jq -c -f /tmp/mint_classify.jq /tmp/admission_gate_<RUN_ID>_jobs.json

# 7) 직렬 구간·잡 간 gap(§5 — /tmp/tail_chain.jq verbatim, §8말미)
jq -r -f /tmp/tail_chain.jq /tmp/admission_gate_<RUN_ID>_jobs.json

# 8) workflow 정의(§3 근거 — GET만)
gh api "repos/Archright/.github/contents/.github/workflows/admission-gate-v2.yml?ref=main" --jq '.content' | base64 -d
#   blob 0ef1a441bf0a01568beebab196cafb01ce3c359e · 713행 — mint-prepare :464(needs [attest, anchor-resolve]),
#   mint-publish :539(needs [mint-prepare, gateway, anchor-resolve]), verdict :658(needs [mint-prepare, closure-deriver, anchor-resolve])
gh api "repos/Archright/Axiom/contents/.github/workflows/certificate-mint.yml?ref=498c55704552291da926fae6eb34bc5c0c04ec1b" --jq '.content' | base64 -d
#   blob 6e6e5b03a2749b8ff325cff96c5dbe1c7be02bd08f177e16b1622c8ac676de15 · 2,672행 — prepare :183·publish :1240,
#   P7 :2145 · P7b :2222 · P7c :2383 · P7c-x :2530, setup 호출 :602/:1300(cache-save-enabled 'false'·provision-scope 'runtime')
gh api "repos/Archright/Axiom/contents/.github/actions/setup-axiom-toolchain/action.yml?ref=498c55704552291da926fae6eb34bc5c0c04ec1b" --jq '.content' | base64 -d
#   962행 — A-layer restore :329·B-layer restore :395·A-layer save :959(save if:에 cache-save-enabled 미참조 — §3 관찰)
```

**/tmp/mint_classify.jq (verbatim)**:

```jq
def cls:
  if (.name | test("Set up job|Complete job|^Post ")) then "env-platform"
  elif (.name | test("setup-axiom-toolchain")) then "env-cache"
  elif (.name | test("Load epoch manifest")) then "env-workspace"
  elif (.name | test("Checkout B only")) then "env-workspace"
  elif (.name | test("Upload subject-certificate|Cert artifact digest \\+ manifest \\+ upload|Artifact retrieval|artifact-id download|Consume admission B-built|Bin/ax 준비")) then "transport"
  elif (.name | test("\\(P7\\)|\\(P7b\\)|\\(P7c\\)|ledger append")) then "verif-ledger"
  else "verif-path"
  end;
.jobs[]
| select(.name | test("^mint-"))
| select(.conclusion == "success")
| {
    run: input_filename,
    job: .name,
    wall: ((.completed_at|fromdateiso8601) - (.started_at|fromdateiso8601)),
    runner: .runner_name,
    grp: .runner_group_id,
    steps_sum: ([.steps[] | select(.started_at and .completed_at) | ((.completed_at|fromdateiso8601) - (.started_at|fromdateiso8601))] | add),
    by_class: ([.steps[] | select(.started_at and .completed_at) | {c: cls, w: ((.completed_at|fromdateiso8601) - (.started_at|fromdateiso8601))}] | group_by(.c) | map({(.[0].c): (map(.w)|add)}) | add),
    n_skipped: ([.steps[] | select(.conclusion=="skipped")] | length)
  }
```

**/tmp/tail_chain.jq (verbatim)**:

```jq
[.jobs[] | {j: .name, s: (.started_at|fromdateiso8601), e: (.completed_at|fromdateiso8601)}]
| {
    attest_end: ([.[] | select(.j | test("attest / admission-check$"))][0].e),
    prep: ([.[] | select(.j == "mint-prepare / prepare")][0]),
    pub: ([.[] | select(.j == "mint-publish / publish")][0]),
    final: ([.[] | select(.j == "admission-check")][0])
  }
| "\nprepare_wall=\(.prep.e - .prep.s)s gap1=\(.prep.s - .attest_end)s publish_wall=\(.pub.e - .pub.s)s gap2=\(.pub.s - .prep.e)s | mint_span(attest_end→publish_end)=\(.pub.e - .attest_end)s gap3(final start)=\(.final.s - .pub.e)s"
```

## §9 관측 한계(문서화 의무 — 선행 문서 §부록 관측 한계 준용)

① ±1 s 그래니러러티(API 초 단위) ② composite(setup-axiom-toolchain) 내부 캐시 HIT/MISS·검증 분리 — jobs API steps[]로 관측 불가, **UNKNOWN** ③ 잡 tail gap(816 prepare 12 s·publish 8 s 등)의 원인 — 스텝 타임스탬프 밖 존재, 대안 설명 배제 불가, **UNKNOWN** ④ skipped 레그(mint-prepare/publish·mint-publish/prepare)의 타임스탬프 역전 quirk(완료 < 시작) — '실행 안 됨' 처리, 해석 금지 ⑤ CAS append 스텝 내부의 API 왕복 수·ref 경합 여부 — 로그 접근 차단, **UNKNOWN**(직렬화 사유는 정의 판독에 근거) ⑥ 신규 3런(821/823/824)의 레인 판정 basis(REUSED/EXECUTED) 미판독 — mint 분해에 불필요했으므로 수행하지 않음; 코호트 귀속은 표지(바이트 길이 일치) 수준을 넘지 않는다 ⑦ run wall은 updated_at−created_at 단일 GET 기준(816·818은 선행 문서 값 인용).

## 부록 A — mint 잡 단위 원값(10잔 전수)

| 런 | 잡 | wall | head gap | tail gap | steps_sum | runner | grp |
|---|---|---|---|---|---|---|---|
| 816 | mint-prepare / prepare | 50 | 11 | 12 | 27 | 1000038708 | 0 |
| 816 | mint-publish / publish | 48 | 1 | 8 | 39 | 1000038709 | 0 |
| 818 | mint-prepare / prepare | 45 | 1 | 3 | 41 | 1000038745 | 0 |
| 818 | mint-publish / publish | 43 | 1 | 0 | 42 | 1000038746 | 0 |
| 821 | mint-prepare / prepare | 53 | 11 | 3 | 39 | 1000038848 | 0 |
| 821 | mint-publish / publish | 48 | 1 | 1 | 46 | 1000038851 | 0 |
| 823 | mint-prepare / prepare | 35 | 1 | 3 | 31 | 1000038880 | 0 |
| 823 | mint-publish / publish | 35 | 1 | 1 | 33 | 1000038885 | 0 |
| 824 | mint-prepare / prepare | 46 | 11 | 5 | 30 | 1000038896 | 0 |
| 824 | mint-publish / publish | 53 | 12 | 2 | 39 | 1000038897 | 0 |

(job wall = head gap + steps_sum + tail gap, 전 잔 ±0 s 정합. skipped 레그: 각 런의 `mint-prepare / publish`·`mint-publish / prepare` — 스테이지 매트릭스 반대편, '실행 안 됨'.)

### 잡별 분류 집계(s — /tmp/mint_classify.jq 출력)

| 런 | 잡 | wall | steps_sum | verif-path | verif-ledger | env-cache | env-workspace | transport | env-platform | skipped |
|---|---|---|---|---|---|---|---|---|---|---|
| 816 | prepare | 50 | 27 | 2 | 0 | 13 | 3 | 8 | 1 | 1 |
| 816 | publish | 48 | 39 | 4 | 20 | 9 | 3 | 2 | 1 | 1 |
| 818 | prepare | 45 | 41 | 3 | 0 | 24 | 5 | 8 | 1 | 1 |
| 818 | publish | 43 | 42 | 3 | 24 | 9 | 3 | 1 | 2 | 1 |
| 821 | prepare | 53 | 39 | 2 | 0 | 22 | 6 | 8 | 1 | 1 |
| 821 | publish | 48 | 46 | 3 | 23 | 13 | 3 | 2 | 2 | 1 |
| 823 | prepare | 35 | 31 | 4 | 0 | 13 | 5 | 7 | 2 | 1 |
| 823 | publish | 35 | 33 | 3 | 15 | 9 | 4 | 1 | 1 | 1 |
| 824 | prepare | 46 | 30 | 3 | 0 | 17 | 4 | 5 | 1 | 1 |
| 824 | publish | 53 | 39 | 3 | 21 | 9 | 5 | 1 | 0 | 1 |

## 부록 B — 스텝 단위 전수 장부(원문 타임스탬프는 §8-4로 재현)

### Run 816(41414648142)

#### mint-prepare / prepare (wall 50s)

| # | step | 결론 | wall |
|---|---|---|---|
| 1 | Set up job | success | 1s |
| 2 | [venue] Resolve execution venue (PR=preflight / MG+call=landing) | success | 0s |
| 3 | (0) Activation guard — API re-verify (workflow_call) | success | 0s |
| 4 | (1) Derive B/H via run API + PR API (no M — pre-landing mint) | success | 1s |
| 5 | Checkout B only (trusted config/tree; no M/H checkout) | success | 3s |
| 6 | [slice-engine] Load epoch manifest implementedSlices (B tree — scope authority) | success | 0s |
| 7 | Run ./.github/actions/setup-axiom-toolchain | success | 13s |
| 8 | [preflight] Prepare-leg static contrast (policy SSOT + mint structure) | skipped | 0s |
| 9 | [mint] Consume admission B-built bin/ax (build-base-artifacts — run-scoped + build_sha==B + sha256 pin) | success | 4s |
| 10 | (2a)+ (2b)+ (2c) TrustedWriterSet@B + PR API identity + provenance comparison | success | 1s |
| 11 | (3) Artifact retrieval — run-scoped API + trusted-name + witness sha + provenance check | success | 1s |
| 12 | (3b) Merge-candidate tree identity — witness.mergeTreeDigest == tree(mergeSha) (fail-closed) | success | 0s |
| 13 | (4) Verify + normalize witness (B-built trusted ax) | success | 0s |
| 14 | (5) Cert artifact digest + manifest + upload (subject-certificate-<run_attempt>) | success | 0s |
| 15 | (5b) Upload subject-certificate artifact (trusted-name) | success | 3s |
| 30 | Post Checkout B only (trusted config/tree; no M/H checkout) | success | 0s |
| 31 | Complete job | success | 0s |

#### mint-publish / publish (wall 48s)

| # | step | 결론 | wall |
|---|---|---|---|
| 1 | Set up job | success | 1s |
| 2 | [venue] Resolve execution venue (PR=preflight / MG+call=landing) | success | 0s |
| 3 | Checkout B only (trusted config/tree; no M/H checkout) | success | 3s |
| 4 | Run ./.github/actions/setup-axiom-toolchain | success | 9s |
| 5 | [slice-engine] Load epoch manifest implementedSlices (contents API @B — scope authority) | success | 0s |
| 6 | (P0) Publish activation guard — self-binding + gate-run identity + PR identity + (a) | success | 0s |
| 7 | [preflight] Publish-leg structural contrast (single-writer posture + stage structure) | skipped | 0s |
| 8 | (P1) [X]1 artifact identity — run-scoped + trusted-name + artifact-id download | success | 2s |
| 9 | (P2) [X]2 file digest — cert_sha256 manifest 대조 + build_sha == B (provenance) | success | 0s |
| 10 | (P3) Bin/ax 준비 — artifact의 B-built bin/ax (build_sha==B, sha256 pin) | success | 0s |
| 11 | (P4) [X]3 field binding — subjectId/baseSha/headSha/certTree/evidenceDigest == 재유도값 + (a) headSha | success | 2s |
| 12 | (P5) [B2] (b) canonical tree identity — testedTreeDigest == tree(github.sha) == cert.certTree | success | 1s |
| 13 | (P6) [B2] (c) gateway lane conclusion == success + 시간 인과 (jobs API) | success | 1s |
| 14 | (P7) D6 + FF-CAS 3분기 reconciliation + exactly-once (ledger append) | success | 5s |
| 15 | (P7b) [SL-15] evidence record → evidence CAS ledger append (exactly-once) | success | 6s |
| 16 | (P7c) [SL-15] judgment record → judgment CAS ledger append (exactly-once) | success | 3s |
| 17 | (P7c-x) [SL-15] extension judgment records → judgment CAS ledger append (exactly-once ×3) | success | 6s |
| 34 | Post Checkout B only (trusted config/tree; no M/H checkout) | success | 0s |
| 35 | Complete job | success | 0s |

### Run 818(41416443711)

#### mint-prepare / prepare (wall 45s)

| # | step | 결론 | wall |
|---|---|---|---|
| 1 | Set up job | success | 1s |
| 2 | [venue] Resolve execution venue (PR=preflight / MG+call=landing) | success | 0s |
| 3 | (0) Activation guard — API re-verify (workflow_call) | success | 1s |
| 4 | (1) Derive B/H via run API + PR API (no M — pre-landing mint) | success | 1s |
| 5 | Checkout B only (trusted config/tree; no M/H checkout) | success | 5s |
| 6 | [slice-engine] Load epoch manifest implementedSlices (B tree — scope authority) | success | 0s |
| 7 | Run ./.github/actions/setup-axiom-toolchain | success | 24s |
| 8 | [preflight] Prepare-leg static contrast (policy SSOT + mint structure) | skipped | 0s |
| 9 | [mint] Consume admission B-built bin/ax (build-base-artifacts — run-scoped + build_sha==B + sha256 pin) | success | 4s |
| 10 | (2a)+ (2b)+ (2c) TrustedWriterSet@B + PR API identity + provenance comparison | success | 1s |
| 11 | (3) Artifact retrieval — run-scoped API + trusted-name + witness sha + provenance check | success | 1s |
| 12 | (3b) Merge-candidate tree identity — witness.mergeTreeDigest == tree(mergeSha) (fail-closed) | success | 0s |
| 13 | (4) Verify + normalize witness (B-built trusted ax) | success | 0s |
| 14 | (5) Cert artifact digest + manifest + upload (subject-certificate-<run_attempt>) | success | 0s |
| 15 | (5b) Upload subject-certificate artifact (trusted-name) | success | 3s |
| 30 | Post Checkout B only (trusted config/tree; no M/H checkout) | success | 0s |
| 31 | Complete job | success | 0s |

#### mint-publish / publish (wall 43s)

| # | step | 결론 | wall |
|---|---|---|---|
| 1 | Set up job | success | 1s |
| 2 | [venue] Resolve execution venue (PR=preflight / MG+call=landing) | success | 0s |
| 3 | Checkout B only (trusted config/tree; no M/H checkout) | success | 3s |
| 4 | Run ./.github/actions/setup-axiom-toolchain | success | 9s |
| 5 | [slice-engine] Load epoch manifest implementedSlices (contents API @B — scope authority) | success | 0s |
| 6 | (P0) Publish activation guard — self-binding + gate-run identity + PR identity + (a) | success | 1s |
| 7 | [preflight] Publish-leg structural contrast (single-writer posture + stage structure) | skipped | 0s |
| 8 | (P1) [X]1 artifact identity — run-scoped + trusted-name + artifact-id download | success | 0s |
| 9 | (P2) [X]2 file digest — cert_sha256 manifest 대조 + build_sha == B (provenance) | success | 0s |
| 10 | (P3) Bin/ax 준비 — artifact의 B-built bin/ax (build_sha==B, sha256 pin) | success | 1s |
| 11 | (P4) [X]3 field binding — subjectId/baseSha/headSha/certTree/evidenceDigest == 재유도값 + (a) headSha | success | 1s |
| 12 | (P5) [B2] (b) canonical tree identity — testedTreeDigest == tree(github.sha) == cert.certTree | success | 1s |
| 13 | (P6) [B2] (c) gateway lane conclusion == success + 시간 인과 (jobs API) | success | 0s |
| 14 | (P7) D6 + FF-CAS 3분기 reconciliation + exactly-once (ledger append) | success | 4s |
| 15 | (P7b) [SL-15] evidence record → evidence CAS ledger append (exactly-once) | success | 4s |
| 16 | (P7c) [SL-15] judgment record → judgment CAS ledger append (exactly-once) | success | 5s |
| 17 | (P7c-x) [SL-15] extension judgment records → judgment CAS ledger append (exactly-once ×3) | success | 11s |
| 34 | Post Checkout B only (trusted config/tree; no M/H checkout) | success | 1s |
| 35 | Complete job | success | 0s |

### Run 821(41420386024)

#### mint-prepare / prepare (wall 53s)

| # | step | 결론 | wall |
|---|---|---|---|
| 1 | Set up job | success | 1s |
| 2 | [venue] Resolve execution venue (PR=preflight / MG+call=landing) | success | 0s |
| 3 | (0) Activation guard — API re-verify (workflow_call) | success | 1s |
| 4 | (1) Derive B/H via run API + PR API (no M — pre-landing mint) | success | 0s |
| 5 | Checkout B only (trusted config/tree; no M/H checkout) | success | 6s |
| 6 | [slice-engine] Load epoch manifest implementedSlices (B tree — scope authority) | success | 0s |
| 7 | Run ./.github/actions/setup-axiom-toolchain | success | 22s |
| 8 | [preflight] Prepare-leg static contrast (policy SSOT + mint structure) | skipped | 0s |
| 9 | [mint] Consume admission B-built bin/ax (build-base-artifacts — run-scoped + build_sha==B + sha256 pin) | success | 4s |
| 10 | (2a)+ (2b)+ (2c) TrustedWriterSet@B + PR API identity + provenance comparison | success | 1s |
| 11 | (3) Artifact retrieval — run-scoped API + trusted-name + witness sha + provenance check | success | 1s |
| 12 | (3b) Merge-candidate tree identity — witness.mergeTreeDigest == tree(mergeSha) (fail-closed) | success | 0s |
| 13 | (4) Verify + normalize witness (B-built trusted ax) | success | 0s |
| 14 | (5) Cert artifact digest + manifest + upload (subject-certificate-<run_attempt>) | success | 0s |
| 15 | (5b) Upload subject-certificate artifact (trusted-name) | success | 3s |
| 30 | Post Checkout B only (trusted config/tree; no M/H checkout) | success | 0s |
| 31 | Complete job | success | 0s |

#### mint-publish / publish (wall 48s)

| # | step | 결론 | wall |
|---|---|---|---|
| 1 | Set up job | success | 1s |
| 2 | [venue] Resolve execution venue (PR=preflight / MG+call=landing) | success | 0s |
| 3 | Checkout B only (trusted config/tree; no M/H checkout) | success | 3s |
| 4 | Run ./.github/actions/setup-axiom-toolchain | success | 13s |
| 5 | [slice-engine] Load epoch manifest implementedSlices (contents API @B — scope authority) | success | 0s |
| 6 | (P0) Publish activation guard — self-binding + gate-run identity + PR identity + (a) | success | 0s |
| 7 | [preflight] Publish-leg structural contrast (single-writer posture + stage structure) | skipped | 0s |
| 8 | (P1) [X]1 artifact identity — run-scoped + trusted-name + artifact-id download | success | 2s |
| 9 | (P2) [X]2 file digest — cert_sha256 manifest 대조 + build_sha == B (provenance) | success | 0s |
| 10 | (P3) Bin/ax 준비 — artifact의 B-built bin/ax (build_sha==B, sha256 pin) | success | 0s |
| 11 | (P4) [X]3 field binding — subjectId/baseSha/headSha/certTree/evidenceDigest == 재유도값 + (a) headSha | success | 1s |
| 12 | (P5) [B2] (b) canonical tree identity — testedTreeDigest == tree(github.sha) == cert.certTree | success | 1s |
| 13 | (P6) [B2] (c) gateway lane conclusion == success + 시간 인과 (jobs API) | success | 1s |
| 14 | (P7) D6 + FF-CAS 3분기 reconciliation + exactly-once (ledger append) | success | 4s |
| 15 | (P7b) [SL-15] evidence record → evidence CAS ledger append (exactly-once) | success | 4s |
| 16 | (P7c) [SL-15] judgment record → judgment CAS ledger append (exactly-once) | success | 4s |
| 17 | (P7c-x) [SL-15] extension judgment records → judgment CAS ledger append (exactly-once ×3) | success | 11s |
| 34 | Post Checkout B only (trusted config/tree; no M/H checkout) | success | 1s |
| 35 | Complete job | success | 0s |

### Run 823(41421620938)

#### mint-prepare / prepare (wall 35s)

| # | step | 결론 | wall |
|---|---|---|---|
| 1 | Set up job | success | 1s |
| 2 | [venue] Resolve execution venue (PR=preflight / MG+call=landing) | success | 0s |
| 3 | (0) Activation guard — API re-verify (workflow_call) | success | 1s |
| 4 | (1) Derive B/H via run API + PR API (no M — pre-landing mint) | success | 1s |
| 5 | Checkout B only (trusted config/tree; no M/H checkout) | success | 5s |
| 6 | [slice-engine] Load epoch manifest implementedSlices (B tree — scope authority) | success | 0s |
| 7 | Run ./.github/actions/setup-axiom-toolchain | success | 13s |
| 8 | [preflight] Prepare-leg static contrast (policy SSOT + mint structure) | skipped | 0s |
| 9 | [mint] Consume admission B-built bin/ax (build-base-artifacts — run-scoped + build_sha==B + sha256 pin) | success | 4s |
| 10 | (2a)+ (2b)+ (2c) TrustedWriterSet@B + PR API identity + provenance comparison | success | 1s |
| 11 | (3) Artifact retrieval — run-scoped API + trusted-name + witness sha + provenance check | success | 1s |
| 12 | (3b) Merge-candidate tree identity — witness.mergeTreeDigest == tree(mergeSha) (fail-closed) | success | 1s |
| 13 | (4) Verify + normalize witness (B-built trusted ax) | success | 0s |
| 14 | (5) Cert artifact digest + manifest + upload (subject-certificate-<run_attempt>) | success | 0s |
| 15 | (5b) Upload subject-certificate artifact (trusted-name) | success | 2s |
| 30 | Post Checkout B only (trusted config/tree; no M/H checkout) | success | 1s |
| 31 | Complete job | success | 0s |

#### mint-publish / publish (wall 35s)

| # | step | 결론 | wall |
|---|---|---|---|
| 1 | Set up job | success | 0s |
| 2 | [venue] Resolve execution venue (PR=preflight / MG+call=landing) | success | 0s |
| 3 | Checkout B only (trusted config/tree; no M/H checkout) | success | 4s |
| 4 | Run ./.github/actions/setup-axiom-toolchain | success | 9s |
| 5 | [slice-engine] Load epoch manifest implementedSlices (contents API @B — scope authority) | success | 0s |
| 6 | (P0) Publish activation guard — self-binding + gate-run identity + PR identity + (a) | success | 0s |
| 7 | [preflight] Publish-leg structural contrast (single-writer posture + stage structure) | skipped | 0s |
| 8 | (P1) [X]1 artifact identity — run-scoped + trusted-name + artifact-id download | success | 1s |
| 9 | (P2) [X]2 file digest — cert_sha256 manifest 대조 + build_sha == B (provenance) | success | 0s |
| 10 | (P3) Bin/ax 준비 — artifact의 B-built bin/ax (build_sha==B, sha256 pin) | success | 0s |
| 11 | (P4) [X]3 field binding — subjectId/baseSha/headSha/certTree/evidenceDigest == 재유도값 + (a) headSha | success | 2s |
| 12 | (P5) [B2] (b) canonical tree identity — testedTreeDigest == tree(github.sha) == cert.certTree | success | 1s |
| 13 | (P6) [B2] (c) gateway lane conclusion == success + 시간 인과 (jobs API) | success | 0s |
| 14 | (P7) D6 + FF-CAS 3분기 reconciliation + exactly-once (ledger append) | success | 4s |
| 15 | (P7b) [SL-15] evidence record → evidence CAS ledger append (exactly-once) | success | 5s |
| 16 | (P7c) [SL-15] judgment record → judgment CAS ledger append (exactly-once) | success | 1s |
| 17 | (P7c-x) [SL-15] extension judgment records → judgment CAS ledger append (exactly-once ×3) | success | 5s |
| 34 | Post Checkout B only (trusted config/tree; no M/H checkout) | success | 1s |
| 35 | Complete job | success | 0s |

### Run 824(41422458822)

#### mint-prepare / prepare (wall 46s)

| # | step | 결론 | wall |
|---|---|---|---|
| 1 | Set up job | success | 1s |
| 2 | [venue] Resolve execution venue (PR=preflight / MG+call=landing) | success | 0s |
| 3 | (0) Activation guard — API re-verify (workflow_call) | success | 0s |
| 4 | (1) Derive B/H via run API + PR API (no M — pre-landing mint) | success | 1s |
| 5 | Checkout B only (trusted config/tree; no M/H checkout) | success | 4s |
| 6 | [slice-engine] Load epoch manifest implementedSlices (B tree — scope authority) | success | 0s |
| 7 | Run ./.github/actions/setup-axiom-toolchain | success | 17s |
| 8 | [preflight] Prepare-leg static contrast (policy SSOT + mint structure) | skipped | 0s |
| 9 | [mint] Consume admission B-built bin/ax (build-base-artifacts — run-scoped + build_sha==B + sha256 pin) | success | 3s |
| 10 | (2a)+ (2b)+ (2c) TrustedWriterSet@B + PR API identity + provenance comparison | success | 1s |
| 11 | (3) Artifact retrieval — run-scoped API + trusted-name + witness sha + provenance check | success | 0s |
| 12 | (3b) Merge-candidate tree identity — witness.mergeTreeDigest == tree(mergeSha) (fail-closed) | success | 1s |
| 13 | (4) Verify + normalize witness (B-built trusted ax) | success | 0s |
| 14 | (5) Cert artifact digest + manifest + upload (subject-certificate-<run_attempt>) | success | 0s |
| 15 | (5b) Upload subject-certificate artifact (trusted-name) | success | 2s |
| 30 | Post Checkout B only (trusted config/tree; no M/H checkout) | success | 0s |
| 31 | Complete job | success | 0s |

#### mint-publish / publish (wall 53s)

| # | step | 결론 | wall |
|---|---|---|---|
| 1 | Set up job | success | 0s |
| 2 | [venue] Resolve execution venue (PR=preflight / MG+call=landing) | success | 0s |
| 3 | Checkout B only (trusted config/tree; no M/H checkout) | success | 4s |
| 4 | Run ./.github/actions/setup-axiom-toolchain | success | 9s |
| 5 | [slice-engine] Load epoch manifest implementedSlices (contents API @B — scope authority) | success | 1s |
| 6 | (P0) Publish activation guard — self-binding + gate-run identity + PR identity + (a) | success | 0s |
| 7 | [preflight] Publish-leg structural contrast (single-writer posture + stage structure) | skipped | 0s |
| 8 | (P1) [X]1 artifact identity — run-scoped + trusted-name + artifact-id download | success | 1s |
| 9 | (P2) [X]2 file digest — cert_sha256 manifest 대조 + build_sha == B (provenance) | success | 0s |
| 10 | (P3) Bin/ax 준비 — artifact의 B-built bin/ax (build_sha==B, sha256 pin) | success | 0s |
| 11 | (P4) [X]3 field binding — subjectId/baseSha/headSha/certTree/evidenceDigest == 재유도값 + (a) headSha | success | 1s |
| 12 | (P5) [B2] (b) canonical tree identity — testedTreeDigest == tree(github.sha) == cert.certTree | success | 1s |
| 13 | (P6) [B2] (c) gateway lane conclusion == success + 시간 인과 (jobs API) | success | 1s |
| 14 | (P7) D6 + FF-CAS 3분기 reconciliation + exactly-once (ledger append) | success | 3s |
| 15 | (P7b) [SL-15] evidence record → evidence CAS ledger append (exactly-once) | success | 4s |
| 16 | (P7c) [SL-15] judgment record → judgment CAS ledger append (exactly-once) | success | 4s |
| 17 | (P7c-x) [SL-15] extension judgment records → judgment CAS ledger append (exactly-once ×3) | success | 10s |
| 34 | Post Checkout B only (trusted config/tree; no M/H checkout) | success | 0s |
| 35 | Complete job | success | 0s |
