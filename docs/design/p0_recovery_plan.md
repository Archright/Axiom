# P0-only Commit 복구 계획 (Controlled Recovery Plan — 실행 아님)

## 1. 목표

잘못된 커밋 `6c435b5cf`(3 의도 + 3 보호)에서 보호 3파일을 분리하여, P0 3파일만 포함하는 정상 커밋을 `origin/main` 위에 재구성한다. 보호 3파일은 source of truth로서 어떤 단계에서도 내용이 변하지 않도록 보존한다.

- **의도 P0 3파일**: `tools/ci/local_ci_gates.nim`, `docs/guides/local_exact_gate.md`, `tests/unit/test_local_ci_gates.nim`
- **보호 3파일**: `docs/DEBT_REGISTRY.md`, `src/generated/debt_constants.nim`, `src/generated/type_registry_metadata.json`
- **기존 커밋**: `6c435b5cf` — forensic evidence로 보존, 삭제하지 않음
- **대상 상태**: P0 3파일만 main 위에 독립 존재하는 정상 커밋

## 2. 불변조건 (invariants)

1. `6c435b5cf`는 forensic evidence로 보존 — 삭제, amend, reset으로 소거하지 않음
2. 보호 3파일 내용은 어떤 단계에서도 worktree/객체 내용이 손상되지 않도록 무변경 보존
3. push/PR은 복구 승인 후에만 수행
4. 기본 원칙: 보호 3파일 = source of truth, P0 3파일만 정상 commit으로 재구성
5. 이 문서는 계획(plan)이며, 실행 명령이 아님

## 3. 옵션 비교

### 옵션 A: 새 작업 branch에서 `origin/main` 재분기 → P0 3파일만 새 커밋

- **동작**: `origin/main`에서 새 branch 생성 → P0 3파일만 checkout/stage → `bin/axiom-gate commit` 또는 `git commit`으로 커밋 → 보호 파일은 해당 branch에서 dirty가 아님
- **위험**: 낮음 — 새 branch이므로 기존 `6c435b5cf`와 완전히 격리됨. 보호 파일이 worktree에 존재하지 않으므로 auto-stage 오염 불가
- **증거 보존**: `6c435b5cf`는 원래 branch `p0-local-exact-gate`에 그대로 남아 forensic evidence 유지
- **권장 여부**: ✅ **권장** — 보호 파일과 P0 파일의 물리적 분리가 가장 깔끔하고, `axiom-gate commit`의 auto-stage 문제를 우회할 수 있음

### 옵션 B: 현재 `p0-local-exact-gate`를 soft reset으로 되돌린 뒤 3파일만 재-commit

- **동작**: `git reset --soft 0be7fd3f` (HEAD를 parent로 되돌리되 working tree 유지) → 보호 3파일을 `git reset HEAD`로 unstage → P0 3파일만 stage → 재커밋
- **위험**: 중간 — `git reset --soft` 후 보호 파일이 working tree에 dirty 상태로 남아 `axiom-gate commit` auto-stage에 오염될 수 있음. `git reset --mixed`로 하면 working tree도 초기화되어 보호 파일 내용이 손실될 위험
- **증거 보존**: `6c435b5cf`는 reflog에 남지만, branch HEAD가 이동됨. reflog로 복구 가능하나 forensic trace가 약화됨
- **권장 여부**: ⚠️ **비권장** — 보호 파일이 worktree에 dirty로 남는 한 `axiom-gate commit` 사용 시 재오염 위험이 본질적임. reset 자체가 기존 커밋 히스토리를 변경하는 것처럼 보일 수 있어 forensic 명확성 저하

### 옵션 C: `bin/axiom-gate commit`의 auto-stage contract를 우회하는 방식

- **동작**: 보호 3파일을 일시적으로 worktree에서 제거(backup) → P0 3파일만 stage → `axiom-gate commit` 실행 → 보호 파일 내용 복원. 또는 `git commit`을 직접 사용하여 `axiom-gate`의 auto-stage를 우회
- **위험**: 높음 — 보호 파일을 backup/복원하는 과정에서 내용 불일치 가능성. `axiom-gate commit`이 auto-staging하는 동안 보호 파일이 dirty가 아닌 "공백 구간"을 만들어야 하므로, 그 사이 worktree 상태가 비정상. 이 옵션은 "보호 파일 내용 무변경" 원칙과 양립하기 위해 worktree에 동일 내용을 복원해야 하는데, 복원 시점의 정확성 보장이 어려움
- **증거 보존**: `6c435b5cf`는 원래 branch에 남지만, 과정 중 worktree가 보호 파일 없이 동작하므로 일시적 상태 불일치 발생
- **권장 여부**: ❌ **비권장** — 보호 파일을 worktree에서 제거하는 행위 자체가 "보호 파일 내용 무변환" 원칙의 spirit에 위배됨. `axiom-gate commit`의 auto-stage contract(`docs/guides/axiom_gate_commit_staging_contract.md` 참조)를 우회하는 것은 도구 계약 위반이며, 복원 과정에서 human error 가능성이 있음

## 4. 적용 순서 (승인 후 실행 단계) — 옵션 A 기준

### 1단계: 현재 상태 증거 확보
```bash
git show 6c435b5cf --name-status > /tmp/p0_recovery_evidence_6c435b5cf.txt
git diff 6c435b5cf^..6c435b5cf -- docs/DEBT_REGISTRY.md src/generated/debt_constants.nim src/generated/type_registry_metadata.json > /tmp/p0_protected_diffs.txt
git status --short
```
- **rollback**: 없음 (읽기 전용)

### 2단계: 새 작업 branch 생성 (`origin/main`에서)
```bash
git checkout -b p0-recovery origin/main
```
- **rollback**: `git checkout p0-local-exact-gate` 로 되돌리기

### 3단계: P0 3파일만 checkout
```bash
git checkout 6c435b5cf -- tools/ci/local_ci_gates.nim docs/guides/local_exact_gate.md tests/unit/test_local_ci_gates.nim
```
- **rollback**: `git checkout origin/main -- tools/ci/local_ci_gates.nim docs/guides/local_exact_gate.md tests/unit/test_local_ci_gates.nim` 후 `git checkout p0-local-exact-gate`

### 4단계: 보호 3파일이 worktree에 존재하지 않음을 확인
```bash
git status --short
# 예상: M tools/ci/local_ci_gates.nim, M docs/guides/local_exact_gate.md, M tests/unit/test_local_ci_gates.nim 만 표시
# 보호 3파일이 나타나면 안 됨
```
- **rollback**: `git checkout -- .` 후 `git checkout p0-local-exact-gate`

### 5단계: 커밋 실행 (axiom-gate 또는 git 직접 사용)
```bash
# axiom-gate 사용 시: 보호 파일이 worktree에 없으므로 auto-stage 오염 없음
bin/axiom-gate commit --message "feat(ci): add local exact gate CLI tool for deterministic local verification [P0 recovery]" tools/ci/local_ci_gates.nim docs/guides/local_exact_gate.md tests/unit/test_local_ci_gates.nim
# 또는 git 직접 사용:
git commit -m "feat(ci): add local exact gate CLI tool for deterministic local verification [P0 recovery]"
```
- **rollback**: `git reset --hard HEAD~1`

### 6단계: 커밋 검증 — 보호 3파일 부재 확인
```bash
git show --name-status HEAD
# P0 3파일만 있어야 함. 보호 3파일이 절대 나타나면 안 됨
git diff HEAD~1..HEAD -- docs/DEBT_REGISTRY.md src/generated/debt_constants.nim src/generated/type_registry_metadata.json
# 위 diff가 비어있어야 함
```
- **rollback**: `git reset --hard HEAD~1`

### 7단계: `git show`로 P0 커밋 내용 전체 검증
```bash
git show --stat HEAD
git show HEAD:tools/ci/local_ci_gates.nim | wc -l
git show HEAD:docs/guides/local_exact_gate.md | wc -l
git show HEAD:tests/unit/test_local_ci_gates.nim | wc -l
```
- **rollback**: `git reset --hard HEAD~1`

### 8단계: push (승인 후에만)
```bash
git push -u origin p0-recovery
```
- **rollback**: `git push origin --delete p0-recovery` (remote에 올라간 경우)

### 9단계: PR 생성 (승인 후에만)
- base: `main`, head: `p0-recovery`
- 설명에 `6c435b5cf`가 forensic evidence로 보존됨을 명시

## 5. 검증 게이트 (recovery acceptance)

| 검증 항목 | 명령 | 기대 결과 |
|---|---|---|
| 복구 커밋 diff == P0 3파일만 존재 | `git diff main..p0-recovery --stat` | 정확히 3개 파일 (P0 3파일) |
| 보호 3파일이 복구 커밋에 없음 | `git diff main..p0-recovery -- docs/DEBT_REGISTRY.md src/generated/debt_constants.nim src/generated/type_registry_metadata.json` | 빈 출력 |
| `6c435b5cf`가 보존됨 | `git show 6c435b5cf --name-status` | 원래 6개 파일 모두 표시 |
| 보호 3파일 내용 digest 동일 | `git show 6c435b5cf:docs/DEBT_REGISTRY.md \| sha256sum` vs `git show origin/main:docs/DEBT_REGISTRY.md \| sha256sum` | 동일한 hash |
| P0 3파일 내용 digest 동일 | `git diff 6c435b5cf..p0-recovery -- tools/ci/local_ci_gates.nim docs/guides/local_exact_gate.md tests/unit/test_local_ci_gates.nim` | 빈 출력 (차이 없음) |
| `p0-local-exact-gate` branch 존재 | `git branch p0-local-exact-gate` | 존재함 (evidence 보존) |

모든 게이트 통과 후에만 push/PR 진행.

## 6. 원인 방지 (재발 방지)

1. **`bin/axiom-gate commit`을 보호 dirty 존재 하에서 파일 리스트와 함께 사용하지 않음** — 이 도구는 명시적 파일 리스트를 무시하고 dirty working-tree를 auto-staging함. 보호 파일이 dirty이면 자동으로 포함됨. `docs/guides/axiom_gate_commit_staging_contract.md` 참조.
2. **commit 전에 반드시 `git status --short` + `git show --name-status HEAD`로 포함 파일 검증** — 커밋 후가 아니라 커밋 직전(또는 stage 후 커밋 직전)에 포함 파일 목록을 확인.
3. **보호 파일과 P0 파일을 같은 worktree에서 동시에 stage하지 않음** — 옵션 A처럼 물리적으로 분리된 branch에서 작업하여 근본적으로 방지.
4. **커밋 메시지에 `[P0 recovery]` 태그를 포함** — 향후 grep으로 복구 커밋을 식별 가능.

## 7. 보류 사항

- 이 문서는 계획(plan)일 뿐이며, 실행/승인 대기 상태임
- 어떤 단계도 아직 실행하지 않음
- 복구 실행 전 반드시 승인을 받을 것
- `6c435b5cf`는 어떤 경우에도 삭제/amend/reset하지 않음

---

Recovery plan owner: P0 incident / Date: 2026-09-02 — NOT EXECUTED, awaiting approval
