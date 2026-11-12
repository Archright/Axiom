# Local Dev Benchmark — 2026-08-13

> Column: P1 fast-target 도입 전 실측 기준선 (DX 개선을 정량 입증하기 위한 데이터).

## 환경
- 소스: `tests/unit/axiom_ir_test.nim` (대표 유닛)
- Nim 2.2.10, `-d:allowMissingZ3`, gcc, LTO off (debug profile)
- 명령: `nim c --hints:off -d:allowMissingZ3 -o:/tmp/opencode/cN tests/unit/axiom_ir_test.nim`

## 결과

| 단계 | 캐시 정책 | wall clock | Elapsed |
|------|-----------|-----------|---------|
| A. cold (default, hermetic `rmDir`) | 삭제됨 | compile-only | **6.53s** |
| B. 두 번째 build (default) | 삭제됨 (`[hermetic] Clearing ...`) | compile-only | **6.53s** ① |
| C₁. 두 번째 (PRESERVE_CACHE=1) | 보존 | compile-only | 10.42s ② |
| C₂. 세 번째 (PRESERVE_CACHE=1) | 보존 | compile-only | **5.92s** |
| run 1 (cold + 테스트 실행, -r) | 삭제됨 | compile+run | 10.85s |
| run 2 (PRESERVE_CACHE=1, -r) | 보존 | compile+run | 10.21s |
| test-fast (병렬 유닛, exit 0) | 삭제됨 | compile+run+test | **23.5s** |

① B가 A와 동일 ≈ 6.5s: **hermetic `rmDir("build/nimcache")`가 로컬 기본 cmake에서 매 컴파일을 콜드 상태로 강제** (DX 병목 주범 확정).
② C₁의 10.42s는 첫 보존 실행의 gate-runner 재해시/히트웨이밍 오버헤드로 보임 (C₂에서 5.92s로 수렴).

## 구분
- **compile+link**: cold ≈ 6.5s → warm ≈ 5.9s (약 9% 개선)
- **test 실행 (`-r`)**: ≈ 4–5s 추가 (컴파일과 별개 코스트)
- **test-fast (병렬 유닛, exit 0)**: 23.5s wall clock — 컴파일+링크+병렬 유닛 실행 포함, exit 0 확인 완료
- **지배 비용**: `ci-unit-tests`의 `nimble build` + `nimble install` (bin/ax 재링크) + 20개 직렬 컴파일 → 단일 수정 후 수 분.

## P1 도입 후 예상
- `AXIOM_CI_PRESERVE_CACHE=1` 캡슐화 → warm 빌드 유지, gate-runner 재해시 분기 제거.
- `nimble build/install` 생략 + no release/LTO + 병렬 유닛 → 편집-검증 루프를 분 단위에서 초/저분 단위로.