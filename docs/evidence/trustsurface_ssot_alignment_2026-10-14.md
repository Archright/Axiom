# Trust surface policy SSOT 단일 소스 정렬 — B 워크스페이스 앵커 (2026-10-14)

> **종류**: 정렬 문서 (alignment note) — ADR 개정이 아니다. 소유자가 착지 시점에 승인을 슬롯한다(§5).
> **등록일**: 2026-10-14 (착지 이전 작업 워크트리에서 기계 사실만 고정).
> **동기**: 컴파일된 `TrustSurface` 리터럴(src/cli/merge_cli.nim)이 정책 SSOT(config/policy/merge_admission.json)와 drift했다 — v1.9.0/v1.12.0 수록 경로(`config/trusted_writer_set.json`, `.github/workflows/admission-check.yml`, `.github/workflows/certificate-mint.yml`, `.github/workflows/bsec-integrity.yml`, `experiments/act2-wp-toml-b1-input-integrity/bsec/replay.sh`)가 런타임 판정에서 absent → **2026-10-14 06:47 임의 deny 사고(MG run 38524327637)**. code↔policy 이중 상태가 원인이다.

## 1. 변경 — 단일 소스 (drift의 구조적 소멸)

- 런타임 신뢰면 분류는 더 이상 컴파일 리터럴을 읽지 않는다. `loadTrustSurface`가 평가 시점에 `config/policy/merge_admission.json`의 `trustSurface` 배열을 로드한다(순수 코어 `parseTrustSurfaceJson` + I/O 경계, `loadPinBClosure` 오류 의미론 준수).
- 실패는 항상 fail-closed다: 파일 누락·JSON 파싱 실패·`trustSurface` 배열 부재/비배열/비문자열/빈 문자열·**빈 배열**은 모두 err(빈 집합을 성공으로 읽는 경로 없음 — 빈 신뢰면은 전면 비보호이므로 절대 조용한 pass가 아니다).

## 2. 앵커 — B 워크스페이스 (자기 면제 불가)

- 로드 해상도는 CWD 상대다 — pin@B(`config/trusted_writer_set.json`, merge_cli.nim loadPinBClosure)와 동일한 해상도. MG verdict job은 **B 체크아웃에서 실행**된다(verdict stage: "Checkout executor tree = B").
- 따라서 평가되는 정책은 항상 B의 파일이다: **정책 파일을 수정하는 PR은 자신을 재분류할 수 없다**(candidate H의 정책 사본은 판정 입력이 아니다). 이 성질은 구조적(파일 위치)이며 우연한 구현이 아니다.

## 3. 보존 — protection-retention tombstone

- 삭제된 경로 5개(`auto_merge.yml`, `ci.yml`, `readiness_start.yml`, `verify-candidate.yml`, `canonical-bootstrap/**`)는 정책 SSOT에 없으므로(정책은 생존 면만 수록) 컴파일 `TrustSurfaceTombstones`로 보존하며 매 로드마다 합집합된다. 부활·rename-source 변경은 계속 auto-merge가 deny된다.
- tombstone은 유일하게 남는 컴파일 신뢰면 데이터다. 라이브 면의 컴파일 사본은 존재하지 않는다 — 다시 만들면 drift가 재생된다.

## 4. 동반 기계 사실

- `tools/codeowners_coverage_gate.nim`의 텍스트 추출 다리는 `TrustSurfaceTombstones` 선언을 가리킨다(컴파일 decoupled 규율 유지). 구 `TrustSurface` 리터럴의 재등장은 게이트 fail-closed로 포착된다. 대상 집합 = 정책 `trustSurface`(런타임이 소비하는 그 파일) ∪ tombstone ∪ 고정 추가(AGENTS.md, .github/CODEOWNERS).
- `src/cli/merge_cli.nim` 자신도 신뢰면 파일이다 — 본 변경의 착지는 **exit-0 수동 레인**으로 승인 슬롯 채워 later landing한다(본 문서 범위 밖).

## 5. 승인

승인자: wintrover (소유자 — 세션 전면 허가 + 본 착지 시리즈 승인) · 승인 일시: 2026-10-15 · 근거: 2026-10-14 드리프트 사고(ROT_ALLOWLIST 임의 부인, run 38524327637) + B-앵커 자기면책 부정 증명 테스트
