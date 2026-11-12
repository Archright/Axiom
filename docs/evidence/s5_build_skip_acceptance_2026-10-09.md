# S5 build-skip acceptance — 2026-10-09 (v3, 2026-10-10 갱신)

## 1. 계약 (J3 §3.1 / ADR-0032 landing venue)

Landing venue(MG lane)에서 job1의 B-restore가 **검증된 페이로드**(4 ci-compile 바이너리 + ircheck + fingerprint manifest + build/nimcache, 전 멤버 존재·실행비트)를 복원하면 컴파일 블록(probe/smoke/build)을 생략하고 복원 페이로드를 공급으로 바인딩한다. 복원 불가·검증 FAIL 시 기존 fail-closed cold 빌드(Pre-S5 MISS 경로와 바이트 동일). **job2 판정은 불변** — 판정 스텝은 양 모드에서 동일하게 발화한다(§0.9: platform은 skip된 스텝을 success로 계수하므로 명시적 판정 라인이 의무).

판정 라인(모든 lane에서 정확히 하나 발화):
- HIT: `SUPPLY REUSE — verified payload restored; compile skipped (ADR-0032/J3 §3.1)`
- MISS: `S5 COLD BUILD — verified supply absent (B-cache miss, or restore discarded by verify/probe FAIL: fail-closed); compiling from B (cache is acceleration, never evidence)`

## 2. 착지·핀 회전 이력 (실측)

| 항목 | 값 |
|---|---|
| S5 구현 PR | #645 (feat/s5-build-skip, 커밋 d3ccad320 + 18df8c8d6) |
| #645 MERGE | 2026-10-09T08:41:26Z, merge commit `3a33f59774c4` (parents=2) |
| #645 admission-gate | run `37904762781` success 08:24:31Z→08:40:59Z (15 jobs 전부 success) — **주의: 당시 핀 f68049cd(S5 이전 #640 blob 9ed9826a)라 MG lane은 S5 스텝 없이 실행 → 본 런에서 S5 발화 없음 (설계대로)** |
| 핀 회전 트리거 | Archright/.github #101 `chore(dependabot): pin-rotation trigger (S5 build-skip)` MERGE 08:51:09Z `8a99e3d783c2` |
| dependabot 범프 | Archright/.github #102/#103/#104 (f68049cd → dc92faf8ee0a) 전부 MERGE |
| 회전 후 핀 | admission-gate.yml의 5곳 uses 전부 `Archright/Axiom/...@dc92faf8ee0a3402b35d16cb1805a75f9be17b72` — 해당 트리의 admission-check.yml blob = `62294da2` (S5 버전, TWS/epoch manifest 핀과 동일 blob) |
| #645 이후 main 진행 | 3a33f5977(#645) → dc92faf8e(#644, 08:41:27Z) → aaf2ca9d8(#626) → 이후 N+8~N+12 착지 계속 |

## 3. DEBT#502 — SUPPLY REUSE 미발화의 구조적 원인 (v3 신설, 3단계 누출)

v2(#652)에서 등록된 DEBT#502의 재액터 구조가 금일 재현 로그 3건으로 반박 불가로 확정되었다:

1. **생산 부재(lane 경로)**: runner-pool-acceptance.yml ci-bootstrap이 `make ci-compile -j4`만 실행하고 `lake build ircheck`를 하지 않는다(Lake smoke는 mktemp 임시디에서만) → lane artifact `ci-bootstrap-artifacts`의 proofs/.lake에는 ircheck가 구조적으로 없다.
2. **검증 결손**: ci-cache-publisher lane fingerprint manifest files map이 4파일(bin/ax·gate_hook·precompile_gates·install_ax_cas)뿐 → 소비자 b-verify가 ircheck-less 부분 엔트리를 `RESULT OK — 4/4`로 통과시켰다(base fingerprint는 ircheck 포함 5파일 — 대비).
3. **single-flight 영구 선점**: publisher는 lane(부분)을 먼저, base(완전)를 나중에 저장하며 base-lookup이 동일 키의 부분 엔트리를 HIT하면 `base key exists — save withheld (single-flight)`로 보류한다. GitHub 캐시 키는 불변이므로 완전 엔트리의 동일 키 대체는 불가능 — 부분 엔트리가 키를 영구 선점한다.
4. **b-verify·B_PROBE 결손**: 소비자 action.yml이 5번째 공급 멤버(ircheck)를 전혀 단언하지 않는다(b-verify files map 순항, B_PROBE 4바이너리 루프).

## 4. 금일(2026-10-10) COLD 재현 로그 3건 — v3 실측

모든 런이 동일 패턴: **부분 엔트리(4/4) 복원 성공 → ircheck 결손 → fail-closed COLD**. restore 자체는 HIT(부분 캐시가 정상 HIT로 소비된 것 — DEBT#502 (3)의 선점된 키)이므로 "B-cache miss"가 아니라 **부분 공급 재사용 차단**이 정확한 서술이다.

| run | event / head | attest/build-base-artifacts wall | b-verify | S5 판정 |
|---|---|---|---|---|
| `38022092775` | merge_group / 5fabf4847 | 03:52:39→03:56:33 (**3m54s**) | `RESULT OK — 4/4 entries digest-verified, identity=c08e08ea8c06` | `[s5] verified supply absent: proofs/.lake/build/bin/ircheck` → `S5 COLD BUILD` |
| `38022242393` | merge_group / 458579316 | 03:55:15→03:59:02 (**3m47s**) | `RESULT OK — 4/4 entries digest-verified, identity=c08e08ea8c06` | 동일 → COLD (`Built ircheck:exe (758ms)` 재빌드 확인) |
| `38023152483` | merge_group / 15da70d87 | 04:10:49→04:15:02 (**4m13s**) | `RESULT OK — 4/4 entries digest-verified, identity=ae99c1bb0541` | 동일 → COLD (`Built ircheck:exe (874ms)` 재빌드 확인) |

원문 로그 발췌(run 38022092775, job 114125075668):

```
AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 entries digest-verified, identity=c08e08ea8c06 re-derived from trusted inputs (closure+recipe+a_fp), key exact-hit
[s5] verified supply absent: proofs/.lake/build/bin/ircheck
S5 COLD BUILD — verified supply absent (B-cache miss, or restore discarded by verify/probe FAIL: fail-closed); compiling from B (cache is acceleration, never evidence)
```

4/4 판정 라인이 동시 실측된 것은 **부분 엔트리가 정상 HIT로 취급되던 유일한 관측 지점**이며, 수정(§5) 후 이 자리는 `RESULT OK — 5/5`가 완전 페이로드 마커가 된다.

## 5. 수정 (DEBT#502 resolution — fix/s5-ircheck-supply)

4단계 누출 각각의 제거(한 PR에서 일관 세대 전환):

| 누출 | 수정 파일 | 내용 |
|---|---|---|
| (1) 생산 부재 | runner-pool-acceptance.yml | ci-bootstrap에 `cd proofs && lake build ircheck` 추가(admission-check [build]의 정준 호출 미러) + manifest 루프 5파일화(`test -x` fail-closed) |
| (2) 검증 결손 | ci-cache-publisher.yml | lane verify sha256 대조 5파일화 + lane fingerprint files map에 `proofs/.lake/build/bin/ircheck` 추가(base와 동일 집합) |
| (3) single-flight 선점 | ci-cache-publisher.yml + action.yml | **base-verified-complete 우선 규칙** — 키 불변성 하에서의 유일한 정직한 부분→완전 승격: (a) 양 writer complete-by-construction(verify 5파일 fail-closed — 불완전 페이로드는 저장 자체 불가), (b) 소비자 b-verify가 5파일 필수 집합 강제(복원된 부분 엔트리 = DISCARD, 정상 HIT 아님), (c) action.yml script_hash 변경으로 선점된 구세대 키 전량 무효화(문서화된 원샷 콜드) |
| (4) 소비자 결손 | setup-axiom-toolchain/action.yml | b-verify 필수 5파일 집합 → `RESULT OK — 5/5`가 완전 페이로드 마커; B_PROBE에 ircheck 존재·실행비트 단언 추가(Lean 바이너리는 BuildSourceHash가 없어 --check-provenance 정의 밖 — 앵커는 b-verify files map digest + 존재 재단언; 결손 시 FAIL → 폐기) |

계약 테스트: tests/ci/test_b_cache_anchor.nim 5파일 계약으로 갱신 — (h) `RESULT OK — 5/5`, 신설 (r) 불완전 manifest 폐기, 신설 (p5) ircheck 결손 probe 폐기. 37/37 [OK].

## 6. Reopen 이벤트 ADM_IDENTITY fail-closed 사건 (S5 무관, 기존 검사)

close/reopen으로 재유도된 #646/#627/#628의 preflight가 `attest / admission-check` 실패:
`ADM_IDENTITY: FAIL — PR base.sha aaf2ca9d8695 != B 27fce26ccd49 (base moved during admission? fail-closed)`.
원인: reopen 이벤트 페이로드의 base 스냅샷(27fce26, 구) vs PR API base.sha(aaf2ca9d, 현재 main) 불일치 — SL-01 identity 재도출의 설계된 fail-closed. 이 검사는 S5 이전 blob(9ed9826a 1005행)에도 동일 존재 → **S5 회귀 아님**. 수복: `PUT /pulls/{n}/update-branch` (main 병합 갱신) 후 synchronize 이벤트의 신선한 페이로드로 전부 success.

## 7. (a) PR preflight wall — 핀 회전 후 회귀 없음

S5 판정 스텝은 landing 게드(`venue == 'landing'`)라 preflight에서는 발화하지 않는다(로그 실측: venue=preflight, Supply-mode 라인 0건). 벽시계:

| PR | run | 전체 | build-base-artifacts | attest/admission-check |
|---|---|---|---|---|
| #627 (update-branch 후) | `37908813804` | 09:03:25→09:07:05 (3m40s) | 1m25s | 51s |
| #628 (update-branch 후) | 09:03:34→09:07:15 (3m41s) | | 47s | 57s |

사전(회전 전) 실측 대비 build-base·admission-check wall 불변 — preflight 회귀 없음.

## 8. MG lane 실측 (아래 각 절은 착지 런에서 기입)

### (b)(d) HIT — 검증 공급 재사용

수정 전 상태(§4): 세 런 전부 MISS — job1 벽시계 3m47s~4m13s(COLD 재컴파일 포함; §5 수정의 목표 ≤1.5m 대비 ~3배). **수정 후 HIT 실측은 본 수정(main 착지 + org 핀 회전 완료 + A/B 키 원샷 콜드 소진) 이후의 MG lane에서 기입** — 기입 예정 항목: run id, job1 `SUPPLY REUSE` 라인, `AXIOM_CACHE_B_VERIFY: RESULT OK — 5/5`, job1 벽시계, landing_observe VERDICT. (선주장 금지 — 관측 후 기입.)

### (c) MISS — fail-closed cold

§4의 3건이 수정 전 세계의 MISS 구조를 대표한다: publisher lane(부분) 선행 저장 → base(완전) single-flight 보류 → 소비자 복원은 부분 엔트리 → fail-closed COLD. MISS 자체의 fail-closed 방향은 올바르며(부분 공급을 증거로 재사용하지 않음), 결함은 HIT이 도달 불가능했던 구조(DEBT#502)였다.

## 9. 판정

- 수정 전(§4 실측): S5 SUPPLY REUSE는 발화 조건이 구조적으로 성립하지 않았다(DEBT#502 — 등록·본 PR에서 해소).
- 수정 후: §8(b)(d) 착지 lane 관측으로 확정한다. (착지 전 문서 v3 — 측정은 관측 후 기입이 원칙, 선기입 금지.)
