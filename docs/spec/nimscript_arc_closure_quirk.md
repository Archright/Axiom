# NimScript ARC Closure Quirk (task-local closure + `mm:arc`)

> 이 문서는 NimScript(nims) `task` 본문 안에서 task 지역 변수를 참조하는 proc(=closure)이
> `switch("mm", "arc")` 하에서 VM에서 **컴파일 자체가 불가능**하다는 Nim 2.2.10 툴체인 quirk를
> 기록한다. nims 태스크를 수정하는 모든 에이전트는 이 문서를 먼저 읽어야 한다.
> AGENTS.md §0.5 — Quirk Mandate (Documentation-First)의 실행 부속서다.
> 발견 계기: DEBT#524 슬라이스(2026-11-14) — `nim buildGateRunners` 복구.

---

## §1. Symptom (실측, 2026-11-14)

```
$ nim buildGateRunners
[integrity] merkle concat: ...
[Axiom] Checking feature_manifest.json freshness (content-hash)...
config.nims(181, 22) Error: system module needs: nimDestroyAndDispose
```

- 메인 클론과 worktree 양쪽에서 **동일하게** 실패 (9d44c4a 및 d4bbbe1 베이스에서 재현,
  nim 2.2.10 choosenim).
- `nim buildGateRunners`는 DEBT#517/518 조사(2026-11-08)에서 "자동 호출자 0건"으로
  확인된 수동 태스크라 이 실패가 조용히 잠복해 있었다.
- 태스크 본문 실행 전(semantic analysis 단계)에 중단 — 실패는 파일 상태와 무관하다.

## §2. Root cause

1. `config/effects.nims:16`의 `switch("mm", "arc")` — 전역 ARC 메모리 모델 (Phase 16).
2. `task buildGateRunners` 본문 내부의 `proc getStoredHash`가 task 지역
   `var prevHashes`를 참조 → **closure 환경 생성**.
3. ARC closure lowering은 `nimDestroyAndDispose` compilerproc을 요구하지만, nims 실행용
   system 모듈에는 해당 심볼이 등록되어 있지 않다 → `magicsys` 조회 실패 →
   `localError "system module needs: nimDestroyAndDispose"`.

전제 조건이 **세 가지의 곱**이다: (a) nims 태스크 본문 내부 proc, (b) 그 proc이 task
지역 var 참조, (c) `mm:arc`. 하나라도 없으면 발생하지 않는다:

- top-level var + top-level proc (closure 아님) → 정상 (실측).
- task 본문 proc이 지역 var을 참조하지 않으면 closure가 아니므로 이론상 안전
  (본 저장소에서 해당 사례는 buildGateRunners가 유일).

## §3. Reproduction (minimal)

```nim
# config.nims
import std/[strutils, os]

switch("mm", "arc")

task tprobe, "probe":
  var xs: seq[(string, string)] = @[]
  proc f(bin: string): string =   # xs 캡처 → closure
    for (b, h) in xs:
      if b == bin: return h
    ""
  echo f("x")
```

```
$ nim tprobe
config.nims(11, 8) Error: system module needs: nimDestroyAndDispose   # exit 1
```

`var`/`proc`을 top-level로 올리면 (task가 top-level var을 mutate하는 것 포함) exit 0.

## §4. Fix pattern

**closure를 만들지 마라**: 태스크 본문 안의 proc이 지역 변수를 필요로 하면
해당 `var` + `proc`을 top-level로 호이스트하라 (lookup 의미는 동일 — top-level
nims var은 스크립트 전역이다). `mm:arc`를 건드리는 대안(스위치 제거/refc 전환)은
컴파일 산출물의 메모리 모델 계약을 깨뜨리므로 금지.

적용: `config.nims` `buildGateRunners`의 `prevHashes`/`getStoredHash` 호이스트
(DEBT#524 슬라이스 — `nim buildGateRunners` exit 0 복구 커밋). 태스크 본문의 나머지
논리는 불변.

## §5. 영향 범위 (2026-11-14 실측)

- 저장소 내 nims 태스크 중 task 본문 내부 proc을 가진 것은 `buildGateRunners`가
  유일 — 나머지는 `exec` 호출뿐.
- `config/*.nims` include의 proc들은 include 확장 후 top-level이므로 무관.
- Nim 2.2.10 (저장소 pinned, choosenim). 상위 Nim 버전에서의 해소 여부는 미검증.

