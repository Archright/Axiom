# git worktree add 전 파일 mtime 부여 · pre-push stale 오탐 Quirk (git 2.43.0)

> AGENTS.md §0.5 Quirk Mandate — 발견 2026-11-02 (PR #1181 랜딩 활동).
> 도구체인: git 2.43.0, `.githooks/pre-push` Part 4 per-OID 스냅숏 루프 선두의
> Identity verification(mtime precondition). 본 문서는 관측된 툴체인 행동의
> 기록이며 프로시저 매뉴얼이 아니다.

**Discovered**: 2026-11-02
**Class**: git worktree materialization mtime / pre-push 게이트 바이너리 freshness 판정

## Measured environment

- git **2.43.0** (`git --version`, 2026-11-02 측정). 로캘 ko_KR.
- 저장소: Archright/Axiom — 메인 toplevel + `git worktree add` 링크 워크트리
  구성. 본 문서의 재측정 worktree: `.worktrees/quirk-doc`
  (branch `docs/worktree-mtime-quirk`, 기준 commit `7975f3ebe` = origin/main).
- 훅: `.githooks/pre-push` — Part 4 스냅숏 루프 선두의 Identity
  verification(`.githooks/pre-push:152-176`)이 7개 게이트 바이너리↔소스 쌍을
  bash `-nt`(엄격 신규)로 판정한다. 훅 소스 코멘트 기준 "the sole FAIL
  basis" — 이 비교 하나가 FAIL의 유일 근거다.

## Symptom

PR #1181(branch `chore/reanchor-debt-drifts`, commit `90604006e`)의 push
1회차:

- 워크트리 안에서 커밋을 push하자 pre-push가 "stale binary"(소스가 바이너리보다
  새다)로 FAIL했다.
- 실제로는 바이너리·소스 모두 **무변경**이었다 — 커밋 diff에 해당 파일이
  없다(구조적 오탐). 판정 근거는 콘텐츠가 아니라 mtime이었다.

## Measured evidence (2026-11-02)

### 사건 — PR #1181

- push 1회차(워크트리에서 실행): stale 오탐 FAIL.
- 메인 toplevel에서 **동일 커밋을 재push** → 통과. rotation pin `--write`
  불필요 — `OK no-drift — pin@90604006e anchors derived(90604006e)`,
  스냅숏 14 게이트 green(관측 output).

### 금일 재측정 — 메커니즘 직접 확인

1. **전 파일 stamp**. `git worktree add .worktrees/quirk-doc -b
   docs/worktree-mtime-quirk origin/main` 직후 측정: 추적 파일 **6,406건
   전부**가 생성 시각(09:38:13–14 +0900)으로 stamp됐다(`find -newermt` 생성
   윈도우 카운트 6,407/6,407 — +1은 같은 순간 생성된 `.git` gitfile). 소스·
   데이터·문서 구분이 없다 — stat 샘플 `AGENTS.md`,
   `src/gate/runners/gate_hook.nim`, `data/baseline.json`,
   `docs/spec/hooks_architecture.md` 모두 09:38:13–14.
2. **판정은 CWD 로컬 상태만 읽는다**. 동일 `-nt` 시퀀스 재실행: 메인 toplevel은
   7쌍 전부 ok(바이너리가 실제 빌드 순서상 소스보다 새 mtime), 신규 worktree는
   게이트 바이너리가 git 미추적 빌드 산출물이라 부재 → 같은 Identity 블록의
   missing 분기로 간다. 즉 이 검사는 push되는 커밋과 무관하게 **push를 실행한
   저장소의 작업 트리 mtime 상태**를 판정한다. 사건의 stale 분기는 "바이너리가
   존재하나 소스가 더 새로운" 상태에서 발화한다.
3. **훅 자체가 mtime freshness를 결함 패턴으로 선언한 선례**. 같은 훅 Part 5의
   tool ensure는 "Content-addressed freshness. mtime (or "exists ⇒ reuse")
   would let a binary built from older sources render a verdict under the OLD
   derivation rules — the exact defect this part must not
   reintroduce."(`.githooks/pre-push:80-84`) — Part 4 Identity verification만
   여전히 mtime 비교다.

## Cause

세 성질의 결합이다:

1. `git worktree add`는 새 워크트리의 **전 파일을 현재 시각 mtime으로
   materialize**한다(금일 6,406/6,406 측정). 파일 간 상대 순서(어느 파일이 몇
   ms 더 새인가)는 checkout 쓰기 순서라는 구현 디테일이지 콘텐츠에서 유도되는
   값이 아니다.
2. pre-push Identity verification은 `-nt` 하나로 stale을 판정하며("the sole
   FAIL basis", `.githooks/pre-push:154`), 이 비교는 push 콘텐츠와 무관하게
   CWD의 로컬 작업 트리 상태를 읽는다.
3. worktree 생성 이후 빌드되지 않은(또는 symlink 등으로 과거 mtime을 지닌)
   바이너리 + 재-materialize된 소스 조합에서, 콘텐츠 무변경임에도 stale이
   구조적으로 발화한다.

**대조(이미 문서화된 같은 근원의 기록)**: `bin/gate_hook`용 Bash shim
freshness 가드는 동일한 mtime 왜곡에 대해 git diff cross-check를 갖는다 —
"Cross-checked with `git diff` to avoid false positives from mtime distortion
after `git checkout`"(`docs/spec/hooks_architecture.md:76`, 재기술 `:137`).
7쌍 Identity verification에는 이 cross-check가 없다 — 이 격차가 오탐의
구조적 원인이다.

## 영향 범위

- **worktree 기반 워크플로 전반**: `git worktree add`로 만든 워크트리에서
  push하면 Identity verification(7쌍)이 로컬 mtime 상태에 좌우된다. 오탐은
  차단(false positive)으로 발화한다 — fail-closed라 무결성 위험은 아니지만,
  worktree 워크플로에서 push가 반복 가려진다.
- 작업 트리를 재-materialize하는 git 연산(`git checkout`·`git pull`·
  `git rebase` 등) 전반에 동일 family의 mtime 왜곡이 가능하다 —
  `docs/spec/hooks_architecture.md:76`가 gate_hook 가드에 대해 이미 기록한
  근원과 같다.
- 게이트 바이너리 7종(`bin/debt_engine` 등)은 origin/main 기준 git 미추적 빌드
  산출물이다(2026-11-02 `git ls-tree origin/main -- bin/` = `bin/axiom.nim`만
  추적). 미추적 상태의 신규 worktree는 stale이 아니라 missing 분기로 FAIL한다.

## Mitigation (fix 전까지)

1. **검증된 경로 — 메인 toplevel에서 재push**. 동일 커밋을 메인 toplevel에서
   다시 push한다(PR #1181에서 관측된 해결). 메인 toplevel의 mtime은 실제 빌드
   순서(소스 수정 → 빌드)를 반영하므로 판정이 통과한다. 커밋이 동일하면 pin·
   스냅숏 판정도 동일하게 통과한다(관측: pin `--write` 불필요, `OK no-drift`,
   14 게이트 green).
2. **`--no-verify` 금지** — 훅의 각 FAIL 경로가 스스로 명시한다.
3. 구조적 수정 방향(기록용, 본 문서 범위 밖): gate_hook 가드와 동일한
   git-diff cross-check를 7쌍 Identity verification에 적용하면 mtime 왜곡
   오탐이 제거된다(`docs/spec/hooks_architecture.md:76` 선례). 훅 파일 수정은
   본 작업 범위가 아니므로 본 문서는 관측 기록만 담는다.

## Status

본 문서를 실은 PR(branch `docs/worktree-mtime-quirk`)은 worktree에서
커밋·push한다. 이 worktree는 생성(09:38) **이후** 부트스트랩 빌드
(`make ci-compile-ax ci-compile-gate-hook` + 7개 Makefile 게이트 타깃,
09:48–09:51)로 바이너리를 마련했으므로, 위 측정(2) 기준 7쌍 전부
`bin >= src`로 stale 분기는 **통과 측** 재측정이 된다 — 이는 메커니즘의
조건부성(바이너리 mtime이 재-materialize된 소스보다 새면 발화하지 않음)을
확인하는 쌍방향 관측이다. stale 분기의 발화 관측은 PR #1181이 유일하며,
본 PR의 push에서 stale이 발화하면 본 문서를 갱신한다.

## What is NOT claimed (비결론)

- PR #1181 워크스페이스 내부에서 게이트 바이너리가 어떤 경위로 소스보다 오래된
  mtime을 지녔는지(워크트리 내 빌드 시점, symlink 원본 위치 등)는
  재구성하지 않는다 — 관측된 것은 stale FAIL 자체와 메인 toplevel 재push로의
  해결뿐이다.
- git이 checkout 순서를 보장하지 않는다는 일반 단정은 하지 않는다 — 관측
  범위는 "재-materialize된 파일의 상대 mtime은 콘텐츠와 무관한 구현 디테일이며,
  금일 측정에서 소스가 더 새로 materialize된 사례" 수준이다.
- missing 분기("Required prebuilt binary missing")의 동작 보장은 본 문서
  범위가 아니다. 게이트 바이너리가 git 미추적이라는 현재 상태 기록만 담는다.
- 다른 git 버전·플랫폼에 대한 보장은 없다. 본 문서의 모든 측정은 git 2.43.0,
  Linux, 2026-11-02 기준이다.

## References

- 훅 소스: `.githooks/pre-push:152-176`(Part 4 per-OID 루프 선두 Identity
  verification, `-nt` 판정), `:80-84`(Part 5 tool ensure의 content-addressed
  freshness 선언), `:197-199`(스냅숏으로의 prebuilt 바이너리 symlink —
  symlink 패턴 선례)
- 아키텍처 문서: `docs/spec/hooks_architecture.md:75-76`(Binary Build
  Isolation + mtime 왜곡 git-diff cross-check 기록), `:137`(동일 원칙 재기술)
- 선례 quirk 문서: `docs/spec/git_hook_snapshot_quirks.md`(같은 pre-push
  스냅숏 경로의 GIT_DIR 상속 quirk), `docs/spec/git_worktree_repair_quirks.md`
  (worktree 관리 메타데이터 quirk), `docs/spec/nested_worktree_config_quirks.md`
  (worktree 워크플로 quirk)
- 사건: PR #1181(Archright/Axiom, branch `chore/reanchor-debt-drifts`,
  commit `90604006e`, 2026-11-02 merge)
