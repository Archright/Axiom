# Task Process and Skill Mapping

> **정본: AGENTS.md §2.1–2.2.** `main` source mutation 금지·전용 브랜치 workstream·`main` 미커밋 변경 보존(§2.1)과 완료 = 기계 검증 증거 / 발견 ≠ 권한 / 범위 닫힘(§2.2)의 규칙 정본은 AGENTS.md다. 아래 "AGENTS.md §2.1–2.2 원문" 절은 그 정본의 이동 보존된 전문이며, 이 문서는 절차·체크리스트를 보강하지 불변식을 재정의하지 않는다.

Agents must apply the specified technical skills for each task step.

- **3-Step Integrity SOP Operation**: Enforce Context Alignment -> Gherkin Scenario Writing -> TDD Implementation sequence.
- **Design and Architecture**: `src/gate/configs/architecture_rules.json` + `src/gate/runners/architecture_config_gate.nim` (migrated from `architecture-principles` skill; see `docs/agents/plugin-migration.md`)
- **Code Quality and Verification**: pre-commit/pre-push gate pipeline in [docs/agents/quality-gates.md](quality-gates.md) (migrated from `prek-quality-gate` skill)
- **Git Operations**: Git rules in [docs/agents/rules_workflow.md](rules_workflow.md) §2.8 (migrated from `git-atomic-commit` skill)
- **GPA 승격 절차**: 실행 표면·세대 변경 PR은 GPA acceptance 경로를 따른다 — 결정·판정 근거는 [docs/adr/0036-generation-promotion-acceptance.md](../adr/0036-generation-promotion-acceptance.md) (PR #1024 착지 완료 — 4-check required 활성 + manifest: data/promotions/)


## AGENTS.md §2.1–2.2 원문 (추출 2026-10-02)

### 2.1 피처 작업 브랜치 정책 (HARD RULE)

피처, 기능 향상, 리팩터링, 버그 수정, 또는 그 밖의 비사소 규모 구현 작업은 `main`에서 직접 수행해서는 **안 된다**.

이러한 작업을 위해 저장소 파일을 수정하기 전에, 에이전트는 반드시:

1. 현재 Git 상태를 조사한다:

   ```bash
   git status --short --branch
   git branch --show-current
   ```

2. 현재 브랜치가 `main`이면, 전용 작업 브랜치를 생성하고 전환한다:

   ```bash
   git switch -c <descriptive-branch-name>
   ```

3. 브랜치 이름은 수행 중인 작업을 식별해야 한다. 다음을 우선한다:

   * `feature/<short-description>`
   * `fix/<short-description>`
   * `refactor/<short-description>`
   * `chore/<short-description>`

4. 에이전트가 이미 `main`이 아닌 브랜치에 있으면, 작업이 명시적으로 브랜치 격리를 요구하지 않는 한 다른 브랜치를 생성해서는 안 된다.

5. 에이전트는 피처 작업을 `main`에 직접 커밋해서는 안 된다.

6. 구현 시작 전에, 에이전트는 작업 브랜치가 `main`이 아님을 확인해야 한다:

   ```bash
   test "$(git branch --show-current)" != "main"
   ```

#### Main 브랜치 불변식

`main`은 통합 브랜치이지 피처 작업 공간이 아니다.

에이전트는 다음을 불변식으로 취급해야 한다:

> 피처 구현, 리팩터링, 수정, 그 밖의 비사소 규모 저장소 변경은 `main`에서 시작하지 않는다.

에이전트가 `main`에서 커밋되지 않은 변경을 만나면, 절대 조용히 reset/discard/stash/overwrite해서는 안 된다. 기존 작업을 보존하고 안전한 브랜치 전환을 결정한 뒤 진행한다.

#### 완료 경계

구현과 그 필수 검증이 전용 작업 브랜치에서 완료되었을 때에만 작업은 통합 준비 상태로 본다. 에이전트는 코드 변경이 존재한다는 이유만으로 완료를 주장해서는 안 된다.

최종 상태는 다음에서 기계적으로 검증 가능해야 한다:

* 현재 브랜치 이름,
* 저장소 diff,
* 필수 검증 명령과 그 결과.

### 2.2 작업 범위 & 완료 정책

#### 1. 최종 결과(Terminal Outcome)가 권위 있다

모든 작업은 단일의 계산 가능한 최종 결과를 정의해야 한다.

그 결과가 실행 가능한 증거로 입증되었을 때에만 작업은 완료다.

"완료됨", "수정됨", "해결됨", "complete" 같은 에이전트의 주장은 완료 증거가 아니다.

#### 2. 범위는 기본적으로 닫혀 있다

에이전트는 다음을 발견했다는 이유만으로 작업 범위를 확장해서는 **안 된다**:

* 관련 버그
* 아키텍처 개선
* 중복 능력
* 리팩터링 기회
* 미래 확장성 우려
* 더 깨끗한 추상화
* 기술 부채

현재 범위 밖에서 발견된 문제는 `Out of Scope` 또는 `Follow-up`으로 기록하고 건드려서는 안 된다.

#### 3. 발견이 권한을 의미하지 않는다

문제를 발견하는 것이 그것을 고칠 권한을 부여하지 않는다.

다음 구분을 유지해야 한다:

```text
Observation
≠
Task
≠
Authorization to modify
```

새로 발견된 이슈는 현재 최종 결과를 만족시키는 데 직접 필요할 때에만 수정할 수 있다.

#### 4. 범위 확장은 필요성 입증이 필요하다

범위를 확장하기 전에, 에이전트는 다음을 확립해야 한다:

1. 어떤 완료 기준이 추가 변경을 요구하는가,
2. 그 기준이 그것 없이 왜 만족될 수 없는가,
3. 그 요구를 만족시키는 가장 작은 변경은 무엇인가.

"더 나은 아키텍처", "더 깨끗한 설계", "미래를 위해 권장"은 충분한 정당화가 아니다.

#### 5. 최소 변경 선호

여러 유효한 구현 중에서 다음을 만족시키는 가장 작은 변경을 선호한다:

* 최종 결과 만족,
* 기존 신뢰 경계와 불변식 보존,
* 불필요한 추상화 도입 없음,
* 무관한 문제 해결 없음.

#### 6. 조사는 작업 경계 내에 유지한다

현재 최종 결과를 확립하거나 만족시키는 데 필요한 실행 경로, 의존성, 권한 관계만 조사한다.

작업이 명시적으로 요구하지 않는 한 저장소 전체 감사를 수행하지 않는다.

#### 7. 발견과 실행을 분리한다

최종 보고서는 다음을 반드시 구분해야 한다:

```text
이 작업에 필요
구현됨
검증됨
발견했으나 범위 밖
```

범위 밖 발견은 조용히 구현해서는 안 된다.

#### 8. 완화를 근본 권한 분석으로 대체하지 않는다

중복 실행, 반복된 부수효과, 반복 작업이 관측될 때:

1. 실행 권한을 식별한다,
2. 모든 경쟁 권한을 식별한다,
3. 어느 것이 정본인지 확립한다,
4. 불필요한 권한을 제거한다,
5. 그 후에만 retry, cooldown, debounce, concurrency 또는 유사 실행 통제를 고려한다.

#### 9. 기회적 리팩터링 금지

"이미 여기서니까" 무관한 코드를 리팩터링하지 않는다.

나중에 유용할지도 모른다는 이유만으로 제네릭 추상화를 도입하지 않는다.

#### 10. 완료는 기계적으로 확인 가능해야 한다

최종 상태는 실행 가능한 검증 기준을 가져야 한다.

작업 정의·계획·최종 보고서에는 종료를 기계적으로 판정할 **명령과 기대 결과**를 명시한 **Completion Evidence** 섹션을 포함한다. 이 증거가 없으면 완료를 주장할 수 없다.

정성적 서술보다 다음을 선호한다:

```text
command / query
→ observable result
→ pass/fail condition
```


<!-- Extracted from AGENTS.md §2.1–2.2 to keep AGENTS.md under the context-size threshold. -->
