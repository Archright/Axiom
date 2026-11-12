# Hermetic Z3 Version Pinning

## Motivation

이 문서는 `config.nims`의 `hermeticBuildEnv` 블록에서 Z3 버전을 처리하는 아키텍처 변경을 기록한다.

### Problem (기존 방식의 문제점)

1. **비밀폐형 빌드**: `gorge("z3 --version")`로 호스트 환경에서 Z3 버전을 발견(discover)하면, 개발자마다 다른 버전이 빌드에 포함됨
2. **취약한 문자열 스크래핑**: `awk '{print $3}'`은 Z3 CLI 출력 형식 변경에 취약 (`4.13.3` vs `release-4.13.3` vs `4.13.3 (64-bit)`)
3. **이중 생산자**: `tools/hermetic_build.nim`과 `config.nims`가 모두 `build_env.nim`을 생성 — 동기화 부채

### Solution: Sole Producer + Declaration+Validation

- **Sole Producer**: `config.nims`가 `src/generated/build_env.nim`의 유일한 생산자
- **Declaration**: `const ExpectedZ3Version = "4.13.3"` — 프로젝트가 요구하는 버전을 상수로 선언
- **Validation**: 빌드 시 호스트 Z3가 선언된 버전과 일치하는지 검증
- **Explicit Bypass**: Z3 미설치 시 `-d:allowMissingZ3` 명시적 우회만 허용

## Architecture

```
config.nims (Sole Producer)
  ├── const ExpectedZ3Version = "4.13.3"     ← Declaration
  ├── gorge("z3 --version") → Validation     ← Validation
  └── writeFile(buildEnvPath, newContent)     ← Generation (상수 직접 사용)

tools/hermetic_build.nim (Consumer, Z3 무지)
  └── build_env.nim을 읽기만 함 (생성 안 함)
```

## Z3 업그레이드 절차

1. 새 Z3 버전 설치
2. `config.nims`의 `ExpectedZ3Version` 상수 업데이트
3. `nim c`로 빌드 검증 (Z3 버전 불일치 시 빌드 중단 확인)
4. 커밋

## Explicit Bypass Flag

| 시나리오 | 명령어 | 결과 |
|----------|--------|------|
| Z3 4.13.3 설치됨 | `nim c` | ✅ 빌드 성공, `BuildEnvZ3Version = "4.13.3"` |
| Z3 미설치 | `nim c` | ❌ 빌드 중단 (exit 1) |
| Z3 미설치 + 우회 | `nim c -d:allowMissingZ3` | ✅ 빌드 성공, `BuildEnvZ3Version = "unknown"` |
| Z3 다른 버전 | `nim c` | ❌ 빌드 중단 (exit 1) |

## Related

- AGENTS.md §0.5b (Quirk Documentation Mandate)
- AGENTS.md §0.3 (Trust Boundaries — Hermetic Build)
- docs/spec/nim_effect_system_quirks.md §14 (Hermetic Build Orchestrator v28)
