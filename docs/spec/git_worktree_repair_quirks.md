# git worktree repair 전역 재기록 · remove 역포인터 검증 Quirk (git 2.43.0)

> AGENTS.md §0.5 Quirk Mandate — 발견 2026-10-20 (워크트리 관리 메타데이터 정리 활동).
> **범위**: git worktree **관리 메타데이터** — 링크 워크트리의 `.git` gitfile과
> `$GIT_DIR/worktrees/<id>/gitdir`가 이루는 쌍방향 포인터다. 저장소 콘텐츠
> (커밋·브랜치·ref·작업 트리 파일)는 이 문서의 관측 대상이 아니며, 관측 범위에서
> 불변이었다. 본 문서는 관측 기록이며 프로시저 매뉴얼이 아니다.

**Discovered**: 2026-10-20
**Class**: git worktree admin metadata / repair pathspec 범위 / remove `--force` 한계

## Measured environment

- git **2.43.0**, Linux 6.17.0-42-generic x86_64, Linux Mint 22.3 (`git --version`, `uname -srvm`, `/etc/os-release`, 2026-10-20 측정). 로캘 ko_KR — git fatal 메시지가 한국어로 관측됐고, 영문 원형은 v2.43.0 소스 문자열과 병기한다.
- 저장소 배치(동일 upstream 저장소의 다중 클론):
  - 정본 클론: `.4` (HEAD `7ac99157ff`)
  - 구(舊) 클론: `.` — 2026-10-20 `git worktree list --porcelain` 기준 등록 워크트리 **122건**, 이 중 `<user-home>/orca/workspaces/Axiom/**` 하위 orca 워크스페이스 **64건**
  - **이중 등록**: Axiom4의 등록(46건)에도 동일 orca 워크스페이스 경로가 다수 포함되어 있다(2026-10-20 실측). 즉 하나의 워크트리가 두 클론의 `$GIT_DIR/worktrees/<id>`에 동시에 등록되어 있고, 실제 활성 방향은 각 워크트리 `.git` gitfile이 결정한다.
- 사건 워크트리: `~/.cache/axiom/push-admissibility/e04fc830978ba7f9b3c455f2b0aa4f3b5bd55e0c` (구 클론 등록).

## Symptom — 2026-10-20 관찰

아래 1~4는 금일 정리 활동에서의 관찰 기록이다. 각 항목은 오늘 재검증 가능한지 여부를 함께 표기한다.

1. **remove 검증 실패 + 이중 `--force` 무력** (재현: **UNKNOWN** — 원본 인스턴스 소실). 등록 워크트리 `e04fc830…`의 `.git` 역포인터가 구 클론 경로를 가리키는 상태에서 `git worktree remove --force`가 유효성 검증 실패로 거부됐고, 이중 `--force`도 우회하지 못했다(당시 관찰). 2026-10-20 기준 이 워크트리 **디렉터리는 소실**(`ls` 실측)되었고, 구 클론 등록에는 `prunable` 각주로 잔존한다 — 원본 명령·메시지·플래그 조합을 오늘 다시 실행할 수 없으므로 원본 재현은 UNKNOWN으로 유지한다.
2. **repair pathspec 전역 효과** (재현: **금일 샌드박스에서 검증**, 아래 참조). `git worktree repair <specific-path>`를 실행하자 pathspec이 범위 제한으로 기능하지 않았고, **등록된 모든 워크트리**의 `.git` 역포인터가 재기록되어 orca 워크스페이스 전체가 잠시 Axiom4를 가리켰다.
3. **복구** (재확인: **2026-10-20 읽기 전용 감사**). 구 클론에서 인자 없는 `git worktree repair`로 모든 포인터가 원복됐다. 사후 감사: orca 64/64개 `.git` 파일이 `…/<workspace>/Axiom/.git/worktrees/<id>`를 가리키며, 샘플 HEAD가 해석된다 — `A=8d7c56e33`, `B=ae06c0aa1`, `debt484-fix=f5f156e7b` (구 클론 porcelain 목록에서 오늘 재확인).
4. **콘텐츠 불변** (샌드박스 재현에서 확인). repair는 커밋·브랜치·ref를 수정하지 않았고, 워크트리 관리 `.git` 포인터만 재기록했다.

## 최소 재현 — 동일 빌드에서 2026-10-20 검증 (/tmp 샌드박스)

원본 워크트리는 소실되었으므로, 동일 형태를 `/tmp` 새 저장소에서 git 2.43.0으로 재구성해 직접 측정했다. (원본 인스턴스의 재현이 아닌 **메커니즘**의 재현이다.)

### Scenario B — repair pathspec은 등록 전체를 재기록한다

`c1` 저장소에 링크 워크트리 `w1·w2·w3`를 만들고 `cp -a c1 c2`로 클론 디렉터리를 통째로 복사해 **두 클론이 동일 워크트리 등록을 공유**하는 상태(실제 Axiom 레이아웃과 동형)를 만든다. 모든 `.git` 역포인터는 `c1`을 가리키는 출발점에서:

```
$ git -C …/c2 worktree repair …/w1        # pathspec 1개
repair: .git file incorrect: …/w2
repair: .git file incorrect: …/w3
repair: .git file incorrect: …/w1
$ # 결과: w1·w2·w3 전부 'gitdir: …/c2/.git/worktrees/<id>'로 재기록
```

- pathspec은 `w1` 하나였지만 **등록된 세 개 전부**가 재기록됐다 — pathspec은 범위 제한이 아니다.
- 재기록된 포인터는 "깨진" 포인터가 아니라 **다른 유효한 클론(c1)을 가리키던 정상 포인터**였다. repair는 유효성이 아니라 "현재 레포와 일치하는가"만 본다.
- 전후 `for-each-ref`와 각 워크트리 `rev-parse HEAD`가 동일 — 콘텐츠 불변.
- 복구: `git -C …/c1 worktree repair`(인자 없음) → 세 포인터 모두 c1으로 원복. (실제 사건의 복구와 동형.)

### Scenario A — remove의 역포인터 검증은 `--force`로 우회되지 않는다

`c1`에 워크트리 `stale`을 만든 뒤 레포 디렉터를 rename(`c1 → c1-renamed`)해 역포인터를 끊는다(사건의 "레포 경로가 변한" 형태와 동형):

```
$ git -C …/c1-renamed worktree remove --force …/stale
fatal: 유효성 검사에 실패하여, 작업 폴더를 제거할 수 없습니다: '…/stale/.git'은(는) .git 파일이 아닙니다, 상태 코드가 7 입니다
$ git -C …/c1-renamed worktree remove -f -f …/stale   # 동일 fatal, exit 128
fatal: 유효성 검사에 실패하여, 작업 폴더를 제거할 수 없습니다: …
```

영문 원형(v2.43.0 소스): `die(_("validation failed, cannot remove working tree: %s"))` + `_("'%s' is not a .git file, error code %d")`. 오류 코드 7 = `READ_GITFILE_ERR_NOT_A_REPO`(v2.43.0 `setup.h:36`) — gitfile이 기록한 gitdir가 유효한 저장소로 해석되지 않는다는 뜻이다.

이어서 역포인터를 repair로 고친 뒤 동일한 `remove -f -f`를 실행하면 **성공**(exit 0)한다 — 사건의 "repair 선행 → remove 성공" 순서와 동형이다.

## Why `--force` did not bypass (v2.43.0 소스 검증)

v2.43.0 `builtin/worktree.c` / `worktree.c` (github.com/git/git 태그 v2.43.0) 기준:

- `remove_worktree()`에서 `force >= 2`가 우회하는 것은 **lock 검사**뿐이다 (`builtin/worktree.c:1332-1339`, "cannot remove a locked working tree … use 'remove -f -f'").
- 그다음 `validate_worktree(wt, &errmsg, WT_VALIDATE_WORKTREE_MISSING_OK)`는 **force 개수와 무관하게 항상 실행**되며(`builtin/worktree.c:1340-1342`), 실패 시 위 fatal로 사망한다.
- `validate_worktree`는 워크트리의 `.git` gitfile을 읽어(`<wt>/.git`) 현재 레포의 `<git_common_dir>/worktrees/<id>` 실경로와 비교하고(`worktree.c:336-346`), 판독 실패(끊긴 포인터)·불일치 모두 검증 실패다.
- 즉 역포인터가 끊겼거나 다른 레포를 가리키는 상태에서는 `-f -f`도 제거 경로에 도달하지 못한다. 공식 문서가 `--force`에 부여한 의미("unclean worktree는 `--force` 1회, locked는 2회")와 구현이 일치하며, 역포인터 검증은 force가 건드리는 검사가 아니다.

## 공식 문서와의 괴리 (discrepancy 기록)

- `git help worktree` (2.43.0 로컬 man) 및 [git-scm git-worktree](https://git-scm.com/docs/git-worktree)의 repair 섹션:
  > "If multiple linked worktrees are moved, running repair from any worktree with each tree's new \<path\> as an argument, will reestablish the connection **to all the specified paths**."
- 이 문장은 pathspec별 효과로 읽힌다. 반면 같은 섹션의 "If both the main worktree and linked worktrees have been moved … running repair in the main worktree and specifying the new \<path\> of each linked worktree will reestablish **all connections in both directions**"은 전체(양방향) 수리를 함의한다.
- 구현(`builtin/worktree.c:1383-1388`): pathspec마다 `repair_worktree_at_path()`를 1회 실행한 뒤 **무조건 `repair_worktrees()`(등록 전체 순회)를 실행**한다. `repair_gitfile()`(`worktree.c:545-577`)은 워크트리 디렉터리가 존재하는 한 역포인터가 현재 레포와 다르기만 하면 재기록한다.
- 결론 단정 대신 quirk로 기록한다: **문서는 "지정 경로들의 연결을 재establish"으로 읽힐 여지가 있고, 구현은 pathspec을 범위 제한이 아니라 추가 수리 대상으로 처리하며 전역 패스를 항상 수행한다.** 사용자가 전자로 독해하면 관측된 전역 재기록은 문서와 충돌한다. 이 독해 괴리 자체가 본 quirk다.

## 안전 절차 (운영 수칙)

1. **repair는 워크트리 등록을 소유하는 레포에서 실행한다.** 등록을 소유하지 않은 클론에서 실행하면 그 클론의 등록을 따라 포인터를 끌어온다.
2. **`git worktree repair`에 pathspec을 단일 타깃 명령으로 사용하지 않는다.** pathspec 유무와 무관하게 항상 등록 전체에 대한 전역 재기록 패스가 실행된다(본 문서 Scenario B).
3. **이중 등록 상태(여러 클론이 동일 워크트리를 등록)에서는 repair 실행 위치가 곧 전체 포인터 방향 결정**이다. 다중 클론 레이아웃에서 repair 실행 전에 반드시 1~2를 상기한다.
4. 끊긴 역포인터 워크트리를 지우려면 **repair → remove 순서**가 유일한 검증된 경로다. remove의 `--force` 반복은 lock만 우회한다(Scenario A).

## Blast-radius 체크리스트

repair 실행 전후로 다음을 기록한다 (사건 복구 시 실제로 수행된 항목들):

- [ ] **포인터 개수·방향 집계**: `find <워크스페이스 루트> -type f -name .git | xargs cat | sort | uniq -c` — 사건 기준 64/64가 구 클론을 가리켰다(복구 후).
- [ ] **샘플 HEAD 해석**: 대표 워크트리에서 `git -C <wt> rev-parse HEAD` — `A=8d7c56e33`, `B=ae06c0aa1`, `debt484-fix=f5f156e7b` (2026-10-20 재확인).
- [ ] **ref 불변 확인**: `git for-each-ref` 전후 비교 — repair는 ref를 쓰지 않는다(소스상 repair_gitfile/repair_worktree_at_path는 gitfile·gitdir 파일만 쓴다).
- [ ] **작업 트리 dirty 파일 무손상**: repair는 작업 트리 파일을 건드리지 않는다(소스 구조상 + 샌드박스 재현에서 확인).

## What is NOT claimed (비결론)

- **데이터 소실은 관측되지 않았다.** 그러나 이는 보장이 아니라 금일 관측 범위의 기록이다.
- **원본 인스턴스(`e04fc830…`)에 대한 `remove --force` 실패 재현은 UNKNOWN이다** — 워크트리 디렉터리가 소실되어 원본 상태를 재구성할 수 없다. 검증된 것은 동일 git 빌드에서의 **동일 형태(stale 역포인터) 재현**이다(Scenario A).
- **다른 git 버전·다른 로캘에 대한 보장은 없다.** 본 문서의 모든 동작 근거는 git 2.43.0 (소스 태그 v2.43.0 포함)이다.
- Axiom4가 orca 워크스페이스 등록을 보유하게 된 경위(클론 디렉터 복사로 인한 `$GIT_DIR/worktrees` 동반 추정)는 **추정**이며 검증되지 않았다. 검증된 사실은 현재 양쪽 클론이 동일 경로를 등록하고 있다는 현재 상태뿐이다.

## References

- 로컬: `git help worktree` (git 2.43.0), `git worktree repair -h` / `git worktree remove -h` 사용법 문자열.
- 공식: [git-worktree Documentation — git-scm.com](https://git-scm.com/docs/git-worktree) (repair/remove/OPTIONS 섹션; 본 문서 인용문의 출처).
- 소스: git v2.43.0 — `builtin/worktree.c:1332-1347`(remove force/lock/validate 순서), `:1383-1388`(repair pathspec + 전역 패스), `worktree.c:541-602`(repair_gitfile/repair_worktrees), `:657-717`(repair_worktree_at_path), `:287-346`(validate_worktree).
- 공식 문서 미러 검증: Context7 `/git/git` (`Documentation/git-worktree.adoc`, 2026-10-20 조회) — git-scm.com과 동일 문구 확인.
