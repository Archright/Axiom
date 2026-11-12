# 외부 검증 캠페인 001 — S4/S5 수직 슬라이스 기계 판정 증거 (2026-11-10)

> **종류**: 실행 증거(execution evidence)다 — 관측된 기계 판정의 기록이며, 판정 권한 자체는 각 계층의 선언된 authority(GitHub Actions 런·compare 잡·Axiom 엔진)에 있다. 본 문서는 관측 외의 사실을 추가하지 않는다.
> **입력**: 캠페인 런 [42877938958](https://github.com/Archright/nim-libp2p/actions/runs/42877938958)(Archright/nim-libp2p, `workflow_dispatch`, 2026-11-10T18:42:40Z 디스패치)의 `campaign-evidence` 아티팩트 구성 파일 7종 — `verify-record-A.json`·`verify-record-B.json`·`guards.jsonl`·`classification.json`·`comparison-report.json`·`campaign-001.json`·`proposals.json` — 및 실행 로그. 모든 수치는 아티팩트에서 그대로 인용했다(§5 원문 블록).
> **최종 판정**: `campaign_class: DISPROVED_REPRODUCIBLE`, `accepted: true` — "exit 1 on both legs; all 5 guards passed; canonical digests equal"(`classification.json` 원문).

## §1. 궁극 목적 대비 결과

계획의 Ultimate Purpose는 "고정된 Axiom 버전과 설정으로 고정된 외부 프로젝트를 검증하고, 그 결과를 단일 권한자가 판정하며, 검증 산출물과 실행 이력을 외부에서 재현할 수 있게 한다"였다. 2026-11-10 기준 네 가지 사실(Execution·Authority·Evidence·Reproducibility)이 모두 관측됐다:

| 사실 | 관측 |
|---|---|
| Execution | 외부 프로젝트(iftech/nim-libp2p @ `a130a7f3`)에 대해 Axiom 검증이 고객 저장소(Archright/nim-libp2p) GitHub Actions에서 실제 실행됨(런 42877938958, 잡 4/4 success) |
| Authority | 판정 권한은 compare 잡(캠페인 권한자) 하나 — 분류·게이트·아티팩트 발행이 모두 이 잡에서 파생(§3) |
| Evidence | `campaign-evidence` 아티팩트 + 런 URL + axiom-cli v0.6.3 릴리스 자산 + 어테스테이션(§4·§6) |
| Reproducibility | 독립 러너 2회 실행의 정규화 digest 완전 일치(§5) — 스모크 런(별도 저장소·별도 실행)에서도 동일 digest(§7) |

## §2. 8조건 기계 판정

계획 Phase 3의 Terminal condition 8종을 관측된 값으로만 판정한다. 전부 **충족(PASS)**.

| # | 조건 | 관측된 증거 | 판정 |
|---|---|---|---|
| 1 | Release 실존 | axiom-cli 릴리스 `v0.6.3`(id 440753225, published 2026-11-10T18:33:17Z)에 자산 4종: `axiom-bundle-v0.6.3-linux-x86_64.tar.gz`(sha256 `16180f3b…`), `SHA256SUMS`(`cd8d6cb8…`), `manifest.json`(`505150ec…`), `attestation-bundle.jsonl`(`cbf117b1…`). `manifest.json`의 `sourceCommit`=`buildSha`=`87cf67b9…`(PR #72 머지 SHA) | PASS |
| 2 | Customer execution | Archright/nim-libp2p(고객 저장소)의 GitHub Actions 런 42877938958에서 잡 4/4 success: campaign-manifest → propositions → exec(A/B) → compare. 대상 checkout은 핀된 상류 커밋 `a130a7f3…`(`iftech/nim-libp2p`) | PASS |
| 3 | Input identity(7식별자) | `campaign-001.json`에 7종 명시: PROJECT_UNDER_TEST=iftech/nim-libp2p, PROJECT_REVISION=`a130a7f3…`, AXIOM_REVISION=v0.6.3(manifest.json 정본), AXIOM_CONFIGURATION, TOOLCHAIN_IDENTITY, VERIFICATION_SCOPE=SPEC-LIBP2P-BV-SLICE, EXPERIMENT_ID=external-verification-campaign-001. 잡 1이 식별자 검증+전파, compare가 레그·매니페스트·워크플로 3방향 대조(`input_mismatch` 가드 pass) | PASS |
| 4 | Authority(Axiom 단일 판정) | compare 잡이 유일 판정자: 5가드 단언 → 분류 → 게이트(수용 클래스 3종만 허용, fail-closed) → 증거 발행. 판정: `DISPROVED_REPRODUCIBLE`/`accepted: true`(`classification.json`) | PASS |
| 5 | Reproducibility | 레그 A·B의 `canonical_digest` 모두 `c422cd70ce5734d5e58364a6020f8c0de15296fa400add7fb4ea8bce598aafaf`(동일). `determinism_mismatch` 가드 pass. 두 레그는 fail-fast 비활성 매트릭스의 독립 러너에서 각각 신규 prove/report 실행(저장 결과 재관측 아님) | PASS |
| 6 | Zero-Footprint | 양 레그 모두 `pre_tree_hash == post_tree_hash = ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841` + porcelain clean(`zero_footprint_ok: "true"`). `zero_footprint_violation` 가드 pass | PASS |
| 7 | Evidence(제3자 확인 가능) | 런 URL 42877938958 + `campaign-evidence` 아티팩트(7파일) + v0.6.3 릴리스 자산(sha256 공개) + `gh attestation verify` rc=0(§4) + 본 문서의 재검증 명령(§6) | PASS |
| 8 | Claim integrity | 검증 범위는 정확히 1개 BYO 명제(`bytesview-toOpenArray-bv-slice`, SPEC-LIBP2P-BV-SLICE, `libp2p/utils/bytesview.nim::toOpenArray`). 판정 요약 `FAIL/FAIL/DISPROVED` — prove exit=1(§8 전이 계약: 0=PROVED, 1=DISPROVED, ≥2 fail-closed). 명제 수·범위를 초과하는 주장 없음(§8 한계 서술) | PASS |

## §3. 캠페인 실행 이력 — fail-closed가 먼저 관측됐다

정식 캠페인은 2회 실행됐다. 1차 실패는 시스템 결함이 아니라 **가드가 설계대로 매니페스트 드리프트를 차단한 관측**이다:

1. **PR #5**(Archright/nim-libp2p, 머지 `fb9d8c3a`, 18:39:24Z): BYO propositions schema v2 마이그레이션 + Axiom 핀 v0.6.3 + 어댑터 핀 회전(7835673 → `4ca1892a69ab…`, Archright/axiom-cli main tip).
2. **1차 캠페인**(런 42877448900, 18:39:43Z): exec 레그 A/B **모두 success** — 그러나 compare가 `INPUT_MISMATCH`로 fail-closed: `workflow uses pin ('4ca1892a69ab…') != manifest execution.adapter_ref ('78356738f9dd…')`. PR #5가 워크플로 `uses:` 핀만 회전하고 매니페스트 `execution.adapter_ref` 필드를 놓친 것을 가드가 정확히 포착했다.
3. **PR #6**(머지 `f351b4db`, 18:42:30Z): 단일 라인 동기화(`execution.adapter_ref` → 4ca1892).
4. **2차 캠페인 = 정식 판정 런**(42877938958): 잡 4/4 success, §2의 8조건 관측.

이 경로는 "완료는 기계 검증" 원칙의 실증이다 — 선언이 아닌 가드의 exit code가 착지 여부를 결정했다.

## §4. v0.6.3 발행 체인과 자산 검증 (조건 1·7의 근거)

- **엔진 측정 배선**: PR #71(main `63690cf9`, 2026-11-10T17:47:42Z 머지)이 checker.mk에 `ci-compile-hermetic-measure`(guarded 컴파일 → `bin/hermetic_build` → 64-hex 단언, fail-closed)를 배선하고 핀 회전(`config/trusted_writer_set.json` 885→889 멤버, `reanchor_pin --ref HEAD` no-drift exit 0)을 수행했다. 이것이 결함 ⑤(v0.6.2 릴리스 바이너리의 verifierBuildId가 CI에서 unmeasured로 발행됨)의 근본 수정이다.
- **범프**: PR #72(main `87cf67b9`, 2026-11-10T18:21:12Z 머지)가 axiom.nimble/lakefile 0.6.2→0.6.3.
- **발행**: release-ship 런 [42874479725](https://github.com/Archright/Axiom/actions/runs/42874479725) success — release-authority 환경 승인(deployment 7690784092, 18:32:39Z)을 거쳐 axiom-cli v0.6.3 교차 저장소 발행(§2 조건 1).
- **자산 검증(로컬 실측)**: `sha256sum -c SHA256SUMS` 통과(번들·manifest 2항목); manifest `binarySha256` `e369f49c…` ↔ 추출 바이너리 실측 일치; `ax version` → `ax v0.6.3` + Nim 2.2.10 + Lean 4.33.0; `gh attestation verify axiom-bundle-v0.6.3-linux-x86_64.tar.gz --repo Archright/Axiom` → **rc=0**(서명 워크플로 저장소가 Archright/Axiom — 인출한 주체 digest가 번들 sha256과 일치함을 bundle 내 DSSE 페이로드에서 확인).
- **스모크(선행 관측)**: ax-verify 런 [42876739748](https://github.com/Archright/axiom-cli/actions/runs/42876739748) 전 스텝 success — prove exit=1 in-contract + engineBuild guard OK(`e3c42d50…`, 상태 봉투 executionIdentity)+ digest + Zero-Footprint. v0.6.2에서 engineBuild 가드만 실패하던 결함 ⑤가 해소됐다.

## §5. 정본 실측값 (campaign-evidence 아티팩트 원문 인용)

`classification.json`:

```json
{
  "campaign_class": "DISPROVED_REPRODUCIBLE",
  "reason": "exit 1 on both legs; all 5 guards passed; canonical digests equal",
  "accepted": true
}
```

`guards.jsonl`(전 5행):

```json
{"guard":"input_mismatch","pass":true}
{"guard":"determinism_mismatch","pass":true}
{"guard":"vacuous_blocked","pass":true}
{"guard":"zero_footprint_violation","pass":true}
{"guard":"environment_mismatch","pass":true}
```

`verify-record-A.json` — `verify-record-B.json`은 **전 필드에서 A와 동일**(diff 비어 있음; `comparison-report.json`의 `legs.A`/`legs.B` 원문과 동일):

```json
{
  "prove_exit": 1,
  "canonical_digest": "c422cd70ce5734d5e58364a6020f8c0de15296fa400add7fb4ea8bce598aafaf",
  "engine_build_id": "e3c42d5025ce38cda445a04b399ad0d6cfd5231d31b3ec13df6cab1a642adbfb",
  "verdict_summary": "FAIL/FAIL/DISPROVED",
  "zero_footprint_ok": "true",
  "runner_image": "ubuntu24/20261101.360.1",
  "subject_repository": "iftech/nim-libp2p",
  "subject_commit": "a130a7f32219909bdcda14b7f1e64d0804fc832c",
  "axiom_version": "0.6.3",
  "bundle_sha256": "16180f3b1944c786d17de33db9f05f9989ec54e4d108dfcbce0eb67a1753ef2e",
  "proposals_sha256": "beca3b0c53d78c14d4407037078868e9758c01ba4c07f4c6e2999bdadaf388a3",
  "toolchain": {
    "nim": "Nim Compiler Version 2.2.10 [Linux: amd64]",
    "z3": "Z3 version 4.13.3 - 64 bit",
    "lean": "Lean (version 4.33.0, x86_64-unknown-linux-gnu, commit d8b18978322de05a8f3dba51ef03cf5461676c17, Release)",
    "libpcre3": "2:8.39-15build1"
  },
  "pre_tree_hash": "ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841",
  "post_tree_hash": "ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841",
  "state_canonical_run_digest": "294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590"
}
```

`environment_mismatch` 가드는 레그 A↔B의 `runner_image`(ubuntu24/20261101.360.1)와 `toolchain` 4필드 전부 일치를 단언했다. 스모크 5차(런 42876739748, Archright/axiom-cli 러너)도 `canonical_digest` `c422cd70…`·`state_canonical_run_digest` `29418089…`·tree `ec4a0c7e…`가 본 캠페인과 동일했다 — 서로 다른 저장소·러너·입력 직렬화(스모크 proposals_sha `978cebfc…` ≠ 캠페인 `beca3b0c…`)에서도 **결과 digest가 재현**됐다. 단, 정식 재현성 판정은 계약상 캠페인 내 A↔B 비교만이며, 스모크 일치는 보조 관측이다.

## §6. 제3자 독립 검증 절차

GitHub 계정(공개 저장소 읽기 권한)으로 다음을 그대로 실행해 판정을 재현할 수 있다:

```bash
# 1) 캠페인 증거 묶음 — 런의 campaign-evidence 아티팩트 (Actions 기본 보존 90일, §7)
gh run download 42877938958 --repo Archright/nim-libp2p -n campaign-evidence -D campaign-evidence
cat campaign-evidence/classification.json        # → DISPROVED_REPRODUCIBLE, accepted: true
cat campaign-evidence/verify-record-A.json       # → §5 원문
diff <(jq -S . campaign-evidence/verify-record-A.json) \
     <(jq -S . campaign-evidence/verify-record-B.json)   # → 차이 없음 (A == B)

# 2) 릴리스 자산 — 무기한 계층 (만료 규정 없음, §7)
gh release download v0.6.3 --repo Archright/axiom-cli -D v063
(cd v063 && sha256sum -c SHA256SUMS)             # → axiom-bundle…, manifest.json OK
jq . v063/manifest.json                          # → sourceCommit/buildSha 87cf67b9…, binarySha256 e369f49c…

# 3) 출처 증명
gh attestation verify v063/axiom-bundle-v0.6.3-linux-x86_64.tar.gz \
  --repo Archright/Axiom                          # → rc=0 (서명: Archright/Axiom의 release-ship 워크플로)

# 4) 실행 이력 (GitHub이 소유)
gh run view 42877938958 --repo Archright/nim-libp2p   # → jobs 4/4 success, 로그
```

## §7. 증거 보존 정책 (GitHub 플랫폼 네이티브 기능만 사용)

> **구조**: 원본 번들은 **Actions 아티팩트**(시간 제한 계층)에, 바이너리·증명은 **릴리스 애셋**(만료 규정 없음)에, digest·판정·입력 식별자는 **본 문서(git)**에 보존한다. 신규 인프라 없음.

| 계층 | 내용 | 보존 | 근거(공식 문서) |
|---|---|---|---|
| Actions 아티팩트 | 런 42877938958의 4종 — `campaign-evidence`(파일 7종, sha256 `536581c1…`), `propositions`(`993a07f6…`), exec 레그별 `ax-verify-evidence-propositions-A`(`fa836515…`)/`-B`(`98d77c62…`) | **기본 90일**(공개 저장소 상한 90일; `retention-days` 미설정 — 런 워크플로 확인) | [upload-artifact README](https://github.com/actions/upload-artifact): "Maximum 90 days unless changed from the repository settings page" / [보존 설정](https://docs.github.com/en/github/administering-a-repository/managing-repository-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-repository) |
| 릴리스 애셋 | axiom-cli v0.6.3의 자산 4종(번들·SHA256SUMS·manifest·attestation-bundle) | **공식 문서상 만료·자동 삭제 규정 없음**(관리·삭제는 write 권한자만) | [About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases): 파일당 2 GiB 미만·릴리스당 1000개·총량 무제한 |
| git (본 문서) | §5 실측값 전문 + 재검증 명령(§6) | 저장소 수명 | — |
| 어테스테이션 | 번들 provenance(Sigstore, 투명성 로그) | 릴리스 애셋 `attestation-bundle.jsonl`로도 보존 — 아티팩트 만료 후 오프라인 검증 가능 | [어테스테이션 개념](https://docs.github.com/en/actions/concepts/security/artifact-attestations) / [오프라인 검증](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/verify-attestations-offline) |

주의 2건: ① 릴리스 애셋의 "무기한"은 공식 문서에 만료 규정이 *없다*는 근거이지 영구 보장을 명시하는 문장은 아니다. ② 어테스테이션이 증명하는 것은 출처(리포·워크플로·커밋·빌드 지침)와 산출물의 연결이지 산출물의 논리적 정확성이 아니다([개념 문서](https://docs.github.com/en/actions/concepts/security/artifact-attestations): "not a guarantee that an artifact is secure"). 검증의 진실은 Axiom 엔진의 증명·판정(§5)이 담당한다. 아티팩트 90일 경과 후에도 §5·§6의 digest·명령으로 핵심 판정의 재현·대조는 가능하다.

## §8. 한계 — 본 증거가 주장하지 않는 것 (Claim integrity)

- **범위**: 검증된 것은 명제 1개다 — BYO schema v2 문서의 `bytesview-toOpenArray-bv-slice`(specId `SPEC-LIBP2P-BV-SLICE`, 대상 `libp2p/utils/bytesview.nim::toOpenArray`, 문서 계보 cfed3871 byo-agent-verify dispatch "main"). nim-libp2p 전체·다른 심볼·다른 명제에 대한 어떤 주장도 아니다. `verified=0/40`(엔진 로그)은 범위 내 커널 지표 관측값이지 실패가 아니다.
- **판정 의미**: `DISPROVED_REPRODUCIBLE`은 "명제가 두 독립 실행에서 일관되게 **반증**됐고 그 결과가 재현 가능하다"는 뜻이다. 증명(PROVED)이 아니며, 업스트림(iftech/nim-libp2p)에 대한 결함 보고·PR은 본 슬라이스 범위 밖이다.
- **prove exit 의미**: exit=1은 §8 전이 계약(0=PROVED, 1=DISPROVED, ≥2=fail-closed 오류)상 정상 판정 경로다. verify-record의 `verdict_summary: FAIL/FAIL/DISPROVED`와 일치한다.
- **실행 환경의 동일성**: `environment_mismatch` 가드는 A↔B의 러너 이미지 라벨(ubuntu24/20261101.360.1)·툴체인 문자열 일치를 단언한다. 라벨 동일성은 이미지 인스턴스의 바이트 동일성과는 다른 약한 조건이다 — 계획 보완 ①(이미지 자체 고정 아님)의 잔여 한계로 여기에 기록한다. 캠페인 계약은 라벨+툴체인+digest 일치를 재현성 판정 기준으로 채택했다(§5).
- **Zero-Footprint 강도**: 관측은 pre/post 트리 해시·porcelain clean 기계 단언이다. 실행 자체를 read-only 샌드박스로 강제하는 것은 아니다(계획 §4.3 명시된 선택).
- **1차 실행(42877448900)**: fail-closed로 폐기된 진단 실행이며, 정식 판정은 PR #6 착지 후 2차 실행(42877938958)만으로 내려졌다(§3). 두 실행의 EXPERIMENT_ID는 동일하나 재시도는 워크플로 런 단위(같은 디스패치 계약)지 부분 재실행(re-run)이 아니었다.

## §9. 기록

| 항목 | 값 |
|---|---|
| EXPERIMENT_ID | external-verification-campaign-001 |
| 정식 판정 런 | Archright/nim-libp2p actions run 42877938958 (2026-11-10T18:42:40Z 디스패치, 18:44:10Z 완료) |
| 폐기된 진단 런 | 42877448900 (INPUT_MISMATCH fail-closed, §3) |
| 릴리스 | Archright/axiom-cli v0.6.3 (id 440753225) |
| Axiom main | 87cf67b (PR #72) / 측정 배선 63690cf9 (PR #71) |
| 고객 저장소 커밋 | PR #5 `fb9d8c3a` + PR #6 `f351b4db` (Archright/nim-libp2p master) |
| 어댑터 핀 | Archright/axiom-cli @ `4ca1892a69abcdb9036ec8a69d7bcedc940507d1` |
| 문서 작성 시점 관측 | 2026-11-10 (KST) — 이후 런·아티팩트 상태 변화는 본 문서 범위 밖 |
