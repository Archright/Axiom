# 외부 검증 캠페인 — 라이브 BYO AI 에이전트 명제 생성 실증 (2026-11-13)

> **종류**: 실행 증거(execution evidence)다 — 관측된 기계 판정의 기록이며, 판정 권한 자체는 각 층의 선언된 authority(GitHub Actions 런·compare 잡·Axiom 엔진)에 있다. 본 문서는 관측 외의 사실을 추가하지 않는다.
> **입력**: 캠페인 런 [43363278211](https://github.com/Archright/nim-libp2p/actions/runs/43363278211)(Archright/nim-libp2p, `workflow_dispatch`, 2026-11-13T04:06:08Z 디스패치, 04:09:41Z 완료, 잡 5/5 success)의 아티팩트 — `campaign-evidence`·`agent-provenance`·`propositions`·`ax-verify-evidence-propositions-A`·`-B` — 및 실행 로그. 모든 수치는 아티팩트에서 그대로 인용했다(§5 원문 블록).
> **선행 대비 차이**: 캠페인-001(2026-11-10, [증거](external_verification_campaign_001_2026-11-10.md))은 핀된 고정 명제 문서(fixture, sha256 `beca3b0c…`)로 파이프라인을 실증했다. 본 런은 **Job 2가 실제 AI 에이전트(llama.cpp b12340 + Qwen2.5-Coder-1.5B, 시크릿 0)를 실행해 명제 문서를 자율 생성**한 최초의 라이브 캠페인이다(`agent-provenance.mode: "live"`).
> **최종 판정**: `campaign_class: DISPROVED_REPRODUCIBLE`, `accepted: true` — "exit 1 on both legs; all 5 guards passed; canonical digests equal"(`classification.json` 원문).

## §1. 궁극 목적 대비 결과

이 슬라이스의 Ultimate Purpose는 "AI 에이전트가 외부 소프트웨어의 검증 후보를 발견·명제화하고, Axiom이 그 주장을 독립적으로 검증하며, 제3자가 GitHub에서 결과를 재현할 수 있게 한다"였다. 2026-11-13 기준 다섯 사실이 관측됐다:

| 사실 | 관측 |
|---|---|
| Discovery(live) | 라이브 AI 에이전트가 핀된 서브젝트 소스를 읽어 schema v2 명제 문서 2건을 자율 생성(sha256 `5b66721e…`, fixture `beca3b0c…`와 상이 — §5) |
| Verification | 동일 문서에 대해 SHA-핀 어댑터(`ax-verify.yml@4ca1892a…`) A/B 독립 실행, 레그 전 필드 동일(§5) |
| Authority | 판정 권한은 compare 잡(캠페인 권한자) 하나 — 5가드 → 분류 → 게이트 → 증거 발행(§2) |
| Evidence | 런 URL 43363278211 + 아티팩트 5종 + Step Summary + v0.6.3 릴리스 자산·어테스테이션(§5·§7) |
| Replay(제3자) | 로컬 콜드 리플레이에서 `state_canonical_run_digest`·`engine_build_id`·2축 롤업이 CI와 완전 일치, 서브젝트 트리 불변(§6) |

## §2. 라이브 에이전트 슬라이스 기계 판정

계획의 완료 조건을 관측된 값으로만 판정한다. 전부 **충족(PASS)**.

| # | 조건 | 관측된 증거 | 판정 |
|---|---|---|---|
| 1 | 라이브 에이전트 실재 | `agent-provenance.mode: "live"`, `agent_runner: "llama.cpp b12340 llama-completion (MIT) + Qwen2.5-Coder-1.5B-Instruct q4_k_m (Apache-2.0)"`, elapsed 104s. 런에서 사용한 GitHub Secret 0건 — 비결정 요소는 소유자가 핀한 오픈웨이트 추론기로 국한 | PASS |
| 2 | 발견 결속(provenance 4-tuple) | `binary_sha256`·`model_sha256`(=`cc324af0…`)·`prompt_sha256`(=`2761a067…`)·`proposals_sha256`(=`5b66721e…`) + `subject_repository/commit`·소스 블롭 sha(`b205c969…`)·카탈로그 sha(`93c28006…`)가 모두 문서화됨. `proposals_sha256 == sha256(proposals.json)` 3방향 대조 통과 | PASS |
| 3 | fixture와 구별 | 라이브 문서 sha256 `5b66721e…` ≠ 정적 fixture `beca3b0c…`; `agent.id` `byo-open-weights-qwen2.5-coder-1.5b` ≠ fixture `phase3-selftest-agent` | PASS |
| 4 | 입력 계약 준수 | Input Admission이 명제 2건(레인형 1 + 클레임형 1)을 `ADMITTED`로 통과 — 엔진 intake 계약과 100% 패리티인 사전 검증(스키마·크기·ID·단일 타깃·상호배타·신원) | PASS |
| 5 | 카탈로그 정직성(2축) | 롤업: `bv-slice-lane-1`(SPEC-LIBP2P-BV-SLICE) = CAPABLE + DISPROVED(attempted) / `lane-2`(논리 `forall_e_in_1..5`) = **INCAPABLE{UNSUPPORTED_LOGIC}**(attempted=false). 카탈로그 밖 명제를 지원한다고 주장하지 않음 | PASS |
| 6 | A/B 재현성 | 레그 A·B `canonical_digest` 모두 `1603765c…`(동일), verify-record 전 필드 diff 빈함. `determinism_mismatch` 가드 pass | PASS |
| 7 | 5가드 | `input_mismatch`·`determinism_mismatch`·`vacuous_blocked`·`zero_footprint_violation`·`environment_mismatch` 전부 pass(§5) | PASS |
| 8 | Zero-Footprint | 양 레그 `pre_tree_hash == post_tree_hash = ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841` + porcelain clean. 에이전트는 서브젝트 소스를 **데이터로만 읽음**(실행 금지 스텝 `Checkout subject repository into subject-ro (data source ONLY — never executed)`) | PASS |
| 9 | 제3자 재현 | §6 절차를 그대로 실행: `state_canonical_run_digest` `29418089…`·`engine_build_id` `e3c42d50…`·롤업·서브젝트 트리·prove exit=1(in-contract) 모두 CI와 일치(§6) | PASS |

## §3. 실행 이력 — 착지 경로

1. **PR #7**(Archright/nim-libp2p, `campaign/live-byo-agent-job2`, 머지 `94a437bf`, 2026-11-13T04:04:49Z, 파일 1종 `axiom-verification.yml` +851/−57): Job 2를 라이브 BYO 에이전트 실행으로 교체 — llama.cpp/모델 sha256 핀 다운로드, 순수 schema v2 GBNF 문법 제약, 대화 출력에서의 JSON 추출, 엔진 intake와 100% 패리티인 Input Admission, agent-provenance 기록.
2. **라이브 캠페인**(런 43363278211, master @ `94a437bf`에서 디스패치): 잡 5/5 success — manifest 검증 → 라이브 에이전트 + Input Admission → ax-verify A/B(매트릭스 독립 러너) → compare. §2의 9조건 관측. 본 런은 첫 디스패치에 전 스텝을 통과했다(fail-closed 재시도 경로 없음).

## §4. 라이브 에이전트 경계 (신뢰 분리의 실행 관측)

- **실행기 핀**: `llama-b12340-bin-ubuntu-x64.tar.gz`(MIT, ggml-org b12340 릴리스) — 워크플로가 tarball sha256을 검증 후 사용(추출된 `llama-completion` 바이너리 sha256 `7119bef2…`). 추론 파라미터는 온도 0(시드는 고정하지 않음 — llama-completion 기본값)이며, 따라서 **명제 생성 자체는 비결정 영역**이다(§8).
- **모델 핀**: `Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF` q4_k_m(Apache-2.0, sha256 `cc324af0…`). 외부 LLM API·API 키·GitHub Secret **0건** — 자격증명 경계(AGENTS.md §2.4)를 위반하지 않는 무시크릿 경로다.
- **문법 제약**: GBNF 문법은 **순수 schema v2 구조만** 규정한다(`specId`·`target`·`subject` 하드코딩 없음). 모델이 생성한 값은 프롬프트에 제시된 카탈로그·서브젝트 원문에서 온다 — 생성 문서의 신원(`iftech/nim-libp2p @ a130a7f3…`)은 그 후 Input Admission이 워크플로 선언 핀과 대조해 확정한다.
- **도구 경계**: 에이전트는 임의 셸·빌드 스크립트·서브젝트 코드 실행 없음. 출력은 대화 텍스트 → JSON 추출(`JSONDecoder.raw_decode`) → 스키마 사전 검증의 3단 단일 방향이다.
- **권한 분리**: Job 2(비결정 발견)는 데이터(아티팩트)만 생산하고, 판정은 Job 3/4(결정적 검증·compare)가 수행한다. AI는 자기 검증 결과를 확정하거나 GitHub 병합 상태에 개입하지 않는다.

## §5. 정본 실측값 (아티팩트 원문 인용)

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

`verify-record-A.json` — `verify-record-B.json`은 **전 필드에서 A와 동일**(diff 비어 있음):

```json
{
  "prove_exit": 1,
  "canonical_digest": "1603765c7df1c2f183e3f224d9b1fbb61ae3a1b77a1e5455cff7abea4953d14a",
  "engine_build_id": "e3c42d5025ce38cda445a04b399ad0d6cfd5231d31b3ec13df6cab1a642adbfb",
  "verdict_summary": "FAIL/FAIL/DISPROVED",
  "zero_footprint_ok": "true",
  "runner_image": "ubuntu24/20261101.360.1",
  "subject_repository": "iftech/nim-libp2p",
  "subject_commit": "a130a7f32219909bdcda14b7f1e64d0804fc832c",
  "axiom_version": "0.6.3",
  "bundle_sha256": "16180f3b1944c786d17de33db9f05f9989ec54e4d108dfcbce0eb67a1753ef2e",
  "proposals_sha256": "5b66721e1eb58aa4b311c661b17d38951a3d81784ccba864777c596bed987eee",
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

`agent-provenance.json`(핵심 필드):

```json
{
  "mode": "live",
  "agent_runner": "llama.cpp b12340 llama-completion (MIT) + Qwen2.5-Coder-1.5B-Instruct q4_k_m (Apache-2.0)",
  "model_sha256": "cc324af070c2ecbfd324a30884d2f951a7ff756aba85cb811a6ec436933bb046",
  "prompt_sha256": "2761a0671979daf0fdfb9535a93faa87491fa3cccefd6309ba5aacd9ff5a5ed1",
  "subject_repository": "iftech/nim-libp2p",
  "subject_commit": "a130a7f32219909bdcda14b7f1e64d0804fc832c",
  "proposals_sha256": "5b66721e1eb58aa4b311c661b17d38951a3d81784ccba864777c596bed987eee",
  "elapsed_seconds": 104,
  "admission_summary": {
    "result": "ADMITTED",
    "propositions": 2,
    "lane_form": 1,
    "claim_form": 1,
    "target": "libp2p/utils/bytesview.nim::toOpenArray",
    "equipped_scope_lanes": ["SPEC-LIBP2P-BV-SLICE"]
  }
}
```

에이전트가 생성한 `proposals.json`(명제 2건의 요지): ① `byo-open-weights-qwen2.5-coder-1.5b-lane-1` — 레인형, `target: libp2p/utils/bytesview.nim::toOpenArray`, `specId: SPEC-LIBP2P-BV-SLICE`, `libp2p/utils/bytesview.nim:18`의 `v.data.toOpenArray(v.rpos + b, v.rpos + e - b)`가 길이 `e-2b+1`(b원소 부족)을 낸다는 설명; ② `byo-open-weights-qwen2.5-coder-1.5b-lane-2` — 클레임형, 논리 `forall_e_in_1..5` (`toOpenArray(bv,1,e).len == e`). ①은 캠페인-001의 반례(오프바이-b)와 동일 결함을 에이전트가 소스 읽기에서 재발견했고 ②는 카탈로그 미지원 논리로 INCAPABLE 처리됐다(§2 조건 5).

`ax_proof_state.json` 2축 롤업: `CAPABLE/DISPROVED=1`(attempted), `INCAPABLE/UNSUPPORTED_LOGIC=1`(attempted=false) — CI와 로컬 리플레이(§6)에서 동일.

## §6. 제3자 독립 검증 절차 (실측 관측)

GitHub 계정(공개 저장소 읽기 권한)으로 다음을 실행해 판정을 재현할 수 있다. 본 절의 관측값은 2026-11-13 로컬 콜드 리플레이(클린 재추출 번들) 실측이다:

```bash
# 1) 캠페인 증거 — 런 아티팩트
gh run download 43363278211 --repo Archright/nim-libp2p -n campaign-evidence -D ev
cat ev/classification.json                         # → DISPROVED_REPRODUCIBLE, accepted: true
diff <(jq -S . ev/verify-record-A.json) \
     <(jq -S . ev/verify-record-B.json)            # → 차이 없음 (A == B)

# 2) 검증기 — v0.6.3 릴리스 번들 + 출처 증명
gh release download v0.6.3 --repo Archright/axiom-cli -D v063
(cd v063 && sha256sum -c SHA256SUMS)               # → OK
gh attestation verify v063/axiom-bundle-v0.6.3-linux-x86_64.tar.gz \
  --repo Archright/Axiom                            # → rc=0

# 3) 콜드 리플레이 — 핀된 서브젝트 + 라이브 생성 문서로 prove 재실행
gh run download 43363278211 --repo Archright/nim-libp2p -n propositions -D props
git clone https://github.com/iftech/nim-libp2p subject && git -C subject checkout a130a7f32219909bdcda14b7f1e64d0804fc832c
mkdir -p state/logs
# 서브젝트의 Nim 의존성(핀) — 어댑터가 CI에서 스테이징하는 것과 동일
mkdir -p deps && cd deps
git clone -q https://github.com/status-im/nim-serialization && git -C nim-serialization checkout b5473564e80a4908cf6c5a038e4c4a6ca7de2223
git clone -q https://github.com/status-im/nim-faststreams && git -C nim-faststreams checkout 059bc2f52546ac14b583639c33372c14b1d46fa3
git clone -q https://github.com/status-im/nim-stew && git -C nim-stew checkout 4382b18f04b3c43c8409bfcd6b62063773b2bbaa
git clone -q https://github.com/arnetheduck/nim-results && git -C nim-results checkout df8113dda4c2d74d460a8fa98252b0b771bf1f27
cd ..
AXIOM_ROOT=$PWD/v063/axiom-v0.6.3-linux-x86_64 \
AXIOM_STATE_DIR=$PWD/state \
AXIOM_PROVE_WORKERS=1 \
AXIOM_SUBJECT_REPOSITORY=iftech/nim-libp2p \
AXIOM_SUBJECT_COMMIT=a130a7f32219909bdcda14b7f1e64d0804fc832c \
AXIOM_REPLAY_DEP_PATHS=$PWD/deps/nim-serialization:$PWD/deps/nim-faststreams:$PWD/deps/nim-stew:$PWD/deps/nim-results \
  $PWD/v063/axiom-v0.6.3-linux-x86_64/ax prove \
    --proposals props/proposals.json --project subject   # → exit 1 (in-contract: DISPROVED)

# 4) 판정 축 대조
jq -r '.canonicalRunDigest' state/logs/ax_proof_state.json   # → 294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590 (== CI)
jq -r '.executionIdentity.verifierBuildId' state/logs/ax_proof_state.json  # → e3c42d50… (== CI)
git -C subject rev-parse 'HEAD^{tree}'                       # → ec4a0c7e… (불변, Zero-Footprint)
```

**실측 재현 결과(로컬 2회 독립 실행)**: `state_canonical_run_digest` `29418089…`·`engine_build_id` `e3c42d50…`·2축 롤업(1/1)·서브젝트 트리 `ec4a0c7e…`·prove exit=1 모두 CI 레그와 일치. `canonical_digest`는 로컬에서 `9ee9d512…`(2회 모두 동일)로 CI(`1603765c…`)와 다르다 — `executionIdentity` 대조에서 `executionBundleFingerprint`·`toolchainIdentity`·`verifierBuildId`·`platform`은 동일이고 차이는 `executionConfigDigest`·`executionEpoch`(실행 환경 결속 필드)에 격리된다. 즉 `canonical_digest`는 환경 내 결정론(CI A==B, 로컬 1회==2회 — 모두 관측됨)이며, **호스트 무관 재현 판정 축은 `state_canonical_run_digest`**(§8)다. 서브젝트 워크트리는 재현 후 원상복구됐다.

## §7. 증거 보존 정책

캠페인-001과 동일 구조를 따른다(원문 근거: [캠페인-001 §7](external_verification_campaign_001_2026-11-10.md)): 아티팩트(5종 — `campaign-evidence` 9파일, `propositions`, `agent-provenance` 3파일, 레그별 `ax-verify-evidence-propositions-A/B` 각 15파일)는 Actions 기본 90일, 릴리스 자산(v0.6.3 번들·SHA256SUMS·manifest·attestation)은 만료 규정 없음, digest·판정·식별자는 본 문서(git)에 보존. 신규 인프라 없음.

## §8. 한계 — 본 증거가 주장하지 않는 것 (Claim integrity)

- **발견의 비결정성**: AI 명제 생성은 비결정 영역이다. 본 증거는 "이번 런에서 이 에이전트가 이 문서(`5b66721e…`)를 생성했고 그 문서의 검증이 재현됐다"는 관측이지, "에이전트가 매번 동일한 명제를 생성한다"는 주장이 아니다. 결정론 계약(A/B·리플레이 digest 일치)은 **고정된 문서에 대한 검증 단계에만** 적용된다.
- **발견 능력의 일반화 금지·프롬프트 유도 공개**: 프롬프트가 EQUIPPED 레인 사용과 함께 **결함 자체(길이 법칙 `e-2b+1` 오프바이-b)를 명시적으로 안내**했다(워크플로 프롬프트 원문 참조). 명제 ①이 이 결함을 지목한 것은 유도된 관측이지 자율적 결함 발견이 아니다. 에이전트가 생성한 것은 프롬프트·카탈로그·소스를 결합해 계약을 충족하는 **문서(타깃·specId·설명의 올바른 결합)**다. 본 슬라이스가 실증한 것은 **라이브 에이전트를 결정적 검증 경계에 연결하는 연결부**며, 무유도 자율 발견 능력은 별개의 미실증 주장이다.
- **INCAPABLE의 정직성**: 명제 ②(논리 `forall_e_in_1..5`)는 카탈로그 미지원으로 `INCAPABLE{UNSUPPORTED_LOGIC}`·attempted=false로 기록됐다. 이를 PROVED로 표시하거나 생략하지 않았다(§2 조건 5).
- **canonical_digest의 환경 결속**: `canonical_digest`의 CI↔로컬 차이는 §6에서 필드 격리로 입증된 환경 결속(`executionConfigDigest`·`executionEpoch`)이며, 로컬 2회 재실행 동일성으로 비결정성 가능성을 배제했다. 제3자 재현 판정 축은 `state_canonical_run_digest`다(캠페인-001과 동일 값 `29418089…` — 동일 서브젝트·동일 판정 의미론의 안정 재현).
- **판정 의미**: `DISPROVED_REPRODUCIBLE`은 "라이브 생성 명제가 두 독립 실행에서 일관되게 반증되고 재현 가능하다"는 뜻이다. 증명(PROVED)이 아니며, 업스트림(iftech/nim-libp2p) 이슈 작성·PR은 본 슬라이스 범위 밖이다.
- **스코프**: 검증 범위는 카탈로그 EQUIPPED 레인 `SPEC-LIBP2P-BV-SLICE`(타깃 `libp2p/utils/bytesview.nim::toOpenArray`) 1건 + 미지원 클레임 1건이다. nim-libp2p 전체·다른 심볼에 대한 주장이 아니다.
- **권한**: 본 문서는 관측 기록이며 판정 권한은 GitHub(런·병합)·compare 잡(캠페인 분류)·Axiom 엔진(증명)에 있다. 문서 작성 시점 이후의 런·아티팩트 상태 변화는 본 문서 범위 밖이다.

## §9. 기록

| 항목 | 값 |
|---|---|
| EXPERIMENT_ID | external-verification-campaign-001 (관측; 라이브 모드 구분은 `agent-provenance.mode: "live"`) |
| 라이브 판정 런 | Archright/nim-libp2p actions run 43363278211 (2026-11-13T04:06:08Z 디스패치, 04:09:41Z 완료, 잡 5/5 success) |
| 워크플로 커밋 | master @ `94a437bf` (PR #7 머지, 2026-11-13T04:04:49Z, `axiom-verification.yml` +851/−57) |
| 서브젝트 | iftech/nim-libp2p @ `a130a7f3` (트리 `ec4a0c7e…` 불변) |
| 어댑터 핀 | Archright/axiom-cli @ `4ca1892a69abcdb9036ec8a69d7bcedc940507d1` (ax-verify.yml, v0.6.3) |
| 릴리스 | Archright/axiom-cli v0.6.3 (번들 sha256 `16180f3b…`·manifest·SHA256SUMS·attestation) |
| 라이브 에이전트 | llama.cpp b12340 (MIT) + Qwen2.5-Coder-1.5B-Instruct q4_k_m (Apache-2.0, `cc324af0…`) — Secret 0건 |
| 생성 문서 | proposals.json sha256 `5b66721e…` (fixture `beca3b0c…`와 상이, mode=live, elapsed 104s) |
| 제3자 재현 | 로컬 콜드 리플레이 2회 (2026-11-13): `state_canonical_run_digest` `29418089…`·`engine_build_id` `e3c42d50…`·롤업 1/1·트리 `ec4a0c7e…`·exit=1 — 전부 CI와 일치 |
| 문서 작성 시점 관측 | 2026-11-13 (KST) |
