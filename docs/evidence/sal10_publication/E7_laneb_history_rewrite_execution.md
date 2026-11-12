# E7 — Lane B 전체 Git 이력 재작성 실행 기록 (Publication Integrity v3.2)

**실행일**: 2026-11-08 (동결창 12:45:59Z–15:38:05Z·ruleset 비상창 15:35:10Z–15:42:39Z) · **실행자**: Lane B 에이전트 (격리 fresh clone — 본체 클론 불침범)

## Ultimate Purpose

Axiom 저장소 전체 Git 이력에서 비공개 대상 정보(인프라 지문·제3자 PII·개인 경로·사업 CI 비용·재배포 금지 자료)를
제거하고, 원격 전 refs를 일관된 재작성 세대(coherent generation)로 일괄 전환한다.

## 승인 및 산물 보관 원칙

- 사용자 전면 승인(자동 권한 모드) — 실행 정본: `~/.cache/axiom/publication/laneb-spec.md` (동결본)
- bundle·commit-map·ref_map·first-changed·replace-text-extended·ruleset 백업 전부 **사적 캐시**
  (`~/.cache/axiom/publication/laneb-private/`) — repo/Actions 업로드 없음

## 세대 전이 관측 (commit-map)

| 구 SHA | 신규 SHA | 의미 |
|---|---|---|
| `2c48285d0121c04b4c447d2551652d8952bd431e` | `df378f603070c243afbd8718a22df3d08a9d90fb` | main tip (#20 병합) |
| `938a49e024e4139b736ba81f568b74076d47bb2a` | `6104b249c14c50c183dd54a428168b29a9561f10` | clean-origin 루트 (핀 회전 대상) |
| `8058d18f1eb7c010d7bd0a34b603b0834986d39e` | `08c37b4308965cb812f2a6331af467d1746037c3` | workstream/s2c-standalone-bundle-observation |
| `c1245c09…` / `723b745f…` | (재작성 후 ref 삭제) | axiom/certificates·axiom/evidence-cas 레저 side ref |

- **결정론 증명**: 앱 크래시(관측 공백) 후 사적 캐시의 pre-rewrite.bundle(sha256 검증 원본) + origin fetch로
  동일 ref 집합을 재현해 filter-repo를 재실행 — 재생성 commit-map이 저장본과 **전 라인 일치**(diff 0)로 관측.
  재작성은 (원격 상태, pathspec, replace-text)에 대해 결정론적임이 실증됨.

## 1차 재작성 → Phase 3(d) FAIL → 확장 치환 (정책 변경 아님)

- 1차(동결 replace-text 14종): (a) 제거 경로 0 · (b) KEEP 존재 · (c) 14패턴 0 — PASS.
  (d) 침소 5종 **패턴당 40잔존** FAIL — 전 매치가 `E2_cutover_execution.md` 과거 개정 40본의
  (d) 검증 라인이 패턴 리터럴을 인용한 것 (현재 HEAD는 이미 마스킹됨, 이력만 잔존).
- **대응**: `laneb-private/replace-text-extended.txt` — 동결 14종 원문 + E2 정본 치환 관례
  (`~/.cache/axiom/sal10_cutover/replace_text.txt`)의 침소 표현식 블록. 선례: pathspec-final.txt 스코프 노트
  (실측 발견의 문서화된 확장). 증거: `laneb-private/phase3-d-failure-evidence.txt`.
- 2차(확장 26종) 재검증: (a)(b)(c)(d) **전부 PASS** (binary 포함 grep, 침소 5종 0, 8진 이스케이프 변형 0).

## 신원·메시지 불변 판정

- 커밋 수 161→161 (동일 ref 집합) · author|email 전 라인 불변.
- `%an|%ae|%s` 3라인 차이 — 전부 메시지에 박힌 구 SHA 참조가 신규 SHA로 치환된 것
  (hex 토큰 마스킹 시 diff 0으로 기계 증명). spec Terminal Outcome "SHA만 변동"의 문자적 실현.
- 잔여 레저 메시지의 미치환 구 SHA 참조(단절)는 증거 기록의 세대 경계 특성 — E2 선례(재작성 전 기록)와 동일 유형.
  기계 원인은 `docs/spec/git_filter_repo_quirks.md` Q2로 문서화.

## 동결창 (Actions 비활성)

- 개시: **2026-11-08T12:45:59Z** — `PUT /repos/Archright/Axiom/actions/permissions` (enabled=false),
  GET readback `{"allowed_actions":null,"enabled":false}` 관측.
- 개시 조건 관측: in_progress run 0 · queued 0 · merge queue entries 0 · 열린 PR 0.
- **관측 공백**: ~13:2xZ 앱 종료 → 15:15Z(main agent)·15:24:08Z(본 에이전트 재개 첫 관측)까지.
  공백 기간 원격 무변동(main 2c48285d·4본·ruleset 6종 active)은 15:15Z/15:24Z 관측으로 소급 확보.
- 재개 첫 행동 = spec 불변 규칙 6: Actions enabled? + ruleset 6종 enforcement GET — 창 열림 확인 후 복원 우선 판정.

## 창 중 소유자 활동 (TOCTOU)

1. **12:51:15Z** 소유자(wintrover)가 `workstream/s2c-standalone-bundle-observation` push + PR #24 개설
   (본 클론 12:43Z 이후·창 개시 6분 후). PR #24 필수 워크플로 2종(admission-gate·landing-integrity)은
   12:52:20Z **success 완료**(B2-Sweep post-sweep-new-generation.txt 관측) — Actions 비활성에도
   이미 발화한 run이 완료된 것으로 관측됨.
2. spec "재클론 후 재개" 실질 이행: 13:05Z fresh 재클론에 신규 ref 포함·재작성·commit-map 갱신·전수 재검증.
3. **15:35:56Z PR #24 main 병합** (merge commit `a0d9c598901c70a37c995c8d9a036836a27c41f3`,
   parents `2c48285d`+`8058d18f`) — main ruleset 비활성화(15:35:10Z) **46초 후** 자동 발화
   (auto-merge/mergeability 폴링 추정 — 비활성화 직후 병합 가능 상태가 된 것이 트리거).
4. **15:38:05Z force-push가 병합 커밋 a0d9c59를 대체** — parents 구성(병합 커밋 단독, 추가 고유 커밋 0)으로
   콘텐츠 무손실 확인: s2c 콘텐츠는 재작성 브랜치 `08c37b43`에 보존. **PR #24 재착지 필요** (신규 PR 경로 —
   재작성 콘텐츠에 대한 체크 재실행 동반, 소유자 판정 대기).
5. 교훈(규칙화 후보): ruleset 비활성화 직전 "병합 대기 PR/auto-merge 등록" 관측이 선행되어야 함.

## ruleset 비상창 (최소 무효화 → 즉시 복원)

정본 쓰기 경로 실측: **REST PUT(전체 본문) 성공** — `github_ruleset_api_quirks.md` Q1 "측정 경계"(PUT 미실측) 해소.
차단 실측: repo main 무효화 후에도 org required workflow 2종이 push 차단 → 총 3종 무효화 필요
(E2 4종 대비 1종 감소 — cas-probe 대상 없음).

| ruleset | node_id | 무효화 | 복원 | 백업 sha256 |
|---|---|---|---|---|
| repo 26702792 "main" | `RRS_lACqUmVwb3NvdG9yec5WVHkJzgGXc8g` | 15:35:10Z PUT disabled (readback 관측) | 15:42:36Z PUT 원본 JSON → GET readback **전 필드 대조 diff: updated_at 1필드만** (PUT 부수 시각 필드, 불가피) | `a387baf2f98bc4d8e41863426acd633c8a7fbd789708f0a0e5077df78eba6b34` |
| org 25218071 "axiom-admission-gate" | `RRS_lACkVXNlcs4P_cG4zgGAzBc` | 15:37:03Z PUT disabled (readback 관측) | 15:42:37Z PUT 원본 → readback 동 상동 | `1441d544bb81424aca6555e7937d6403e922eda60b232a9e5c667bea3b2164ea` |
| org 23943917 "landing-integrity" | `RRS_lACkVXNlcs4P_cG4zgFtWu0` | 15:37:03Z PUT disabled (readback 관측) | 15:42:38Z PUT 원본 → readback 동 상동 | `97f871f8af47bcd3ef3a2c4374de0b8d38fd8b2d2dd5dee677f7f9b35e04f806` |

- 미무효화 유지: repo 26702920 "cas-probe-scratch"(`0b4661f3ea9f66e67b6056d7ab257fcd5846d312c0b7088ad54230a34b6d488c`)·
  26702960 "execution-surface-create"(`0ee5446725db49f2ffe36157e67b2f47f497d10d483906c431951623b120522e`)·
  26702965 "artifact-hygiene"(`a6742781cedefd43bd26ae6349db9d7630dc6d88c05933286e2c8986acc6fb62`) — 백업 확보 후 무동작.
- GitHub 자체 감사추적 관측: `GET …/rulesets/{id}/history` — 무효화·복원 시각과 일치하는 version entries
  (repo 56836096/56836456 · org 56836157/56836458 등) 확인.
- 사유: 재작성 세대 전환의 force-push는 필수 워크플로·merge queue·PR 필수 규칙과 구조적으로 양립 불가 —
  E2 §"Force-Push 및 동결창" 선례 절차.

## force-push (15:38:05Z)

```
+ 2c48285d…→df378f60… main (forced update)        # TOCTOU: 실제 old=a0d9c59(#24 병합, 상기 참조)
* [new branch] workstream/s2c-standalone-bundle-observation → 08c37b43  # 로컬 관점 new; 원격 기존 ref 대체
- [deleted] axiom/certificates · axiom/evidence-cas  # 활성 mint 레저 — cold-start 재기동 설계(ledger_side_ref.nim createLedgerRoot)
```

- LFS: pre-push 스무지로 재작성 포인터 대상 객체 1종(10MB) 업로드 관측 (구 LFS 객체 purge는 Support 티켓 대상).

## 산물 (사적 캐시 — repo 커밋 금지)

- `pre-rewrite.bundle`(20,230,160B) · `pre-rewrite-refs.txt` · `commit-map`(168행) · `ref-map` ·
  `first-changed-commits.txt` · `commit-map.run1`(1차 폐기 세대 참조) · `replace-text-extended.txt` ·
  `gitleaks-run2-firstpass.json`(533 findings — Phase 6 재판정 대상) · `ruleset-backup/*.json` ·
  `phase3-d-failure-evidence.txt` · `window-state.log`

## 잔여·후속

- **PR #24 재착지** (신규 PR 경로 — 상기) · refs/pull/*/head 구세대 잔존 = Support 티켓(Lane B2) ·
  B2-Sweep 보류 삭제(구세대 CI 증거): runs 42482254027·42482253969 + artifacts 13618350332·13618226630·
  13618132598·13617743924·13617684449 + cache 10191764811 — Actions 재활성화 후 신세대 체크 관측 시점에 삭제.
- Phase 5 핀 회전: `938a49e→6104b249` commit-map 값으로 admission-gate-v2.yml 6핀·parse-probe.yml 3핀
  (3fafce5a 선재 dangling → 신규 루트 수렴)·org ruleset 25218071 workflow sha 회전·TWS closure 핀·bsec MANIFEST 재봉인.
- Phase 6 최종 검증: fresh 재클론 4종 재검증·gitleaks 전체 재판정(신규 finding 0)·ls-remote 구 SHA 잔존 0.
- filter-repo quirk 문서화: `docs/spec/git_filter_repo_quirks.md` (본 커밋에 동봉).

## Phase 5 실행 — 핀 회전 (2026-11-08T16:0xZ)

- **.github callee 핀 9개 회전**: 직접 push는 `.github` 자체 ruleset의 필수 체크
  `pin-promotion-gate (DEBT#473)`에 거부(예상 폴백 경로) → PR #262
  (`rotation/laneb-clean-origin-root`)로 전환 — admission-gate-v2.yml 6핀
  (setup-axiom-toolchain·admission-check×2·certificate-mint×2·runner-pool-acceptance)·
  parse-probe.yml 3핀(선재 dangling 3fafce5a 포함)을 전부
  `@6104b249c14c50c183dd54a428168b29a9561f10`(commit-map 루트 신값)로 교체.
  pin-promotion-gate **pass(13s)** → **MERGED** `1eed0a482d370a77a6724b73ab7b484b6cddcff4`
  (2026-11-08T16:07:26Z). E2 PR #258 선례와 동일 경로.
- **org ruleset 25218071 게이트 핀 회전**: 백업 상동 페이로드에서 workflows[0].sha만
  `ca183990…`→`1eed0a48…`로 변경해 PUT(유일 의미 차이 1행 — diff로 기계 확인) →
  GET readback: sha `1eed0a48…`·enforcement **active**·do_not_enforce_on_create **false**·
  conditions(refs/heads/main + Axiom) 불변.
- **TWS closure 핀 대조 — 무동작 PASS**: `config/trusted_writer_set.json`의
  `trustedCheckerTreeClosure` 885 항목 전수가 재작성 트리 HEAD의 blob sha와
  **885/885 일치**(불일치 0·결측 0). `trustedAdmissionWorkflowSha`
  `38ceca69…` = 현 `.github/workflows/admission-check.yml` blob sha 일치. 치환된
  클로저 파일이 없어 재결속(reanchor_pin)은 필요 없음 — spec 예상과 달리 무동작.
- **bsec MANIFEST — 재봉인 무동작 PASS**: MANIFEST 3891행 중 file 128·archive 12행의
  sha256 전수 대조 **140/140 일치**(불일치 0). 주체 고정 커밋 클론
  (status-im/nim-toml-serialization@4aa8e222)으로
  `SUBJECT_REPO=… bash bsec/replay.sh verify` → file 128·아카이브 12+멤버 3733·
  주체 blob 12·대장 체인(84 events/82 lineages) 전수 검증 —
  **`VERIFY RESULT: OK`**. E2 cutover와 달리 Lane B 치환은 bsec MANIFEST 도메인
  파일에 도달하지 않았으므로 재봉인 불필요.
- **PR #25 게이트 재실행**: required-workflow rerun은 403 금지(E2 관측) → 본 커밋
  (Phase 5 실행 관측 추가)의 push가 `synchronize` 이벤트로 admission-gate를 재실행.

## 사후 추기 (post-window addendum) — 창 종료(15:54:15Z) 이후 관측 사건

> 이 단락은 비상창 폐쇄 **이후** 관측된 사건들의 기록이다(관측 공백 원칙: 아래 관측은 창 내
> 실시간 관측이 아니며 창 닫은 뒤 원격 상태 관측으로 확정된 사실이다).

- **PR #25 랜딩**: 체크 전량 pass(`verdict / admission-check` 포함 — 회전된 게이트 핀 동작
  증명) → merge queue 경유 **MERGED** `66faafd9d36b5e092fd5d9fc0f3fe7be22d13269`
  (2026-11-08T16:36:43Z). 본 감사기록(E7)은 이 커밋으로 main에 도달 가능.

### 사건 ① — PR #24 TOCTIU 병합·고아화 → 재랜딩 복구

- **관측**: Actions 재활성(15:54:15Z) 직전 창 내, ruleset 최소 무효화(15:35:10Z) 46초 후
  PR #24가 **구 head `8058d18f`** 기준으로 15:35:56Z에 merge(merge 커밋 `a0d9c598…`).
  15:38:05Z main force-push(`2c48285d→df378f60`, 실 old=a0d9c598)가 이 병합 커밋을
  대체 — `a0d9c598`은 main에서 도달 불가(고아). PR #24 표시는 MERGED지만 **변경사항은
  main에 부재**; s2c 재작성 브랜치 `08c37b43`(commit-map `8058d18f→08c37b43`)에
  무손실 보존.
- **복구**: PR #26(`workstream/s2c-standalone-bundle-observation` → main)으로 재랜딩 —
  diff는 문서 1종(+188행, `docs/evidence/s2c_standalone_bundle_observation_2026-11-08.md`)
  ·경로 분류 PRODUCT(trustSurface·CODEOWNERS 비접촉) → auto-merge(normal) 경로.

### 사건 ② — hooks-usercfg 낡은 클론 재유입 → 수리 (2026-11-08T16:38Z)

- **관측**: 소유자의 낡은(재작성 전) 로컬에서 `workstream/hooks-usercfg`가 push됨 —
  커밋 `65ace234…` "fix(hooks): skip user cfg in pre-push genDepend capture (machine
  independence)", 부모 = `2c48285d`(구 main). 이 ref가 **구 이력 전체(938a49e 포함)를
  다시 도달 가능하게 노출**.
- **수리**: 격리 클론에서 `65ace234`를 재작성 main `df378f60` 위에 cherry-pick —
  패치는 원본과 **바이트 동일**(diff 검증), author 보존. 결과 `76eda8f2…`.
  전 트리 Deny 검증: replace-text(-extended) 26패턴 + 침소 5종 전 revs(binary-inclusive)
  **0**·pathspec 제거 경로 **0**·구세대 SHA(commit-map old열 교집합) **0** →
  force-push(무효화 불필요 — main 외 브랜치는 push-target 규칙만 적용, 통과).
  Readback: 원격 `workstream/hooks-usercfg` = `76eda8f2…`.
- **재발 방지**: 소유자 낡은 클론 push 금지 안내는 소유자 통지 채널로 발송됨(운영 기록).

### 사건 ③ — 잔여 구세대 run·artifact·cache 소탕 (2026-11-08T16:4xZ)

- **경계 확정**: B2-Sweep 완료 13:09Z(905건 삭제) · 본 재작성 main force-push
  **15:38:05Z**(본 문서 §force-push). 13:09Z~15:38:05Z 생성 run은 전부 구 코드 기반.
- **열거**: 해당 구간 생성 run 잔존 **정확히 2건** — `42482254027`(admission-gate)·
  `42482253969`(landing-integrity), 전부 PR #24·구 head `8058d18f`·12:52:20Z 생성.
  소속 artifact 5건(`13618350332`·`13618226630`·`13618132598`·`13617743924`·
  `13617684449` — run 42482254027 소속) + cache 1건(`10191764811`,
  `refs/pull/24/merge`).
- **삭제 → 재열거**: artifact 5 + run 2 + cache 1 DELETE → 재열거 잔존 **0·0·0**
  (신세대 run 60건은 전부 force-push 이후 생성 — 보존).
