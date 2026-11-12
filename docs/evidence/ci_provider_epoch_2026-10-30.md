# CI 공급자 에포크 — Ubicloud 전환·OVH/GARM 철거·철거 후 수용 (2026-10-30)

> 문서 성격: 실행 증거 기록(docs/evidence — §5 SSOT 표). CI 러너 에포크
> generation 11(OVH/GARM)→12(Ubicloud) 전환과, 그에 따른 OVH·GARM·Northflank
> 철거(teardown) 인프라의 비활성화·삭제, 그리고 철거 후 required 체크 5종이
> Ubicloud 러너에서 success로 병합된 수용(acceptance) 관측의 기록이다.
> 선행 문서: `ci_provider_failover_2026-10-23.md`(Ubicloud failover Stage 0–3),
> `ci_provider_return_path_acceptance_2026-10-24.md`(복귀 경로·canary 계약),
> `ci_provider_monthly_trial_2026-10-24.md`(월간 trial 창),
> `ci_runner_bootstrap_disable_updates_2026-10-27.md`(GARM scaleset 2
> `ci-axiom-x64`·OVH SGP1), `ci_phase2_runner_bootstrap_decomposition_2026-10-28.md`.
> quirk 본문: `docs/spec/ci_provider_failover_quirks.md`.
>
> 측정 주체 구분: **[session]** = 2026-10-30 에포크 운영 세션에서 `gh api`/
> `garm-cli`/OVH·Northflank API로 관측해 인계된 값(명령·응답 원문은 운영 세션
> 기록 `agents/agent-18/wire.jsonl`). **[live]** = 본 문서 작성 세션에서
> `gh api`로 재관측한 값. **[derived]** = 위 관측에서 도출된 판정.
> 모든 시각은 UTC.

## 1. 목적과 종결 판정 (Ultimate purpose · Terminal outcome)

**목적(1문장)**: GARM 러너 상실로 required check 2건이 취소된 실행 평면을
Ubicloud로 전환하고(generation 12), 병합 계약에 더 이상 필요 없는 OVH·GARM·
Northflank 철거 인프라를 비활성화·삭제하며, 철거 후에도 required 체크 5종이
Ubicloud 러너에서 success로 병합됨을 관측해 철거의 정당성과 실행 평면 무손상을
닫는다.

**Terminal outcome** [live 재관측 포함]:

- `CI_RUNNER_MAP` generation 12 — `mode=ubicloud, state=UBICLOUD_ACTIVE,
  fallback_provider=ubicloud`. PATCH(07:46:09Z) 이후 라우터 무쓰기, 본 문서
  작성 시점 GET 재관측(`updated_at 2026-10-30T07:46:10Z` 유지)까지 무변경.
- 철거 완료(09:06:09Z): GARM scaleset 2·1 disabled→deleted(컨트롤러 서비스는
  생존), OVH 인스턴스 0·스냅샷 0·OpenStack 사용자 0, Northflank
  axiom-garm 서비스·garm-data 볼륨 삭제(axiom-control-runner 보존).
- 철거 후 수용: 검증 병합 2건(§2.6 PR #1120·#1121)의 merge_group 필수 체크
  5/5가 전부 `labels=["ubicloud-standard-2"]`·`runner_group_id=1`·
  success·runner_id>0 — **Ubicloud 실행 평면의 철거 후 acceptance**.
- 병합 권위·계약 무변경: ruleset 20303214(required 5종·merge queue)와
  철거 전 동일 [live: id 20303214, name `main`, enforcement `active`].

## 2. 타임라인 (2026-10-30, 전 항목 UTC) [session — 별도 표기 제외]

### 2.1 Freeze (07:43:54Z) — 전환 직전 상태

- `CI_RUNNER_MAP`: `mode=ovh, state=OVH_ACTIVE, generation=11,
  x64=slim=ci-axiom-x64, fallback_provider=ovh`.
- ruleset **20303214** active. runner group **7**
  (`axiom-control-northflank`) online. 워크플로 잡 스냅샷: queued **10** /
  in_progress **2**.

### 2.2 취소 사건 — GARM 러너 상실 (canceller UNRESOLVED)

- PR #1120 필수 체크 2건이 GARM 러너에서 사망:
  - `debt-registry-gate` — **07:39:30Z** 취소(runner
    `garm-sp4p4hjaz63o`).
  - `axiom-operational-slice` — **07:43:41Z** 스텝 취소 → 잡 failure(runner
    `garm-bfhleuvritvj`).
- org 감사로그에서 취소 액션 **0건**(API 미기록) — canceller **UNRESOLVED**.
- 정황: GARM elastic 루프의 러너 churn — 당일 `axiom-ci-elastic[bot]` 등록
  **204회**(00:04–08:14Z). **[derived]** 러너 churn에 따른 러너 상실이
  가장 유력하나 **강한 정황일 뿐 직접 증명은 불가**하다 — 이 에포크 기록은
  canceller를 특정하지 않는다.

### 2.3 PATCH — generation 12 전환 (07:46:09Z)

- `CI_RUNNER_MAP` → `mode=ubicloud, state=UBICLOUD_ACTIVE, generation=12,
  x64=slim=ubicloud-standard-2, arm64=ubicloud-standard-2-arm,
  fallback_provider=ubicloud, last_transition_reason=BOOTSTRAP,
  last_transition_at=2026-10-30T07:46:09Z` — 기존 필드 보존
  (`last_ghec_success_period=2026-09` 등).
- 쓰기: HTTP **204**, 직후 GET 바이트 비교 **EXACT_MATCH**.
- 사전 검증 [session, 오프라인]: 라우터 jq 스키마 검증 PASS, 출하 블록의
  오프라인 정적 재생 — GHEC 차단 상태의 전환 타깃 =
  `UBICLOUD_ACTIVE`+`ubicloud` 라벨, 라우터에 OVH 전환 경로가 부재함을 확인.
- **[derived]** OVH scaleset이 이 시점에 이미 계약 실행 평면에서 퇴역했음이
  스키마와 정적 재생 양쪽에서 확인됐다 — 전환은 부트스트랩(BOOTSTRAP reason)
  이지 failover 아니다.

### 2.4 제어평면 — 라우터 run 2건 success, 이후 무쓰기

- 라우터 run **41022103325**(created 07:46:03Z)·**41022524953**(07:50:14Z)
  모두 success — `axiom-control-northflank` / group 7에서 실행, 로그
  `mode=ubicloud state=UBICLOUD_ACTIVE fallback=ubicloud generation=12`.
  [live] 두 run 재관측: `event=workflow_run, conclusion=success, created`
  일치.
- 이후 라우터의 변수 쓰기 0건 — `CI_RUNNER_MAP` 안정 [live: `updated_at
  2026-10-30T07:46:10Z` 유지].

### 2.5 취소 2 run 재실행 — Ubicloud 실행 평면 첫 직접 증거 (08:05Z)

- `rerun-failed-jobs` → attempt 2가 `labels=["ubicloud-standard-2"]`·
  `runner_group_id=1`·runner_id **5353**·**5354**로 실행, 둘 다 success
  (08:13:06Z / 08:08:55Z).
- **[derived]** §2.2에서 GARM 러너로 사망한 동일 체크가 재실행만으로 Ubicloud
  러너에서 success — 장애 원인이 코드가 아니라 러너 평면이었음의 직접 관측.

### 2.6 검증 병합 2건 — merge_group 필수 체크 5/5 Ubicloud (철거 전 착지)

- **PR #1120**(docs/spec-fallback-default-fix) MERGED — merge commit
  `a4b4d42a91564503ceb294cc1e939187176daa7b`, **08:34:03Z**. merge_group
  (branch `gh-readonly-queue/main/pr-1120-de9c9e2`) 필수 체크 **5/5** 전부
  success·`ubicloud-standard-2`·group 1:

  | 필수 체크 | run id | runner_id |
  |---|---|---|
  | admission-check | 41025127537 | 5375 |
  | bsec-integrity | 41025127250 | 5355 |
  | debt-registry-gate | 41025127218 | 5363 |
  | generation-acceptance | 41025127220 | 5356 |
  | axiom-operational-slice | 41025127285 | 5362 |

  비필수(landing-integrity, observer-manifest-consistency,
  probe-merge-queue)도 success.
- **PR #1121**(docs/app-install-inventory) MERGED — merge commit
  `e24c27e6b3e9914e4508936642754dbce381040d`, **08:56:32Z**, 부모 =
  `a4b4d42` + PR head(순차 그래프). merge_group(`pr-1121-a4b4d42`) 필수
  체크 **5/5** 전부 success·`ubicloud-standard-2`·group 1:

  | 필수 체크 | run id | runner_id |
  |---|---|---|
  | admission-check | 41027830781 | 5400 |
  | bsec-integrity | 41027830569 | 5381 |
  | debt-registry-gate | 41027830603 | 5384 |
  | generation-acceptance | 41027830635 | 5380 |
  | axiom-operational-slice | 41027830708 | 5382 |

- [live] 두 PR 재관측: `MERGED` + mergedAt·mergeCommit 일치.
- **[derived]** §2.5의 rerun과 §2.6의 merge_group 10잡(runner_id
  5353–5400)이 Ubicloud JIT 러너 패턴(`runner_group_id=1`·`ubicloud-*`
  라벨·runner_id>0)을 공유한다 — merge queue의 병합 admission이 이미
  Ubicloud 실행에 의존하는 상태로 진입했다.

### 2.7 철거 완료 (09:06:09Z)

순서대로: drain 게이트 4개 관측 통과(§3.1) → GARM scaleset 비활성화(§3.2) →
러너 0 재확인 → scaleset 삭제(§3.2) → OVH 자원 정리(§3.3) → Northflank
자원 정리(§3.4). 상세는 §3.

### 2.8 라우터 — 철거 직후 발화 무손상

- 라우터 run **#979** **09:05:22Z** success — GARM·OVH 삭제 직후의 발화.
- 철거 후 신규 라우터 실행은 cron(`7,37 * * * *`) 대기(10:07Z 예상)이며,
  이 문서의 병합이 만드는 main push 트리거로도 발화한다 — 발화 시
  `mode=ubicloud state=UBICLOUD_ACTIVE fallback=ubicloud generation=12`
  유지가 철거 후 상태 무손상의 관측점이다(본 문서 PR의 병합 관측에 귀속).

## 3. 철거 증거 — 비활성화/삭제 구분과 전·후 [session]

> 구분 규약: **disabled** = 존재 유지·기능 정지(reversible), **deleted** =
> 존재 소멸(irreversible), **preserved** = 의도 보존. 각 삭제는 개별 API
> 호출 + GET 재확인으로 닫았고, 응답 원문은 운영 세션 기록
> (`agents/agent-18/wire.jsonl`)에 보존돼 있다.

### 3.1 drain 게이트 4개 — 삭제 전 관측 (모두 통과)

1. 구형 라벨(`ci-axiom-x64` 등 OVH 라벨)의 queued/in_progress 잡 = **0**.
2. merge_group in_progress = **0**.
3. GARM 러너 = **0**.
4. GitHub 등록 구형 라벨 러너 = **0**.

### 3.2 GARM — scaleset 2·1: disabled → deleted (서비스는 생존)

| 대상 | 조치 | 구분 | 비고 |
|---|---|---|---|
| GARM scaleset **2** | `garm-cli scaleset update <id> --enabled=false --name <name>` | **disabled** | 러너 0 재확인 후 delete |
| GARM scaleset **1** | 〃 | **disabled** → **deleted** | 〃 |
| scaleset 2·1 | `garm-cli scaleset delete` | **deleted** | GARM 서비스 생존 중 응답 기록 |
| GARM 컨트롤러 서비스 + `garm-data` 데이터 | — | **preserved**(§3.4에서 삭제로 확정) | §3.4 참조 |

- scaleset 2는 `ci-axiom-x64` 라벨의 x64 실행 평면이었다
  (`ci_runner_bootstrap_disable_updates_2026-10-27.md` §1 대상과 동일).
- **[derived]** 컨트롤러 서비스 자체는 철거 후 재검증에서 DNS·API 양쪽으로
  부재 관측(§4) — scaleset 삭제가 마지막 유효 기능이었다.

### 3.3 OVH — OpenStack 자원 정리

| 대상 | 조치 | 구분 | 전 | 후 |
|---|---|---|---|---|
| 스냅샷 `6e27e2b8-017c-499d-a26b-c548df89c3db` | 삭제 | **deleted** | 존재 | 0 |
| OpenStack 사용자 **899622** (`user-F2nBCS6B9MCZ`) | 삭제 | **deleted** | 존재 | 0 |
| 인스턴스 | — | 관측 결과 **0대** | — | 0 |
| SSH 키 `axiom-ci-probe` | — | **404 부재 기록** | — | 부재 |
| 공인 IP 4개 | — | **API 미관측 — PARTIAL** | — | §5 참조 |

- 공인 IP(`192.0.2.10`, `192.0.2.11` + IPv6 2개)는 floating/
  additional/extnet 조회가 전부 null, 계정 레벨 조회는 403 — API 권한으로는
  관측 불가한 **PARTIAL** 항목(§5).

### 3.4 Northflank — axiom-garm 서비스·볼륨 삭제, control-runner 보존

| 대상 | 조치 | 구분 | 비고 |
|---|---|---|---|
| 서비스 `axiom-garm` (`6adf73faf50ee4db04e81640`) | 개별 삭제 + GET 재확인 | **deleted** | GARM 컨트롤러 호스트 |
| 볼륨 `garm-data` (`6adf6e46f4483f99ed3ec6cc`) | 개별 삭제 + GET 재확인 | **deleted** | GARM DB 볼륨 |
| 서비스 `axiom-control-runner` (`6adecb145a0fd9c9bfaa2ea3`) | — | **preserved** | 제어평면 러너(group 7) — build SUCCESS·deployment COMPLETED 유지 |

## 4. 철거 후 재검증 (09:14:01Z 기준 관측) [session]

- 구형 라벨 활성 잡 재유입 = **0**(09:14:01Z).
- §2.1 시점의 in_progress 2 run — 모두 **success로 종료**(취소·유실 0).
- runner group 7 `axiom-control-northflank` online, `busy=false`.
- GitHub App **4879411**(`axiom-ci-elastic`) 설치 존재 — 잔류 위험 §6.1.
- GARM 공개 API **DNS 실패**(curl exit 6, 09:08:04Z), `garm-cli` **no such
  host**(09:08:15Z) — 컨트롤러 완전 부재.
- Northflank: 볼륨 0, 서비스는 `axiom-control-runner`만 존재(build SUCCESS·
  deployment COMPLETED).
- OVH: 스냅샷 0·사용자 0.
- 라우터 run #979(09:05:22Z) success — 철거 직후에도 제어평면 발화 무손상
  (§2.8).
- **[derived]** 철거는 실행·제어·관측 세 평면 모두에서 "required 체크가
  Ubicloud만으로 self-contained히 통과하는 상태"로 닫혔다 — §2.6의 수용이
  그 기계적 증거다.

## 5. PARTIAL 항목 — API 미관측 [session]

- **OVH 공인 IP 4개**(IPv4 `192.0.2.10`, `192.0.2.11` + IPv6 2개):
  floating IP·additional IP·extnet 조회가 전부 null이고 계정 레벨 조회는
  403이라 API로 존재·해제를 관측할 수 없다. **PARTIAL — 인간 콘솔 확인이
  후속 과제**(§6.7 비용 항목과 결합).
- **Northflank 실제 청구액**: Billing API가 무료 플랜에서 403 — 콘솔 인간
  확인 필요(§6.6).

## 6. 잔류 위험 (7건 — 에포크 종결 시점 기준)

1. **App 4879411 권한 공유**: `axiom-control-runner`의 `RUNNER_APP_ID=
   4879411`이 GARM credential(`axiom-ci-elastic`)과 동일 App이다 →
   `organization_self_hosted_runners:write` 축소 시 제어 Runner 재등록이
   붕괴한다. 권한 축소는 이번 에포크에서 **보류**. 후속: 등록 App 분리.
   `contents:write`(Landing)·`ubicloud-managed-runners`(387324) 권한은
   **유지 필수**.
2. **Ubicloud 지출 상한 부재** — 사용량 과금, 월 $2.5 크레딧. 상한 설정은
   후속 과제.
3. **closure-watcher의 GARM 게스트 진단 참조 잔존**(dormant) —
   `.github/workflows/closure-watcher.yml:782,837–846`. GARM이 철거됐으므로
   해당 진단 분기는 도달하지 않는다(발화 시 진단만 상실, 게이트 영향 없음).
4. **`PROVIDER_POLICY`의 `ovh` 행 잔존**(dormant, 소스 불변) —
   `.github/workflows/ci-provider-router.yml:264`. 실제 OVH 인프라는
   삭제됐지만 정적 정책 표에는 열거돼 있다(`.github/**` FROZEN 소스 — 수정은
   별도 계약 경로).
5. **2026-11-01–03 월간 trial 창**: 라우터가 `mode→ghec` 자동 복귀 시도를 할
   수 있다 — `ci_provider_return_path_acceptance_2026-10-24.md` §8의 설계된
   동작이며, 전환 실패가 아니다. GHEC 차단이 유지되는 한 canary는 0-step
   실패 후 Ubicloud를 유지한다.
6. **Northflank 실제 청구액** — Billing API 무료 플랜 403으로 API 관측
   불가. 콘솔 인간 확인 필요(§5).
7. **비용 전후**: 철거 전 예상 ~**$6.10/월**(axiom-garm $5.40 + 볼륨
   $0.70) → 철거 후 **$5.40/월**(axiom-control-runner). Sandbox $20 무료
   크레딧 수용 안이므로 현금 지출은 양측 **$0**. 공인 IP 4개(§5)는 API
   미관측 — PARTIAL, 인간 콘솔 확인 후속.

## 7. 기록 사실

- **ruleset 20303214** [live: name `main`, enforcement `active`]:
  `required_status_checks`에 필수 체크 5종(admission-check, bsec-integrity,
  debt-registry-gate, generation-acceptance, axiom-operational-slice) 명시,
  merge_queue(MERGE·ALLGREEN·`max_entries_to_build=2`·
  `max_entries_to_merge=1`), pull_request(merge-only·승인 0·unattributed
  추가 승인), deletion·non_fast_forward, bypass_actors 없음.
- **`gh` merge queue 등록 경로**: 이 버전의 `gh`에는 `--queue` 플래그가
  없다 — merge queue 필수 브랜치에서 `gh pr merge <N>`(플래그 없음)이 큐
  등록으로 동작함을 확인 후 사용했다(PR #1120·#1121과 본 문서 PR).
- **취소 2 run의 재발**: attempt 2에서 모두 success, 이후 재발 0건(§2.5,
  §4).
- **증거 원문 위치**: 철거 시점의 명령·응답 상세가 필요하면 운영 세션 기록
  `agents/agent-18/wire.jsonl`(세션 디렉터리
  `<user-home>/.kimi-code/sessions/wd_axiom4_a9f6347fc418/
  session_d20f5702-9764-468c-8b9f-38e564a3bdf6/agents/main/` 기준)에서
  grep해 인용할 수 있다.
- **production mutation 경계**: 이 문서의 착지 자체는 문서 1개 추가뿐이다 —
  변수(`CI_RUNNER_MAP`)·ruleset·GARM·OVH·Northflank·App 권한에 대한 변경은
  이 에포크의 운영 세션에서 완료됐고 본 PR은 그 상태를 건드리지 않는다.
