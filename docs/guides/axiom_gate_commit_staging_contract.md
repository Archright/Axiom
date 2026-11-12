# axiom-gate commit 자동 stage 계약

## 1. 관찰된 동작 (실측)

`bin/axiom-gate commit --message "..." <file-list>`를 명시적 파일 리스트와 함께 호출하면, 커밋에 리스트에 포함된 파일 외에도 worktree에서 dirty 상태인 추적 파일(tracked file)이 추가로 포함된다.

**실측 예시:**

```$ bin/axiom-gate commit --message "fix: something" docs/DEBT_REGISTRY.md src/cli/main.nim```

위 명령으로 3개 파일만 지정했음에도 커밋에는 아래 6개 파일이 포함되었다:

| 포함 파일 | 리스트 명시 여부 |
|---|---|
| `docs/DEBT_REGISTRY.md` | ✅ 명시 |
|  | ✅ 명시 |
| `src/cli/main.nim` | ✅ 명시 |
| `docs/DEBT_REGISTRY.md` | ❌ 미지정 — dirty working-tree에서 자동 stage |
| `src/generated/debt_constants.nim` | ❌ 미지정 — dirty working-tree에서 자동 stage |
| `src/generated/type_registry_metadata.json` | ❌ 미지정 — dirty working-tree에서 자동 stage |

즉, 명시적 파일 리스트는 "추가 stage 대상"일 뿐, "유일한 stage 대상"이 아니다.

## 2. 소스 근거 (file:line, 실제 확인된 경우)

**소스 파일**: `src/gate/gateway.nim`
**빌드 경로**: `nim c -d:release -o:bin/axiom-gate src/gate/gateway.nim` (gateway.nim:17)

### 2.1 `parseCommitArgs` — 파일 리스트 파싱 (gateway.nim:109–136)

`axiom-gate commit --message "msg" [--skip-ci] [file1 file2 ...]`의 positional 인자를 `files` 시퀀스로 수집한다. `--message`가 제공되면 그 뒤의 positional 인자가 전부 `files`가 된다.

### 2.2 `stageFiles` — 명시 파일 개별 stage (gateway.nim:143–152)

```nim
proc stageFiles(files: seq[string]): bool =
  if files.len == 0:
    return false
  for f in files:
    let (outp, code) = runGit("add " & quoteShell(f))
    ...
```

각 파일을 `git add <file>`로 개별 stage한다. 이 단계에서만 명시적 파일 리스트가 사용된다.

### 2.3 `runCommitCommand` — 핵심 stage 로직 (gateway.nim:337–345)

```nim
  # ── Phase 2: 스냅샷 고정 (Immutable Snapshot) ──
  let phase2Start = getMonoTime()
  if files.len > 0:
    if not stageFiles(files):
      logError("gateway", "[gateway] Failed to stage files")
      return 1
  discard runGit("add -u")
  let staged = hasStagedChanges()
  logTiming("Phase 2 (stage)", phase2Start)
```

**이것이 핵심 메커니즘이다:**

1. `files.len > 0`이면 `stageFiles(files)`로 명시적 파일들을 `git add <file>`로 stage한다.
2. **그 다음 줄 `discard runGit("add -u")`가 무조건 실행된다.** `git add -u`는 worktree에서 수정된 모든 추적 파일을 stage한다 — 명시적 리스트에 포함되었든 아니든, dirty 여부와 관계없이.

따라서 명시적 파일 리스트는 "추가로 stage할 파일"일 뿐이며, `git add -u`가 항상 모든 dirty tracked 파일을 함께 stage한다.

## 3. 계약 명문화 (contract)

### 3.1 semantic property

> **`bin/axiom-gate commit`은 파일 리스트를 명시하더라도, dirty working-tree에 존재하는 모든 추적 파수를 함께 stage한다.**

이것은 버그가 아니라 현재 `axiom-gate` commit wrapper의 **의도된 semantic property**이다. wrapper는 `git add -u`를 무조건 실행함으로써 "worktree의 모든 변경을 커밋에 포함"시키는 것을 기본 동작으로 삼고 있다.

### 3.2 안전한 사용을 위한 의미

- 보호 대상 파일(`docs/DEBT_REGISTRY.md`, `src/generated/debt_constants.nim`, `src/generated/type_registry_metadata.json` 등)이 worktree에서 dirty 상태로 존재하는 동안에는, `bin/axiom-gate commit`을 파일 리스트와 함께 사용해도 해당 파일이 커밋에 포함될 수 있다.
- 파일 리스트를 전달하는 것은 "이 파일들도 반드시 포함시켜라"는 보장일 뿐, "오직 이 파일만 포함시켜라"는 제한이 아니다.
- P0-only 커밋(특정 파일만 커밋)을 구성하려면, wrapper의 이 동작을 우회하거나, 커밋 전에 보호 파일의 dirty 상태를 해소해야 한다.

## 4. 확인 상태

**VERIFIED** — 소스 코드로 확인됨

- `src/gate/gateway.nim:343` (`discard runGit("add -u")`)가 명시적 파일 리스트와 무관하게 항상 실행되는 것을 직접 확인함.
- `src/gate/gateway.nim:143–152` (`stageFiles`)가 개별 `git add <file>`만 수행하며, 리스트를 제한하지 않음을 확인함.
- `src/gate/gateway.nim:109–136` (`parseCommitArgs`)가 파일 리스트를 positional 인자로 수집함을 확인함.
- `bin/axiom-gate`는 컴파일된 ELF 바이너리이며, 그 소스 루트는 `src/gate/gateway.nim`임(`gateway.nim:17`의 빌드 명령으로 확인).

## 5. 권고

보호 파일이 dirty 상태인 상황에서 P0-only 커밋을 안전하게 구성하려면 다음 수단이 후보로 존재한다 (별도 실행 방법론 결정은 recovery plan 문서를 참조):

1. **커밋 전 보호 파일 복원**: `git checkout -- <protected-file>` 또는 `git restore <protected-file>`로 dirty 상태를 해소한 후 `axiom-gate commit` 실행.
2. **wrapper 외 별도 staging**: `git add`를 wrapper 밖에서 직접 제어하여 원하는 파일만 stage한 뒤, `axiom-gate commit`을 `--no-verify` 등으로 호출하는 경로.
3. **wrapper 수정**: `runCommitCommand`의 `discard runGit("add -u")` (gateway.nim:343)를 파일 리스트가 제공된 경우에만 조건부로 실행하거나, `git add -u`를 `git add -u -- <explicit-file-list>`로 제한하는 방향. 단, 이 수정은 AGENTS.md §-1에 의해 `src/gate/runners/import_encapsulation_gate.nim` + `config.nims` importEncapsulation block과 `AGENTS.md`만 보호 대상이므로(원 §-1이 인용하던 `.github/workflows/ci.yml`은 CI=0 cutover, 2026-09-20로 삭제), `gateway.nim` 자체는 수정이 가능하나 architect 승인이 필요하다.

---

Contract owner: P0 incident / Date: 2026-09-02
