# ci-bootstrap 가치사슬 실측 — 5지표 측정 후 keep·MG-이관·삭제 결정 (2026-10-09)

> **문서 성격**: 실행 증거(§5 SSOT — docs/evidence). 승인 계획
> `wasp-swamp-thing-colossus.md`의 Slice 2(ci-bootstrap 실측 슬라이스) 산출물.
> 본 문서는 **측정 + 사전 확정 결정 규칙에 실측값을 채워 기록**하는 것이 전부다.
> 제거·이관·저가화의 **구현은 본 슬라이스 범위 밖**(별도 최소 슬라이스)이며,
> 워크플로·코드 변경 0건.

## 0. 관측 창·방법론

| 항목 | 값 |
|---|---|
| 관측 창 | **2026-10-07T07:12:08Z → 2026-10-09T08:24:32Z** (≈49시간, venue split(ADR-0032, 2026-10-08T23:49Z 착지) 전·후 포함) |
| 모집단 | `admission-gate`(조직 필수 워크플로, Archright/Axiom) **243런** = PR 144 + merge_group 99 (전수) |
| 수집 경로 | `gh api repos/Archright/Axiom/actions/runs`(created=2026-09-25..2026-10-09, name==admission-gate) · `/runs/{id}/jobs` · `/runs/{id}/logs`·`/jobs/{id}/logs`(ANSI strip) · `/actions/caches` · publisher(`ci-cache-publisher`) 런 243건 로그 전수 |
| 원본 보존 | 채굴 원본(publisher 로그 zip 243건·집계 TSV)은 세션 로컬 `/tmp/ciboot-metrics/` — 본 문서의 모든 수치는 이 원본에서 재계산 가능. 로그 만료(~90일) 후 소급 재판정은 불가 (사전 식별 잔여 리스크대로 창 내 종결) |
| 한계 | 러너 VM 1.4–1.5× 속도 편차 (계획 §리스크 3·4) → cold/warm 비교는 **페어드 불가** 모집단 차이를 명시하고 wall 수준 결론은 "기여 0·역전(노이즈)"까지만. 비용 실측은 enhanced billing 미사용 — job 분 합산 근사 |

`gh api` 대표 명령 (본 문서 모든 표의 출처):

```
gh api --paginate "repos/Archright/Axiom/actions/runs?created=2026-09-25..2026-10-09&per_page=100" \
  --jq '.workflow_runs[] | select(.name=="admission-gate") | [.id,.event,.conclusion,.created_at,.head_branch] | @tsv'
gh api "repos/Archright/Axiom/actions/runs/<id>/jobs?per_page=100" \
  --jq '.jobs[] | select(.name|test("ci-bootstrap|/ select")) | [.id,.name,.conclusion,.started_at,.completed_at] | @tsv'
gh api "repos/Archright/Axiom/actions/jobs/<job_id>/logs" --allow-escape-sequences | sed 's/\x1b\[[0-9;]*m//g'
gh api "repos/Archright/Axiom/actions/caches?per_page=100" --jq '.actions_caches[] | [.key,.created_at,.last_accessed_at,.size_in_bytes] | @tsv'
```

> **공식 문서 quirk (측정 중 발견 — §0.5 Quirk Mandate)**: `actions/runs?created=>=2026-09-25T00:00:00Z`
> (부등호+ISO 타임스탬프)은 필터가 적용되지 않고 최신순 전체가 반환된다(관측 2회 재현).
> 기간 필터는 **`created=A..B` 범위 문법**만 신뢰 가능. 또한 범위 질의의 `total_count`는
> 2500에서 캡되어 관측됨 — 전수 확보는 `--paginate` + 결과 라인 수 검증(243)으로 마침.
> `gh api .../jobs/{id}/logs`는 ANSI 시퀀스가 포함되면 사전 거부 — `--allow-escape-sequences` 필요.

## 1. 발화 구조 (selector 종속 — 사전 확정 사실 재확인)

- 발화 규칙 SSOT: `tools/ci/impact_closure_selector.nim:1043` —
  `ciBootstrap = (mode == "full") ∨ ("W2" ∈ executableWorkUnits) ∨ w8`.
  잡 조건: `.github/workflows/runner-pool-acceptance.yml:474-476`
  (`needs:[select]`, mode=full ∨ mode=selected∧ciBootstrap=true).
- **envelope 실측 검증** (select 잡 로그의 decision envelope 덤프):
  - MG skip 표본 37902009229·37890135588: `"mode": "none"`, `"ciBootstrap": false`
  - MG 실행 표본 37904763970: `"mode": "full"`, `"ciBootstrap": true`
- 창 내 발화율 (잡 conclusion 기준, jobs API):

| 이벤트 | 런 | ci-bootstrap 실행 | skip(mode=none) | 발화율 |
|---|---|---|---|---|
| pull_request | 144 | 88 | 56 | **61.1%** |
| merge_group | 99 | 59 | 40 | **59.6%** |
| 합계 | 243 | 147 | 96 | 60.5% |

- post-split(ADR-0032 이후, 2026-10-08T23:49Z~): PR 55런 중 실행 24 (43.6%), MG 27런 중 실행 16 (59.3%).

## 2. 지표 1 — PR ci-bootstrap 비용 (jobs API span, 실행 88건 전수)

| 통계 | 값 |
|---|---|
| n | 88 (PR 실행 런 전수, success) |
| min / p50 / avg / max | **179s / 239s / 235.3s / 281s** |
| 분포 | 하단 179–202s 10건, 235–252s 대 밀집(최빈), 상단 278/281s |
| red | **0 / 88** |

- 기존 실측 대조: canary 런 **37886858198**(계획의 DAG 근거 런) ci-bootstrap = **202s** —
  jobs API 재측정(`05:05:57→05:09:19`)으로 **동일 재현**. census(2026-09-30)의 169–182s 대비
  현재 창은 avg +53~66s (+31~39%) — 레시피/페이로드 세대 변동 포함, 본 결정에는
  현재 창 실측(avg 235s)을 채택.
- **publisher 비용**(발화 시 후행 런, workflow_run): job duration n=26 표본
  min 0s / p50 21s / avg 31s / max 89s.
- **PR lane 발화 총비용(근사, 창 3일)**: 88 × 235s ≈ **5.75 runner-hours** (ci-bootstrap 잡만)
  + publisher 243런 × 31s ≈ 2.1 runner-hours (lane-save 외 base-seed·a-seed·verdict 로그 포함 — lane 귀속분은 그 일부).

## 3. 지표 2 — lane-seed 게시 성공률 (publisher 로그 243건 전수, 런타임 라인만)

런타임 판별 앵커: `Z [publish] lane-save: outcome=…`, `Z [publish-skip] …`, `Z [publish-fail] …`,
`Z Cache saved with key: axiom-b-…` (소스 에코는 `Z   echo "[publish…` 형태로 배제).

| 트리거 이벤트 | SAVE-OK (`Cache saved with key:`) | single-flight skip (`lane key exists`) | identity/manifest 차단 (R6/R10) | lane 미실행 (mode=none 등) | 구버전 로그(판별 불가) | 합계 |
|---|---|---|---|---|---|---|
| pull_request | **49** | 2 | 22 | 28 (artifacts-absent 18 + chain-nonexec 10) | 0 | 101 |
| merge_group | **50** | 12 | 0 | 24 (artifacts-absent 21 + chain-nonexec 3) | 3 | 89 |
| 트리거 미해석 | 0 | 0 | 0 | 53 (publisher 런 conclusion **skipped** 52 + cancelled 1 — Publish 잡 미실행) | 0 | 53 |
| 합계 | 99 | 14 | 22 | 105 | 3 | 243 |

- **lane-seed 게시 성공률(분모 = lane chain이 실제 실행된 PR 발화 73건)**:
  저장 **49 (67.1%)** · single-flight skip 2 (2.7%) · **저장 차단 22 (30.1%)**.
- 차단 22건의 런타임 사유 원문(2클래스): `[publish-skip] tree(build_sha)=<T1> != tree(head_sha)=<T2> —
  content identity not landable as tested (ahead invariant absent; residuals R6)` 와
  `[publish-skip] manifest.txt missing after download`. 즉 **PR head가 빌드 트리보다 앞서면
  시드는 설계상 저장되지 않는다** — 창 내 30%가 이 구조적 차단.
- **`[publish-fail]`(lane reservation lost) 런타임 발생: 0건** (창 내 전체). `[publish-fail]` 실측 표본 0은 계획 §교정 2의 진짜 갭이 그대로 유지됨.

## 4. 지표 3 — MG 동일 identity HIT·MISS·skip (b-key 문자열 상관)

MG ci-bootstrap 잡 99건: skip 40(mode=none) · 실행 59. 실행 59건의 로그 전수:

| 상태 | n | 비율 |
|---|---|---|
| B-HIT (`Cache hit for: axiom-b-<동일 key>`, bmiss_n=0) | **16** | 27.1% |
| B-MISS (`Cache not found`) | 43 | 72.9% |

- **HIT 소싱** (b-key 조인: publisher `AXIOM_CACHE_KEYGEN: b-key=` ↔ MG 잡 keygen b-key ↔
  캐시 API `created_at/last_accessed_at`):

| 소스 | n | 근거 |
|---|---|---|
| **PR publisher 시드 선행 저장** | **10** | 동일 b-key의 PR-triggered publisher 저장이 MG 소비(잡 start) 선행 — 예: 37904680390(08:24:02 저장) → MG 37904762781 소비(08:25:52, **110초 후**); Oct 8대 9건은 저장 후 **~90–130초** 내 소비 |
| 동일-G 재발화(MG publisher 선행) | 2 | 37870822698·37875631786 ← MG publisher(37865790583, 00:38:20 저장) — 큐 재시도 세대 |
| 소비 시점 엔트리 부재(only-after) | 4 | 37586763966 등 — 동일 key 캐시 엔트리가 소비 이후 생성만 관측(창 외부 시드 또는 퇴출/덮어쓰기 소실; taxonomy의 퇴출-소실 클래스, 소급 확정 불가) |

- **PR 측 소비**: PR ci-bootstrap 88건 중 B-HIT **2건 (2.3%)** (37863398592·37859919931) —
  PR lane은 사실상 **매번 콜드 컴파일**(B producer이지 소비자가 아님).

## 5. 지표 4 — MG cold vs warm (페어드 불가 모집단 명시)

| 구분 | n | ci-bootstrap 잡 span (min/p50/avg/max) |
|---|---|---|
| COLD (B-MISS) | 43 | 185 / 241 / **238.4s** / 315s |
| WARM (B-HIT) | 16 | 57 / 210 / **202.1s** / 284s |
| Δ(잡 span) | | **−36.3s (avg)** |

- **S5 공급재사용 활성 표본은 2/16뿐** (s5 `B-verified supply reuse` 런타임 라인 2회 —
  37904762781=95s, 37875631786=57s, 절감 ~140–180s). 나머지 14 HIT는
  **S5 미착지 세대**(창 중반 이전 워크플로 버전) — B 페이로드 복원 후
  warm nimcache로 `make ci-compile` 재실행(166–284s, 절감 ~0–70s).
- **MG 런 wall (created→updated)**: COLD n=43 avg 691.6s (p50 669) vs WARM n=16
  avg 740.3s (p50 799) — **WARM이 오히려 뒤처짐(역전)**. 비페어드·러너/큐 편차 지배로
  wall 수준 결론: **시드 유무의 MG wall 기여 = 0 (실측)**.
- **MG 임계경로 직접 실측** (실행 MG 59런의 jobs API): `mint-publish`가 ci-bootstrap
  완료를 기다린 케이스 — **WARM 0/16, COLD 4/43(대기 3–35s, slack 6–70s)**.
  attest 체인(~9.5분 slack)이 MG를 지배하고 lane이 흡수한다는 계획 §교정 1의
  "(b) 시드 소실 → MG 느려짐 성립 불가"가 **정량으로 재확인**됨.

## 6. 지표 5 — (a) 조기검출 가치 (red 빈도 채굴)

- 창 3일: ci-bootstrap red **0 / 243런**(실행 147건 전부 success).
- **30일 확대 스캔**(2026-09-09..2026-10-09, conclusion=failure 런 47건 전수): 해당 런들의
  ci-bootstrap 잡 conclusion = success 19 + skipped 28, **failure 0** — 게이트 실패는
  전부 타 잡. 즉 **30일간 "ci-bootstrap이 컴파일 파손을 조기 잡은" 실측 사례 0건**.
- 컴파일-브로큰 픽스처 PR(선택 항목): **미수행**. 사유 — 사전 확정 결정 규칙상
  "(a) red 빈도 ≈0"이 판정 조건이고 그 값이 0/30일로 확정되어, 픽스처 1표본은
  규칙 분기를 바꿀 수 없음(지연·슬롯 비용 1표본의 반사실 계량은 잔여로 이관).
- post-split PR 임계경로 실측(Oct 9 PR 런 12건, jobs API): **6/12**에서 `mint-publish`가
  ci-bootstrap 완료를 기다림(준비 체인 종료 후 **143–182s**, avg ~161s) —
  canary의 2m26s(146s)와 동일 구조 재현. 나머지 6/12는 attest 체인이 지배(slack 3–4s).
  → "지배 여부는 selector 분포에 달렸다"(계획 §교정 1)와 일치.

## 7. producer → consumer 맵 (실측 확정분)

```
[PR 런] gateway/select ─needs→ gateway/ci-bootstrap (컴파일 = (a) 유일 PR 컴파일 게이트)
   │  발화 61% (88/144) · avg 235s · B-HIT 2/88 (producer이지 소비자 아님)
   ├─→ artifact ci-bootstrap-artifacts(9경로) → publisher lane-save
   │      PR publisher 101: SAVE-OK 49(67%) / single-flight 2 / R6·R10 차단 22(30%) / lane 미실행 28
   │      → B캐시 엔트리 axiom-b-<tree(head)>-<recipe><a_fp> (48–49MB)
   ├─→ [소비 1] 동일 PR 재런: B-HIT 2/88 (재런만)
   └─→ [소비 2] MG ci-bootstrap 복원(동일 identity): MG 실행 59 중 HIT 16
          소싱: PR 시드 10 / 동일-G 2 / 엔트리 소실 4
          절감: 잡 span −36.3s avg (S5 활성 2표본만 −140~180s)
          **MG wall 기여 0 실측** (mint-publish 지배 WARM 0/16)
[MG 런] gateway/ci-bootstrap = 착지 venue 검증의 일부 (mode=full/selected)
          ※ 본 결정의 대상은 **PR venue lane**이며 MG 착지 게이트는 범위 밖
[S5(feat/s5-build-skip, 진행 중)] MG B-HIT를 공급재사용으로 소비 — lane 시드가
          S5의 MG 입력임 (소비 가치 재평가는 S5 착지 후 별도 슬라이스)
```

## 8. 비용 ↔ 소비 비대칭 (창 3일 합산)

| | 근거 | 러너 job-min (창 3일) |
|---|---|---|
| PR lane ci-bootstrap | 88 × 235s | **≈ 345 job-min** |
| publisher 런 | 243 × 31s (lane-save 외 기능 포함) | ≈ 126 job-min |
| 소비 실현 가치 (MG 잡 span 절감 합) | 16 HIT × 36.3s | **≈ 9.7 job-min** |
| 소비의 wall 가치 | MG wall 역전 + mint-publish 지배 WARM 0/16 | **0** |

**비대칭 ≈ 36 : 1** (lane 잡만 기준 345 : 9.7; publisher 합산 시 ≈ 49 : 1). 소비율은
존재(27%)하나 절감의 실현 가치가 lane 비용의 ~2.8%(publisher 포함 시 ~2.1%) —
"소비율·절감 유의" 기준 미달.

## 9. 결정 (사전 확정 규칙에 실측 채움)

사전 확정 규칙(승인 계획 §보강 3):
1. 발화율 높음 ∧ 소비율 낮음 ∧ (a) red 빈도 ≈0 → **삭제·저가화 후보**
2. 소비율·절감 유의 → keep
3. 발화율 높음 ∧ (a) 가치 실재 → keep(조기검출 수용) 또는 MG-이관

**적용: 발화율 높음(61.1% / post-split 43.6%) ∧ 소비 절감 무의(≈2%, wall 0 실측) ∧
(a) red 0건/30일 → 규칙 1 발동 → 결정 =「ci-bootstrap PR-venue lane 삭제·저가화 후보」.**

근거 요약:
- 비용은 매 W2-PR 발화 시 **확정**(235s avg + post-split 50%의 런에서 임계경로 지배 143–182s),
  소비는 세대 역학상 우연이고 그 가치가 MG wall에서 0으로 실측 — 계획 §교정 1의
  "비용 확정/소비 우연" 비대칭이 정량으로 닫힘.
- (a) 컴파일 조기검출의 가치는 **30일간 미실현**(red 0건; 47 실패 런 전수 포함) —
  규칙 3의 "(a) 가치 실재" 분기는 미발동. MG-이관도 (a) 수용 여부의 함수라 정당화 근거가 없음.
- PR publisher의 시드 저장 성공률 67% + 차단 30%(ahead invariant)는
  lane 가치사슬의 추가 누수 — 삭제 시 이 구조 전체가 소멸.
- MG 측 ci-bootstrap(착지 검증 게이트)과 publisher의 base-seed·a-seed 기능은
  본 결정 대상이 **아니며** 별개 가치사슬로 유지.

**유보·전제**: 이 결정은 "후보"이며 구현(제거·저가화·이관 설계)은 **별도 최소 슬라이스**에서
진행한다(본 슬라이스 금지 규칙 준수). S5 build-skip 슬라이스가 lane 시드를 MG 입력으로
소비하므로, S5 착지 시 본 결정을 재검토해야 한다(§10 잔여 4).

## 10. 잔여 (Follow-up)

1. **컴파일-브로큰 픽스처 PR 미수행** — (a) 지연·슬롯 비용 1표본의 반사실 계량은
   red 실측 0건이어도 "삭제 시 파손 검출이 MG로 완전 이관될 때의 비용" 수치로
   유용하다. 삭제-구현 슬라이스의 사전 실측으로 이관 권장.
2. **`[publish-fail]` 실측 표본 0** — 계획 §교정 2의 미해결 갭 그대로. 창 내 미발생.
3. **소비 시점 엔트리 소실 4건**의 정밀 분류(퇴출 vs 창 외부 시드) — 캐시 퇴출 관측 창
   (10GB 상한 초과 구간)이 필요. duplicate-computation 관측 슬라이스와 결합 가능.
4. **S5 시대 소비 가치 재측정** — S5 활성 표본 2건(95s/57s)은 유망하나 창 내
   2표본뿐. S5가 전면 착지하면 "B-HIT → compile skip"의 MG 잡 절감(−140~180s)이
   lane 시드의 실질 소비 가치가 된다 — 이때 본 결정 재검토.
5. **게이트 컨텍스트 페이로드의 러너 편차** — cold/warm 비교는 비페어드라
   1.4–1.5× 편차를 wall 결론에 반영 못 함. 페어드 설계(동일 커밋 재런)는 별도 실측 과제.
6. **landing_observe.sh TERMINAL_SUCCESS 미수행** — §11의 main 착지 경로 회귀
   (DEBT#503) 해소 후 PR 재진입 → 병합 → MERGE OID(2-parents) 확정 → landing
   관측으로 종결.

## 11. 착지 차단 사건 (2026-10-09 — 본 문서 PR의 착지 경로에서 실측)

본 문서를 실은 PR #650의 병합 관측 중, main 착지 경로 전체가 회귀로 막히는 사건이
실측됐다. 측정 산출물이 아닌 **착지 장애의 1차 증거 기록**으로 여기에 남긴다.

- **시계**: #646(DEBT#501 fail-closed 전환, src/cli/merge_cli.nim만 변경)이
  TRUST_SURFACE_MODIFIED 수동 경로로 10:05:51Z 착지 → #650 MG 배치(base
  a12e555383) 판정 10:06:45Z **mergeAborted(ROT_UNSPECIFIED)** → 큐 이탈 →
  후속 정상 배치 #628(10:18:14Z)·#627(10:26:14Z) 동일 실패 — 신규 main 위의
  **모든** merge_group 정상 배치가 ROT_UNSPECIFIED로 거부됨(런
  37913885973·37915594405·37916822611 실측).
- **기구**: #646은 unspec 회전 판정을 fail-closed로 바꿨으나 SL-02는
  epoch_manifest의 notYetImplementedSlices에 그대로여서 derived-closure
  아티팩트 공급 경로(scope_sl02 게이트, admission-check.yml:1521)가 어떤
  배치에서도 활성화되지 않는다 — 판정의 유일한 만족 입력이 존재하지 않는
  도메인에 fail-closed가 활성화된 형태. #646 자체 배치는 판정이
  TRUST_SURFACE_MODIFIED(exit 0, 수동 병합 경로)라 새 분기를 실검 없이
  통과했다(런 37913719570 verdict job 113770184102).
- **극장 등록**: §0.9에 따라 **DEBT#503**(Theater/Unenforced Claim, high)으로
  등록했다(DEBT#502는 병렬 슬라이스 PR #652가 사용 중 — ID 충돌 회피).
  DEBT#501은 #646 착지 시 closed/FIXED로 전환됐으나 본 §11의 측정은 그
  closure가 착지 경로를 차단함을 보이는 반증 증거다. 구현·워크플로 변경은
  본 슬라이스 금지 규칙상 수행하지 않았고, 해결(epoch_manifest 승격 또는
  판정 재스코프)은 아키텍트 결정 사항이다. `bin/debt_engine --codegen`으로
  프로젝션 재생성·`--validate` 전수 통과를 확인했다.
- **본 슬라이스에 미치는 영향**: PR #650은 자체 required checks 전부 pass,
  mergeStateStatus=CLEAN으로 병합 대기 중이었으나 위 회귀로 큐 판정이
  불가능하다. **landing_observe.sh TERMINAL_SUCCESS는 미수행** — 회귀 해소
  후 재진입 시 수행한다(§10 잔여 6).

## 12. 측정 산출 원본

- publisher 로그 zip 243건: `/tmp/ciboot-metrics/publogs/<run_id>.zip` (세션 로컬)
- 집계 원본 TSV: `gate_runs.tsv`(243) · `ciboot_jobs.tsv`(486) · `mg_signals.tsv`(59) ·
  `pr_signals.tsv`(88) · `pub_signals3.tsv`(243) · `caches.tsv`(211) · `bcache.tsv`(82) ·
  `mg_wall.tsv`(99) · `dag_oct9.tsv` · `dag_mg.tsv` · `redcheck.tsv`(47)
- 본 문서의 수치는 위 원본에서 집계 스크립트로 재계산한 값이며, 임의 생성 수치 0건.
