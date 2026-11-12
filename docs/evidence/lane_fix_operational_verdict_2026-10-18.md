# 레인 히든파일 수복 운영 판정 — lane 시드·DEBT#502 부활 관측 (2026-10-18)

> **종류**: 실행 증거 (운영 판정 기록, operational verdict). 레인 히든파일 수정 컷오버(PR #906 → 컨트롤러 #229 → 양 ruleset 재핀) 이후 production publisher 런의 복원·검증 로그를 관측해 **lane-seed/DEBT#502 부활**을 확인한다. 결함 검증·수정 기록은 [lane_artifact_hidden_files_fix_2026-10-17.md](lane_artifact_hidden_files_fix_2026-10-17.md)가 담당하며, 본 문서는 그 **사후 운영 판정**이다.
> **권위**: 런/잡/로그 = GitHub Actions API GET 관측값(§6 재현). 본 문서는 Reporter다 (Authority ≠ Adapter — merge-admission 판정 권위는 GitHub다).
> **판정**: **CONFIRMED — lane-seed/DEBT#502 resurrection.** 신규 클로저 키 warm-hit(`exact-hit=true`) 관측 + 구 실패 서명의 수정 후 전수 부재(n=65, 0건).

---

## 1. 판정 대상 — 컷오버 구성 (하나의 논리적 단위)

| 구성요소 | 내용 | 판정 |
|---|---|---|
| Axiom PR #906 | `runner-pool-acceptance.yml` lane 업로드 스텝에 `include-hidden-files: true` 1행 — upload-artifact v4 기본 히든 필터가 `proofs/.lake`(ircheck 거처)·`.axiom/cache`를 전량 소실시키던 결함의 수정 | MERGED 2026-10-17T10:50:11Z (MERGE `18b180094a19096f15a268eeb110a1c7f2f4cfba`) |
| 컨트롤러 Archright/.github PR #229 | callee 핀 회전 `ba773d063` → `18b180094` (Axiom PR #906 MERGE 커밋) | MERGED 2026-10-17T10:55:56Z (MERGE `484f00894995e49b7cd58b366feba66eb438427e`) |
| 양 org ruleset 재핀 | ruleset 25218071(axiom-admission-gate)·23943917(landing-integrity) workflows sha → `484f0089` | 재핀 완료 — 컷오버 단위 완결 |

## 2. 증거 — publisher 런 39047613165 (2026-10-17T16:01:38Z, success, workflow_run)

`ci-cache-publisher` 런 **39047613165**의 잡 로그 원문 (전수 1,549행 감사):

```
AXIOM_CACHE_B_RESTORE: exact-hit=true requested-key=axiom-b-890911ed7f2536afe816e1c190b8446260123bf9-25846005d0fd56faabb1b6f023731c41779205b1ff70f6fcc51dffbb0416e1ba
                       (primary-key=matched-key=동일 키)
AXIOM_CACHE_B_VERIFY: anchor — derivation source identity=890911ed7f25 recipe=25846005d0fd56faabb1b6f023731c41 a_fp=779205b1ff70f6fcc51dffbb0416e1ba (recomputed from trusted inputs, not read from the payload)
AXIOM_CACHE_B_VERIFY: entry OK — bin/ax sha256=9145ca18641ba55c
AXIOM_CACHE_B_VERIFY: entry OK — bin/gate_hook sha256=ffb16076f003d92c
AXIOM_CACHE_B_VERIFY: entry OK — bin/install_ax_cas sha256=fb3e9ae08e2cc4da
AXIOM_CACHE_B_VERIFY: entry OK — bin/precompile_gates sha256=41b7ff2f91851447
AXIOM_CACHE_B_VERIFY: entry OK — proofs/.lake/build/bin/ircheck sha256=9d4309bd6387d175
AXIOM_CACHE_B_VERIFY: RESULT OK — 5/5 entries digest-verified, identity=890911ed7f25 re-derived from trusted inputs (closure+recipe+a_fp), key exact-hit
AXIOM_CACHE_B_PROBE: OK — restored proofs/.lake/build/bin/ircheck present+executable (Lean reference extractor; digest-bound via b-verify files map …)
[publish] guard=true trees=true verify=true key=axiom-b-890911ed7f2536afe816e1c190b8446260123bf9-25846005d0fd56faabb1b6f023731c41779205b1ff70f6fcc51dffbb0416e1ba
```

**의미 — ircheck가 artifact→cache→restore→verify 전 경로를 흐른다.** 결함 창(2026-10-17 03:54–05:56Z, 8/8)에는 lane 아티팩트 자체에서 `proofs/.lake/**`가 소실되어 publisher lane verify가 매 사이클 fail-closed 탈락했다. 본 런에서는 (i) 아티팩트가 ircheck를 포함해 저장되고(수정), (ii) 복원이 요청 키 exact-hit으로 성공하며, (iii) b-verify 5파일 digest 대조 — ircheck 포함 — 가 전부 통과했고, (iv) 소비자 프로브가 `present+executable`을 재확인했다. **DEBT#502의 5번째 verified-supply 멤버(`proofs/.lake/build/bin/ircheck`)가 lane 경로에서 부활했다** — complete-by-construction verify(불완전 페이로드는 어떤 키에도 저장 불가)가 lane 경로에서 처음으로 실제로 작동한다.

정합성 노트: `entry OK — proofs/.lake/build/bin/ircheck sha256=9d4309bd6387d175`는 결함 문서 §1.2가 기록한 흡연총 매니페스트 바인딩(`9d4309bd6387d17582ecd117c3ab7e0b470236fa6cd10e6fbd83da495efc5890`)과 동일 ircheck 파생값이다 — 결함 창에도 빌드·매니페스트에는 존재했으나 전송 계층(v4 히든 필터)에서만 탈락했다는 근본 원인 판정과 정합.

## 3. 구 실패 서명 소멸 — 수정 후 전수 0건

구 실패 서명 `[publish-skip] proofs/.lake/build/bin/ircheck missing after download`에 대한 기계 스캔:

| 창 | 표본 | 서명 관측 |
|---|---|---|
| 사전 수정 (결함 창 03:54–05:56Z) | publisher 런 8건 | **8/8** ([lane_artifact_hidden_files_fix_2026-10-17.md](lane_artifact_hidden_files_fix_2026-10-17.md) §2) |
| 사후 수정 (2026-10-17T10:56:00Z–23:59:59Z) | publisher 런 전수 **65건** | **0건** |

## 4. 전이 아티팩트 판별 (disambiguation) — 구세대 페이로드 폐기는 회귀이 아니다

수정 후 로그에서 아래 라인 형상이 관측되면 그것은 **레인 회귀가 아니라 소비자 fail-closed 계약의 정상 작동**이다:

```
AXIOM_CACHE_B_PROBE: FAIL — proofs/.lake/build/bin/ircheck missing or not executable from restored payload (DEBT#502: partial payload is not a verified supply)
```

- 출처 계약: `.github/actions/setup-axiom-toolchain/action.yml:645` — ircheck 부재·비실행 불가 복원 페이로드는 **구세대(legacy generation) 부분 페이로드**로 판정되어 폐기된다 (DEBT#502 소비자 완결성 게이트 — 부분 페이로드는 verified supply가 아님).
- 해석: 컷오버 전 세대가 저장한 잔여 엔트리가 같은 키로 복원되는 전이 창의 **transition artifact**다 — 소비자가 이를 올바르게 폐기(fail-closed)한 기록이며 lane 시딩 실패와 무관하다.
- 본 증거 런 감사: 런 39047613165의 전수 로그(1,549행)에서 프로브 결과는 **전부 OK**였다 — FAIL 형상은 구세대 잔여 엔트리 폐기 창에 국한되는 별개 계약 발화로, 본 판정의 관측치(RESULT OK 5/5)와 혼동하지 않기 위해 기록한다.

## 5. 정직한 한계 (honest bounds)

- **세대 우선 콜드는 구조적이다.** b-key는 빌드 트리 정체성(클로저 digest)에서 파생되므로 새로 착지한 트리 자신의 키 엔트리는 착지 시점에 존재할 수 없다 — 본 수정은 첫 런을 웜으로 만들지 않으며, 이 콜드는 캐시 계약이 아니라 키 정의의 필연이다.
- **판정 범위**: lane-seed/DEBT#502 부활 **CONFIRMED** + 신규 클로저 키(`axiom-b-890911ed7f25…`)에서의 warm-hit **관측**(exact-hit=true, 런 39047613165). **다음 소비자의 warm 관측(동일 트리 재소비자)은 향후 착지에서 확장 관측 대상**이며 본 판정으로 선언되지 않는다.
- **범위 밖 플래그**(PR #906 후속, 별개 결정): b-key 클로저가 `proofs/**/*.lean`·`lakefile.lean`·`lake-manifest.json`을 배제 → Lean 소스만 변경된 트리에서 S5 build-skip이 구 Lean 소산물 ircheck을 복원할 수 있는 갭(stale-ircheck-on-S5-skip). 본 판정으로 승인·종결되지 않는다.

## 6. 재현 (sources)

```bash
gh run view 39047613165 --repo Archright/Axiom --json displayTitle,event,status,conclusion,createdAt,headSha
gh run view 39047613165 --repo Archright/Axiom --log | grep -E "AXIOM_CACHE_B_|^\S+\s+\S+\s+\S+ \[publish\]"
# 구 실패 서명 전수 스캔 (사후 창 n=65):
gh run list --repo Archright/Axiom --workflow ci-cache-publisher \
  --created "2026-10-17T10:56:00Z..2026-10-17T23:59:59Z" --json databaseId --jq '.[].databaseId'
# 각 런: gh run view <id> --repo Archright/Axiom --log | grep -F "ircheck missing after download"
```

- 관련 문서: [lane_artifact_hidden_files_fix_2026-10-17.md](lane_artifact_hidden_files_fix_2026-10-17.md) (결함 검증·수정), `data/debt_registry.json` DEBT#502 (5파일 complete-by-construction 계약), `data/ci_optimization/lane_fix_verdict_2026-10-18.json` (본 판정의 구조화 사본)
