# Sync Daemon Git Quirks 레지스트리

> 이 문서는 `bin/integration-daemon` 구현 과정에서 발견한 Git 동작 특이사항을 기록합니다.
> 모든 에이전트는 sync daemon 관련 변경 시 이 문서를 먼저 참조해야 합니다.
> AGENTS.md §0.5b (Quirk Documentation Mandate)의 실행 부속서입니다.

---

## §1. `git update-ref` vs `git branch -f`

### 1.1 문제

`bin/integration-daemon`은 shadow worktree의 브랜치 포인터를 대상 커밋으로 강제 갱신해야 합니다. 두 가지 방법이 존재합니다:

| 명령어 | 동작 |
|--------|------|
| `git branch -f <branch> <commit>` | 브랜치 ref를 직접 갱신하지만, **현재 체크아웃된 브랜치에는 사용 불가** |
| `git update-ref refs/heads/<branch> <commit>` | ref 파일을 직접 갱신. 체크아웃 상태와 무관하게 동작 |

### 1.2 이유

`bin/integration-daemon`은 shadow worktree에서 `git fetch` 후 브랜치 포인터를 갱신합니다. shadow worktree가 해당 브랜치에 **체크아웃된 상태**일 때 `git branch -f`를 사용하면 Git이 에러를 반환합니다:

```
fatal: Cannot force update the current branch.
```

`git update-ref`는 이 제한을 우회합니다 — ref 파일을 직접 수정하므로 체크아웃 상태와 무관하게 동작합니다.

### 1.3 주의사항

- `git update-ref`는 **reflog를 생성하지 않습니다**. 실수로 갱신하면 되돌리기 어렵습니다.
- daemon은 갱신 전 **현재 commit 해시를 백업**하여 `git update-ref` 실패 시 복구할 수 있도록 합니다.
- `git update-ref -d` (삭제)는 절대 사용하지 않습니다 — 브랜치 ref 삭제는 의도하지 않은 분기 포인터 사라짐을 유발합니다.

**근거**: Git 문서 `git-update-ref(1)` — "Update the object name stored in a ref safely." 체크아웃 브랜치 제한은 `git branch(1)` 구현의 제약사항입니다.

---

## §2. `GIT_OPTIONAL_LOCKS=0`

### 2.1 문제

Git은 `git status`, `git diff`, `git fetch` 등 다수의 명령을 실행할 때 **잠금 파일** (`.git/index.lock`)을 생성합니다. 동시에 실행되는 Git 명령이 많아지면 lock contention이 발생하여 명령이 실패하거나 대기합니다.

```
fatal: Unable to create '/path/to/.git/index.lock': File exists.

Another git process seems to be running in this repository, e.g.
an editor opened by 'git commit'. Please make sure all processes
are terminated then try again.
```

### 2.2 이유

`bin/integration-daemon`은 **백그라운드에서 반복적으로 Git 명령을 실행**합니다. 에이전트 세션도 동시에 `git status`, `git diff`, `git commit` 등을 실행하므로 lock contention이 빈번합니다.

`GIT_OPTIONAL_LOCKS=0`은 Git에 **잠금 파일을 생성하지 말 것**을 지시합니다. 이 환경 변수가 설정되면:

| Git 명령 | 영향 |
|-----------|------|
| `git status --porcelain` | index.lock 없이 실행. 읽기 전용이므로 안전 |
| `git diff` | index.lock 없이 실행. 읽기 전용이므로 안전 |
| `git fetch` | **index.lock이 여전히 생성됨** — fetch는 refspec을 쓰므로 불가피 |
| `git merge` | **index.lock이 여전히 생성됨** — 워킹 디렉토리를 수정하므로 불가피 |

### 2.3 적용 범위

daemon의 **파일워처 폴링 루프**에서만 `GIT_OPTIONAL_LOCKS=0`을 사용합니다:

```bash
# Polling — 읽기 전용, lock 불필요
GIT_OPTIONAL_LOCKS=0 git status --porcelain

# Sync cycle — 쓰기 포함, lock 필요
git fetch origin
git merge --ff-only
```

**근거**: Git 문서 `git(1)` 환경 변수 섹션 — `GIT_OPTIONAL_LOCKS`: "If set to 1, do not use any optional locks."

---

## §3. `git status --porcelain` 선행 확인

### 3.1 문제

`git merge --ff-only`는 워킹 디렉토리가 **완전히 깨끗**해야 성공합니다. 워킹 디렉토리에 uncommitted 변경사항이 있으면:

```
error: Your local changes to the following files would be overwritten by merge
```

또는:

```
error: Pulling is not possible because you have unmerged files.
```

### 3.2 이유

`bin/integration-daemon`은 shadow worktree에서 `git merge --ff-only`를 실행합니다. shadow worktree에는 에이전트가 직접 작업하지 않지만, Git 내부��作 (예: `git stash`, `git checkout`)이나 외부 프로세스가 임시로 워킹 디렉토리를 오염시킬 수 있습니다.

**`git status --porcelain`을 먼저 실행하여 워킹 디렉토리가 깨끗한지 확인합니다:**

```bash
# 1단계: 워킹 디렉토리 확인
dirty=$(GIT_OPTIONAL_LOCKS=0 git status --porcelain)
if [ -n "$dirty" ]; then
  echo "WARN: shadow worktree dirty, skipping merge"
  exit 0  # 실패가 아니라 스킵
fi

# 2단계: 안전하게 fast-forward merge
git merge --ff-only origin/main
```

### 3.3 `--porcelain`이 필요한 이유

| 출력 형식 | 안정성 | 이유 |
|-----------|--------|------|
| `git status` (사람용) | ❌ | 출력 포맷이 Git 버전마다 다름. 파싱 불가 |
| `git status --porcelain` | ✅ | 기계 파싱용 안정적 포맷. Git 2.x 전 버전 호환 |

**`--porcelain` 플래그 없이 `git status` 출력을 파싱하는 것은 금지합니다.** 출력 형식이 Git 버전, 로케일, 터미널 크기에 따라 변합니다.

**근거**: Git 문서 `git-status(1)` — `--porcelain`: "Give the output in an easy-to-parse format for scripts."

---

## §4. TOCTOU Race와 Git의 Merge 거부

### 4.1 문제

**TOCTOU (Time of Check to Time of Use)** race condition:

```
시간 0: daemon이 git status --porcelain → 깨끗함 확인
시간 1: 외부 프로세스가 shadow worktree에 파일 변경
시간 2: daemon이 git merge --ff-only → 실패 (워킹 디렉토리 더러움)
```

### 4.2 이유

daemon과 Git 명령 사이에 시간 간격이 존재합니다. 이 간격 동안 워킹 디렉토리가 변경될 수 있습니다.

### 4.3 Git의 방어 메커니즘

Git은 `git merge --ff-only` 실행 시 **실시간으로** 워킹 디렉토리를 재검사합니다. `git status --porcelain`에서 깨끗하다고 확인했더라도, `git merge --ff-only` 실행 시점에 더러워져 있으면 **Git 자체가 merge를 거부합니다**:

```
error: Your local changes to the following files would be overwritten by merge
fatal: Cannot merge: Working tree has modifications in the following paths:
  src/some_file.nim
```

이것이 **최종 방어선**입니다:

```
[daemon check] ──TOCTOU gap──> [Git merge check]
     │                                │
     ▼                                ▼
  깨끗함 확인                    Git 자체가 거부
  (과거 상태)                    (현재 상태)
```

### 4.4 정책

- daemon은 TOCTOU race를 **완전히 제거할 수 없음** — 구조적 한계.
- daemon은 `git status --porcelain`으로 **가능한 최신 상태**를 확인.
- Git은 `git merge --ff-only`에서 **최종 안전장치** 역할.
- race 발생 시 daemon은 **스킵** (에러가 아님) — 다음 사이클에서 재시도.

**근거**: Git 문서 `git-merge(1)` — `--ff-only`: "Refuse to merge unless the current HEAD is already an ancestor of the other branch, or if the working tree or the index has local changes."

---

## §5. 요약: 4중 방어 체인

```
Layer 1: GIT_OPTIONAL_LOCKS=0  →  lock contention 방지 (읽기 전용 폴링)
Layer 2: git status --porcelain →  워킹 디렉토리 사전 검사
Layer 3: git merge --ff-only    →  Git 자체 TOCTOU 방어 (최종 안전장치)
Layer 4: panic/safe mode        →  비정상 상태 감지 시 수동 복구 강제
```

각 레이어는 단독으로 완벽하지 않지만, 4개가 합쳐지면 sync daemon의 안전성이 보장됩니다.

---

**최종 갱신**: 2026-06-17 | `bin/integration-daemon` 초판 구현 기반
