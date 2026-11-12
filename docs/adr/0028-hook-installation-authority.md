# ADR-0028: git hook 설치 권위 단일화 — `core.hooksPath`의 authority · sole writer · 집행 수단 분리

## Status

**Accepted (2026-10-04)** — 결정 영역 **D1 (git hook 설치 권위)**의 권위 선언 그 자체다.
아래 §Decision의 authority·writer·device 3분리는 이 ADR이 처음 선언하며, 경쟁 writer
(`axiom.nimble` `task hooks`)의 폐기는 **본 ADR과 동일 착지**에서 이루어진다. §Consequences의
잔여 ①~③은 **해소되지 않은 상태로 기록된 잔여**다.

## Context

### 경쟁하는 두 writer

| writer | 호출 | 값 |
|---|---|---|
| `tools/setup_hooks.nim:15` | `execCmdEx("git config core.hooksPath .githooks")` | `.githooks` — 의도된 writer |
| `axiom.nimble` `task hooks` (삭제 전 `:41-88`) | `exec "git config core.hooksPath hooks"` | `hooks` — bare `exec`이므로 repo-local |

`task hooks`는 스텁 4개(`hooks/pre-commit`, `hooks/pre-push`, `hooks/commit-msg`,
`hooks/prepare-commit-msg`)를 `mkDir("hooks")`로 생성해 git에 넘긴다.

### 왜 `hooks`는 침묵한 무력화인가

`.gitignore:189-190`이 `hooks/*`를 무시하고 `!hooks/.gitkeep`로 역예외를 예약한다. 그러나
**예약은 dangling이다** — `git ls-files hooks/`는 0건을 반환하고 `hooks/.gitkeep`은 추적되지
않는다. 즉 retired writer가 지정한 디렉터리에는 git이 추적하는 진입점이 존재하지 않는다.
그 결과 버전 관리되는 `.githooks/pre-commit`(mode 100755)과 `.githooks/pre-push`(mode 100755)가
조용히 비활성화된다 — 게이트 실패도, 메시지도 없다.

### advisory 2곳

`config/integrity.nims`와 `src/gate/config.nims:23-24` 모두 `"WARNING: Git hooks not
configured. Run: nimble hooks"`를 출력해 사용자를 경쟁 writer로 안내한다. 후자는 `src/gate/**`
FROZEN 표면이라 본 착지에서 고칠 수 없다(잔여 ①).

### 정규값을 선언한 커밋된 정책은 없었다

"어느 값이 정본인가"에 답하는 문서가 저장소에 존재하지 않았다. 존재하는 것은 다음뿐이다.

- `config/repository_surface.json:221` — FROZEN glob 목록의 `.githooks/**`. 정규값 선언이 아니라
  **보호 대상 나열**이다(값을 말하지 않는다).
- `docs/spec/repository_surface_contract.md:68` — "로컬 집행 훅의 설치 위치와 구현"이라는 서술.
  값이 아니라 역할 기술이다.
- `src/generated/build_metadata.json:6` — `"hooksPath": ".githooks"`. **관측된 상태의 파생
  스냅샷**(`tools/build_metadata_generator.nim:99`가 `execCmdEx("git config core.hooksPath
  2>/dev/null")` 결과를 기록)이며 선언이 아니다. 생성 이후 쓰인 값은 갱신 전까지 반영되지 않는다.

이 공백이 두 writer를 배양했다: 어느 쪽이 "진짜"인지 규칙이 없으므로 둘 다 합법적으로 보인다.

## Decision

**세 가지를 혼합하지 않는다.** authority(결정권) · writer(기록 권한) · device(집행 수단)는
서로 다른 층이다.

| 층 | 결정 |
|---|---|
| **(a) authority — 정책값** | `core.hooksPath = .githooks` |
| **(b) sole writer — 기록 권한** | `tools/setup_hooks.nim` — 그 키에 값을 쓸 수 있는 **유일한** 코드 |
| **(c) device family — 집행 수단** | tracked `.githooks/pre-commit` + `.githooks/pre-push` |

설치 명령 = **`make -f ci/checker.mk setup-hooks`** (`ci/checker.mk:316-320`:
`bin/setup-hooks` ← `tools/setup_hooks.nim`).

### 판정 단일성 규칙 (adjudication-singularity rule)

> 하나의 결정에는 하나의 adjudicatory authority와 하나의 writer가 있어야 한다. 독립 검증자는
> 여러 개일 수 있으나, 같은 결정에 대해 (i) 서로 모순될 수 있는 판정을 독립적으로 생산하거나
> (ii) 서로 결합(bind)할 수 없는 rule table·면제 수단으로 판정하는 경쟁 adjudicator가 되어서는
> 안 된다. (위반 형태: V1 경쟁 판정자 / V2 경쟁 작성자 / V3 비결합 검증자. Authority는 결정권,
> Device는 집행 수단.)

### 새로 추가되는 것은 binding/plurality 절 하나뿐 — 나머지는 기존 코퍼스

이 규칙의 대부분은 이미 존재한다. 중복 발명하지 않고 참조한다.

- `AGENTS.md:139` — **Per-output authority** / "Authority ≠ Adapter"
- `AGENTS.md:162` (§2.6) — 산출물당 생성 authority는 하나
- `docs/agents/authority_invariant_protocol.md:16` — single-writer 점검 항목 ·
  `:112-124` — FACT(믿어야 할 사실) vs METHOD(실행 수단) 분리
- `docs/adr/0026-execution-authority-unification.md:30,217` — 권위 행위 single-writer 봉인 선례
- `docs/spec/merge_admission_controller.md:33-35` — **이미 실행된 선례**: 플랫폼의 ruleset을
  CLI 안에서 재판정하던 `--arm-auto` lane 제거 (경쟁 adjudicator 제거)

### 읽는 자는 경쟁 adjudicator가 아니다

`src/gate/runners/gate_self_check.nim:53,96`, `src/gate/runners/gate_hook.nim:110`,
`tools/build_metadata_generator.nim:99`, `tools/hermetic_build.nim:1264`는 이 키를 **읽는다**.
읽기는 writer 권한이 아니며 판정을 생산하지도 않는다(`AGENTS.md:139` — Authority ≠ Adapter).
reader를 writer로 승격시키지 않는 것이 이 결정의 일부다.

## Retired

- **`axiom.nimble` `task hooks`** — 경쟁 writer(V2). writer이면서 gitignored 디렉터리의 생성자로
 서 **생성 authority**(설치 상태의)와 **기록 authority**(git config 값의) 두 자리를 동시에
점유했다.
- **"Run: nimble hooks" 안내** — `config/integrity.nims`는 `make -f ci/checker.mk setup-hooks`
  로 교체. `src/gate/config.nims:24`의 동일 문자열은 FROZEN이라 잔존한다(아래 ①).

## Consequences

**긍정:** `core.hooksPath`의 값과 기록 주체가 각각 1개로 고정된다. 설치 상태가 실제 enforcement
device(tracked 훅)를 가리키는지 여부가 컴파일 advisory로 관측된다. `tests/unit/test_setup_hooks.nim`
이 tracked 소스 전체를 스캔해 writer가 `tools/setup_hooks.nim` 하나임을 단정한다 — 새 경쟁 writer
추가는 그 테스트를 깨뜨린다.

### Open residuals (해소되지 않음 — 아래 3건은 현재 상태 그대로다)

**① `src/gate/config.nims:23-24` — 잘못된 경로 probe + dangling 문자열.**
이 블록은 `.git/hooks/pre-commit`의 **파일 존재 여부**를 본다. 그 경로는 git 스톡 기본값 아래에서만
존재하며 `core.hooksPath = .githooks` 상태에서는 존재하지 않는다. 따라서 `.git/hooks/pre-commit`가
없는 머신에서는 **`src/gate/**` 컴파일마다** 이 경고가 발화한다. 게다가 여전히
`"Run: nimble hooks"`를 출력하는데, 그 writer는 본 착지에서 삭제된다 — dangling 안내가 된다.
`src/gate/**`는 FROZEN이므로 본 워크스트림에서 고칠 수 없다. 제거하려면 **표면 정책 변경**
(`config/repository_surface.json`)이 선행되어야 한다. → follow-up.

**② `docs/spec/break_glass_protocol.md`의 commit-msg stage 도달 불가.**
fail-secure reconciliation(`src/gate/runners/gate_hook.nim:244-247`, dispatch `:463-465`)은
`commit-msg` stage에서만 실행된다. 그 stage의 유일한 호출자는 retired writer가 만들던
`hooks/commit-msg`였다. `hooks/`가 gitignored이므로 **실질적으로 이미 도달 불가**였고, 정규값을
`.githooks`로 고정해도 그 사실은 변하지 않는다(정규 훅 세트에 commit-msg가 없다). 복구는
`.githooks/commit-msg` 추가를 요구하는데 `.githooks/**`는 FROZEN이다. → follow-up.

**③ 관측 vs 선언의 분리 — static check는 설치 값을 단정하지 않는다.**
*소스 수준 사실*(writer가 정확히 1개)과 *설치 상태*(`git config --local core.hooksPath`)는
**시점도, 술어도 다른 서로 다른 술어**다. fresh clone에서 이 키가 비어 있는 것은 정상이다 —
git의 문서화된 기본값(`$GIT_DIR/hooks`)이며, 이를 **EXPECTED-PRE-INSTALL-DEFAULT**로 라벨한다.
그 상태는 "`setup-hooks` 실행 전에는 Axiom 훅이 하나도 돌지 않는다"를 뜻하지 결함이 아니다.
따라서 정적 검사(컴파일 시점 advisory)는 설치 값을 **단정하지 않고 관측만 보고**한다.
이 구분을 무시하면 같은 모순이 재도입된다.

## References

- `tools/setup_hooks.nim:15` — sole writer · `ci/checker.mk:316-320` — 설치 명령
- `.gitignore:189-190` · `.githooks/pre-commit`(100755) · `.githooks/pre-push`(100755)
- `AGENTS.md:139` · `AGENTS.md:162` · `docs/agents/authority_invariant_protocol.md:16,112-124`
- `docs/adr/0026-execution-authority-unification.md:30,217` · `docs/spec/merge_admission_controller.md:33-35`
- 잔여 ① `src/gate/config.nims:23-24` · 잔여 ② `src/gate/runners/gate_hook.nim:244-247,463-465`
- 파생 스냅샷(선언 아님) `src/generated/build_metadata.json:6` · `tools/build_metadata_generator.nim:99`

---

*작성일: 2026-10-04. Accepted — D1 권위 선언. 잔여 ①~③은 해소된 것으로 취급하지 않는다.*