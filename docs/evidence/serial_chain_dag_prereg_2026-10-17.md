# 직렬 사슬 DAG 사전등록 — publish→verdict 스케줄링 산물 분류와 후보 A (2026-10-17)

> **종류**: 설계 사전등록 (design pre-registration) — 형식 계보: `docs/evidence/rotation_allowlist_g2_prereg_2026-10-16.md`. 본 문서는 **판정을 만들지 않는다**(Reporter) — merge-admission 판정·정책·불변식의 권위는 기존 정본(docs/spec/admission-generation.md, ADR-0022/0032, 레지스트리 규칙)에 그대로 있다.
> **등록일**: 2026-10-17 (착지 이전 고정 — no-peeking). §5 게이트는 관측 전 고정이며 사후 조정 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.
> **측정 원문**: merge_group 런 38925131342 / 38913175446 / 38891209338 (모두 success, 2026-10-16)의 runs/jobs/steps API + 조직 호출부 라이브 판독본(`/tmp/admission-gate-v2-live.yml` — 컨트롤러 저장소 Archright/.github 소속 파일로 Axiom 체크아웃 밖) + [docs/evidence/d3_gap_decomposition_2026-10-17.md](d3_gap_decomposition_2026-10-17.md)(n=8 표본).
> **본 PR의 범위**: docs+data 전용 — 본 PR은 워크플로·코드 변경을 일절 수반하지 않는다. §3의 구현(후보 A)은 본 등록에 구속되는 **별도 컨트롤러 PR**에서만 수행된다.

---

## 1. 측정 기준 (post-Lever-B)

**MG post-lane 직렬 꼬리(레인 완료 후 attest 소비자→mint-prepare→mint-publish→verdict→롤업)**: 중앙값 **291s(254–331, n=8)** — [d3_gap_decomposition_2026-10-17.md:23](d3_gap_decomposition_2026-10-17.md). 갭 성분 중 단일 최대이며 갭 전체보다 크다(같은 문서 §2-1).

**3-run step-API 상세** (runs 38925131342 / 38913175446 / 38891209338 — 중앙값, 초):

| 단계 | 총 | envelope (환경 셋업) | authority (본질) |
|---|---:|---|---|
| attest 소비자 (`attest / admission-check`) | 116 | 62 — set-up 1, checkout B 3, toolchain 52 (47/52/69 산포), checkout H 2, base dl 3, verify 0 | J3 인도 13–19 (nimcache 병합·업로드 — 가속) + 30 (purity 4, identity 16, witness 10, uploads 3) |
| mint-prepare | 32 | 22 — toolchain runtime-scope 17 | 8 — witness 인출 6, cert 업로드 2 |
| mint-publish | 49 | 20 — toolchain 16 | 28 — 원장 append P7+P7b+P7c+P7c-x = 24–25 |
| verdict | 43 | 14 — libpcre 6, base dl 2 | 27 — predicate 24–26 |
| 롤업 (`admission-check`) | 1–2 | — | — |

잡 간 갭 3–7s ×4 = 20–26s/run (스케줄러 + wrapper→callee 2단 큐). 꼬리 합계 3런: 260 / 247 / 275 (중앙값 260) — D3 대표본(n=8) 291과 일관.

**교차 검증 (2026-10-17 재판독)**: run 38925131342 잡 타임라인 — attest 소비자 15:42:57→15:44:55, mint-prepare 15:44:58→15:45:33, mint-publish 15:45:36→15:46:25, verdict 15:46:29→15:47:12, 롤업 15:47:15→15:47:20. 꼬리 263s, **5단계 완전 직렬** 관측 — 상기 분해와 정합.

## 2. 현재 DAG + 엣지 분류 표

```
closure-deriver(91) ──────────────┬──────────────┐
attest ──[lane0 351 / lane1 309]──┤              │
  └ attest 소비자(116)            │              │
mint-prepare(32) ── mint-publish(49) ── verdict(43) ── admission-check 롤업(1–2)
gateway: select(77) ── ci-bootstrap(106) ──────────┘ (mint-publish에 P6 인도)
```

(serial chain만 — lane·gateway·closure 병렬 가지 생략. 괄호 = 3-run 중앙값 초.)

| 엣지 | 소비물 | 생산자 내 업로드 위치 | 분류 |
|---|---|---|---|
| attest → mint-prepare | witness 번들 `admission-check-<H>-<attempt>` (witness.json+sha256) + `admission-check-base-artifacts`(bin/ax) | witness = attest 잡의 **마지막 실행 스텝** (admission-check.yml:2367-2400 — 완료 T-6..13s 생산; 커널 :1650-1671) | **진짜** (needs 엣지는 잡 경계; 잡 내 중복 ≈ 0) |
| mint-prepare → mint-publish | `subject-certificate-<attempt>` (certificate-mint.yml:1207-1215 업로드 — prepare 마지막 스텝) | prepare step 15/15, 잡 종료 1–2s 전 | **진짜** (attest의 evidence/judgment 레코드도 전이적으로 소비) |
| mint-publish → verdict | **artifact 레벨에서 NOTHING.** verdict의 `--cert` 다운로드(admission-check.yml:1809-1821)는 **prepare의 업로드**를 겨냥(`subject-certificate-<runAttempt>`); P7 commit_meta는 cert+gateway만 참조; 원장은 폴백 소스 (ADR-0022 §D5-3 — :1792-1807 주석) | — | **스케줄링 산물** / 신뢰-순서 포즈 (본 등록의 대상) |
| verdict → 롤업 | 잡 결과만 (needs.X.result) | — | **진짜 + 정체성 하중** — 접두사 없는 필수 체크 컨텍스트 `admission-check`(repo ruleset 20303214)는 호출자 수준 잡에서만 발생 (callee 잡은 "verdict / admission-check"로 렌더) |
| lanes → attest 소비자 | `go-judgment-lane-{0,1}-<H>-<attempt>` fail-closed (admission-check.yml:1054-1065) | lane 종료 | 진짜 — 구속 엣지 = lane-0 (351s) |
| gateway → mint-publish | P6 jobs-API 결론 + 시간 인과 | — | 계약상 진짜 (레이스 수정 run 37569755722); 이 3런에선 비구속 (gateway가 3–7분 먼저 종료) |
| closure-deriver → verdict/gateway | `derived-closure` (dl :1778-1790) + V-H 레이스 순서 | deriver 종료 | 진짜 순서; 이 3런에선 비구속 |

**분류의 요점**: publish→verdict가 유일한 무소비 직렬 엣지다. publish(49s)가 verdict(43s)의 입력을 하나도 주지 않으므로, 이 엣지는 artifact 인과가 아니라 callee 주석(admission-check.yml:1810-1813 — "It must sit AFTER the caller's mint-publish job")이 서술하는 **신뢰-순서 포즈**의 스케줄링 구현이다. 인증서 자체는 prepare 직후(= verdict 시작 전이라면 언제든) 존재한다.

## 3. 선택 슬라이스 — 후보 A 사양

**변경 (단일)**: org 호출부 `Archright/.github` `admission-gate-v2.yml`의 `verdict` 잡 `needs`에서 `mint-publish`를 제거한다 — `[mint-publish, closure-deriver, anchor-resolve]`(라이브 판독본 L645) → **`[mint-prepare, closure-deriver, anchor-resolve]`**.

- **호출부 단독** — callee(admission-check.yml@64f78ab7, certificate-mint.yml@9aaee76f0, runner-pool-acceptance.yml@ba773d0631) 재핀 **불필요**.
- **양 venue 자동 적용** — PR preflight의 D1 쌍둥이 직렬 사슬도 동일하게 수축한다 (호출부 파일이 양 venue 공유).
- **예상 효과 — 예측치로만 기록한다** (관측 전 확정 수치 아님; 판정은 §5 게이트가 한다): 꼬리 ~43–55s 절감 (publish 49 + 잡 갭 ~6), D3 −~50s. §1 중앙값 291s 대비 ~15–19%.
- **경화 옵션 (별도, A에 포함하지 않는다)**: verdict의 cert 다운로드(admission-check.yml:1809)에 DEBT#474 방식 bounded retry 적용 — `fetch_bounded` 계약(max 4 attempts, 고정 backoff 5/10/20s, fetch-scoped; data/debt_registry.json DEBT#474 resolutionNote). callee 변경이므로 재핀(promotion)을 수반한다 — A와 **다른 슬라이스**로 수행한다.
- **감시 항목**: `--cert` fetch는 `continue-on-error`(:1818)이고 폴백 소스는 publish가 append하는 원장(P7)이다. publish ∥ verdict가 되면 predicate 도달 시점에 P7 append(24–25s)가 미완료일 수 있다 — **원장 폴백 경합**. 이 경합으로 폴백이 비면 결과는 red다: 무결성이 아니라 **가용성의 fail-closed 손실**이며, green 위장(극장)이 아니다. §5 (iii)의 귀인 판정 대상이다.

## 4. 불변식 (MUST NOT — 후보 A 구현이 훼손하는 것 0)

1. **verdict = `ax merge --dry-run --json` exit 계약** — predicate 자체는 변경하지 않는다 (admission-check.yml:1852+; :2332-2365 fail-closed 가드).
2. **certRequired=true** — 인증서 요구 강도 불변 (`src/cli/merge_cli.nim:96` const; ADR-0032가 서술하는 계약).
3. **7-fold 롤업 ∧ RESULT_MINT_PUBLISH 포함** — 호출부 롤업 잡의 집계(needs 7잡, `if: always()`)와 `RESULT_MINT_PUBLISH`(라이브 판독본 L669, L691-692 — "skipped/cancelled/failed must block")는 불변. A의 needs 변경은 verdict 잡에만 적용되며 롤업의 7-fold는 mint-publish를 **직접** 계속 요구한다. ※ 필수 체크 `admission-check`가 호출자 롤업 잡에서만 발생한다는 정체성 사실은 롤업을 verdict에 흡수하는 후보 C의 차단 근거다 (callee 체크런은 wrapper 접두사 렌더 — ruleset 20303214 매칭 불가).
4. **P7b·P7c exactly-once** — 원장 append의 정확-한 번 의미 불변.
5. **P5·P6 게이트** — gateway 결론 게이트 불변.
6. **NO_CERT 순서 "cert exists before predicate"** ([landing_latency_cutover_2026-10-05.md:55-59](landing_latency_cutover_2026-10-05.md) — 2026-10-04, 17런 ~202분 손실) — A는 이 순서를 **강화**한다: 인증서가 prepare 뒤, 즉 현행(publish 뒤)보다 **더 이른** 시점에 존재하며 predicate는 같은 run이 발행한 인증서를 계속 읽는다.
7. **ADR-0032 venue 의미 불변** — PR preflight ≠ landing evidence; verdict leg의 venue 분기(steps.venue.outputs.venue == 'landing')와 preflight contrast 구조는 그대로다.

## 5. 사전등록 판정 게이트 (관측 전 고정 — 사후 조정 금지)

**GO = (i) ∧ (ii) ∧ (iii)**, 판정은 착지 후 **venue별(MG) ≥5회** 관측으로 한다:

- **(i) 구조 성립** — 잡 타임라인에서 `mint-publish/publish`와 `verdict/admission-check`의 실행 구간이 **겹친다**(병렬 관측; §8 jobs API). needs 변경이 실제 병렬을 만들었는지의 구조 판정이다.
- **(ii) 절감 문턱** — MG post-lane 꼬리 중앙값 절감 **> 30s**. required_min_saving 산출(등록 시점 고정): n=8 관측 범위 254–331 → range 77s, 정규 근사 d₂(n=8)=2.847 → σ̂≈27s; 판정 표본 n=5의 중앙값 표준오차 ≈ 1.253·σ̂/√5 ≈ 15.1s → 문턱 = 2×SE ≈ **30s** (잡음 바닥에서 충분히 먼 문턱). 예측치 43–55s는 이 문턱을 넘는다.
- **(iii) admission red 0** — 단 **레인(go-critical-lane) 계통으로 귀인되는 red는 본 판정에서 제외**한다(A 이전부터 존재하는 실패 양상). 레인 외 red는 §3 감시 항목(원장 폴백 경합) 여부를 판정해 귀속한다 — 경합 기인이 확인되면 그것은 A의 fail-closed 가용성 비용이며, (i)(ii) 충족과 별개로 FAIL 취급한다.

- **SLO 480s 선언은 본 게이트에 없다** — 별도 지속 관측 과제로 명시한다. ≥5회 관측은 P95 입증이 **아니다**; SLO 선언에는 더 큰 표본의 지속 관측이 필요하다.
- **FAIL 시**: frozen 세대 rollback — 컨트롤러 세대를 직전 핀으로 원복한다(docs/spec/admission-generation.md §5.7 롤백 행렬 준용; `ref: main` 복원은 금지 — 당시 SHA 값 원복).

## 6. 후속 후보 (별도 슬라이스 — 본 등록으로 승인되지 않음)

| 후보 | 절감(예측) | 전제·위험 |
|---|---|---|
| **B** — prepare+publish 통합 (certificate-mint.yml 결합 stage) | ~26–31s (중복 toolchain 16–19s + 갭 1개) | **읽기-티어 자세 상실 위험** — 통합 잡은 contents:write를 가져 prepare의 contents:read 2단 설계(certificate-mint.yml:166-193)를 깬다. 티어 분리의 사양 권위 확인이 전제다. callee 재핀 수반. A와 함께하면 꼬리 ~175–180s |
| **D′** — core_purity_gate 빌드를 attest stage→build-base-artifacts(job1)로 이관 + manifest 추가, attest toolchain scope full→runtime | ~31–50s (toolchain 47–69→16–19) | callee 변경(admission-check.yml:544-596·1002-1008·872-876) — 양 wrapper가 admission-check.yml을 핀하므로 **재핀 수반**. 판정자 빌드-사이트 이동(:577 주석 "built by job2") — C2가 B-built(레시피)를 의미하는지 권위 확인 필요 |

A+B+D′ 누적 예측 ~130–150s (양 venue; D1 쌍둥이 사슬 동일 수축). E(attest→prepare needs 제거 + bounded-poll witness)는 문서화된 no-poll 계약 위반 + fail-open 표면 신설로 기각(원 분석 §4-E). 후보 C는 §4-3의 정체성 사실로 차단.

## 7. 착지 절차 (컨트롤러 세대 승격)

A는 Axiom `config/policy/merge_admission.json` `trustSurface` 멤버가 **아니다**(trustSurface = Axiom 측 callee 워크플로) — org 호출부 변경이므로 자기참조 잠금(§4.2)이 발동하지 않는다:

1. **활성 세대 재확인 (필수, 착지 직전)** — `gh api /orgs/Archright/rulesets` 재판독. **2026-10-17 등록 시점 판독**: active 2종 — **25218071**(axiom-admission-gate)·**23943917**(landing-integrity). 25218071은 `admission-gate-v2.yml`(repository_id 1182157951) @ **`5bfc9114`** = Archright/.github **repo HEAD**(2026-10-16T06:56:09Z); 파일 마지막 변경 커밋은 `20acdf17`(06:54:11Z) — 커밋 식별자는 상이하나 그 사이 파일 변경이 0이므로 **blob 동일, 세대 드리프트 없음**(원 분석의 "pin≠head" 표기는 커밋 불일치 관측이며 본 판독으로 내용 불일치는 해소). ※ **23943917은 `ade1157`**(10-16 03:17, #225 머지) 핀으로 HEAD 대비 뒤처져 있다 — 선행 불완전 재핀 관측; A 착지의 §4.3 재핀이 같은 논리적 단위에서 이것을 수렴시킨다.
2. **컨트롤러 PR** — Archright/.github에서 verdict.needs 변경 PR을 정상 컨트롤러 큐로 착지 (자기참조 없음).
3. **§4.3 사후 ruleset 재핀 (HARD RULE)** — 컨트롤러 main HEAD 전진과 **같은 논리적 단위**에서 양 ruleset 재핀. 절차 요약: **빈 큐 확인**(Axiom merge queue·in-flight MG 0) → repo ruleset **20303214** `merge_queue.max_entries_to_build` **2→0** freeze(읽기로 관측) → 양 org ruleset **PUT**(workflows 규칙 sha = 새 controller HEAD, ref 제거; REST PUT 불성립 시 GraphQL 폴백) → **바이트 일치 readback**(sha 설정 + 그 외 규칙·조건·bypass 무변경 대조 — 관측된 readback이 완료 조건) → **해제 0→2** + readback.
4. **규범 우위** — 본 절은 요약이며 **docs/spec/admission-generation.md가 SSOT다** (§4 경로·§4.3 재핀 의무·§5 전환 통제·§5.7 롤백 행렬·§6 수용 채널 E1–E4). 불일치 시 spec이 이긴다. ruleset ID는 세대마다 로테이션된 전례(10-13 3세대 회전)가 있으므로 실행 시점 판독값이 권위를 가진다.

## 8. 재현 명령

```bash
# runs API — 대상 3런 확인 (모두 merge_group·success·2026-10-16)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100" \
  --jq '.workflow_runs[] | select(.id==38925131342 or .id==38913175446 or .id==38891209338)
        | {id, event, head_branch, created_at, conclusion}'

# jobs API — 잡 타임라인 (게이트 (i): publish ∥ verdict 겹침 관측, (ii): 꼬리 계산)
gh api repos/Archright/Axiom/actions/runs/38925131342/jobs \
  --jq '.jobs[] | [.name, .started_at, .completed_at, .conclusion] | @tsv'
#   38913175446 / 38891209338도 동일. 꼬리 = attest 소비자 started → 롤업 completed.

# steps API — 스텝 상세 (envelope/authority 분해, §1 표 원문)
gh api repos/Archright/Axiom/actions/jobs/<job_id>/steps \
  --jq '.steps[] | [.number, .name, .started_at, .completed_at, .conclusion] | @tsv'

# 활성 세대 재확인 (§7-1 — 착지 직전 필수)
gh api /orgs/Archright/rulesets --jq '.[] | {id, name, enforcement}'
gh api /orgs/Archright/rulesets/25218071 --jq '.rules[] | select(.type=="workflows") | .parameters'
```

---

*본 문서는 docs+data 전용이며 워크플로·코드를 변경하지 않는다. §3 구현은 §4 불변식·§5 게이트·§7 절차에 구속되는 별도 컨트롤러 PR에서만 수행된다. 게이트의 사후 조정은 인정되지 않는다 — 관측이 예측과 어긋나면 그 사실이 판정이다.*
