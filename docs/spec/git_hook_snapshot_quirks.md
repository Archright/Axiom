# Git Pre-Push Hook Snapshot GIT_DIR 상속 Quirk (git 2.43.0)

> AGENTS.md §0.5 Quirk Mandate — 발견 2026-10-10 (trust-root 슬라이스 측정 활동).
> 도구체인: git 2.43.0, `.githooks/pre-push` Part 4("Push-Target OID Static
> Admissibility"). 본 문서는 관측된 툴체인 행동의 기록이다.

**Discovered**: 2026-10-10
**Class**: git hook 환경 상속 / push-target OID 스냅샷 판정

## Symptom

`.githooks/pre-push` Part 4는 push 대상 OID의 detached worktree 스냅샷을
`git worktree add --detach "$SNAP" "$OID"`로 만들고 `make -C "$SNAP"
push-admissibility`를 실행한다(`.githooks/pre-push:44-119`). 그러나 스냅샷
안에서 판정 근거가 되는 git 명령(`git merge-base`, `git diff … HEAD`)이
**push 대상 OID가 아니라 훅을 실행한 소스 워크트리의 체크아웃 HEAD**로
해석된다. 푸시하는 브랜치와 워크트리에 체크아웃된 브랜치가 다르면,
**다른 브랜치의 diff에 대한 판정**으로 푸시가 거부된다.

## Measured evidence (2026-10-10)

- 푸시: `fix/c2-fence-probe` (`6fd38a655`; 실제 diff = `src/cli/version.nim`
  1행 — 커밋 메타데이터로 확인)
- 당시 워크트리 체크아웃: `policy/surface-v73-closure-watcher`
- 결과: surface verdict `{path: config/repository_surface.json, status: M,
  changeClass: FROZEN, reasonCode: SURFACE_FORBIDDEN}` — 푸시 커밋에는 존재하지
  않는 `config/repository_surface.json` 변경, 즉 **체크아웃된 다른 브랜치의
  diff**에 대한 판정이었다.
- `git switch fix/c2-fence-probe` 후 동일 push → 통과 (판정 대상이 체크아웃
  HEAD임을 쌍방향으로 확인).
- 기구 재현 마이크로테스트(같은 날): 워크트리 안에서
  `GIT_DIR=<main clone>/.git git rev-parse HEAD`는 워크트리 HEAD가 아니라
  env가 가리키는 저장소의 HEAD를 반환 — 환경변수가 cwd 기반 저장소 해석보다
  우위임을 이 툴체인에서 직접 확인.

## Cause

git은 훅 프로세스를 띄울 때 `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` 등
저장소 위치 환경변수(및 푸시 경로의 quarantine/object 관련 변수)를 export한다.
git 2.43.0 `githooks(5)`가 이를 정확히 문서화한다:

> "Environment variables, such as GIT_DIR, GIT_WORK_TREE, etc., are exported
> so that Git commands run by the hook can correctly locate the repository. If
> your hook needs to invoke Git commands in a foreign repository or in a
> different working tree of the same repository, then it should clear these
> environment variables so they do not interfere with Git operations at the
> foreign location."

Part 4는 `make -C "$SNAP"`으로 cwd만 옮길 뿐 환경을 지우지 않는다(훅 전체에
env-clearing 없음 — 실측 시점 소스 기준). 환경변수가 남아 있으면 스냅샷
디렉터리에서 실행된 git 명령은 env가 가리키는 소스 워크트리 쪽으로 해석되고,
그 HEAD/인덱스/diff가 판정 입력이 된다. 결과적으로 "per push-target OID
snapshot"이라는 문서화된 보장
(`docs/agents/rules_workflow.md:235` — "per push-target OID snapshot(`git
worktree add --detach <OID>`) `make push-admissibility`")과 실측 행동이
괴리한다.

## Mitigation (fix 전까지)

- **푸시 대상 ref가 워크트리에 체크아웃된 상태에서만 push한다** — 2026-10-10
  실측에서 유일하게 검증된 안전 조건이다.
- 구조적 수정 방향(기록용): 스냅샷 실행 전 로컬 환경 해제 — git 문서가 제시하는
  `unset $(git rev-parse --local-env-vars)` 패턴. 훅 파일 수정은 본 작업 범위가
  아니므로 본 문서는 관측 기록만 담는다.

## Status

수정 착지: `8c7a865db`(*fix(hooks): pre-push 스냅샷이 push-target OID를 판정하도록
git env 정리*, 2026-10-10) — Part 4가 이제 `env -u GIT_DIR -u GIT_WORK_TREE
-u GIT_INDEX_FILE -u GIT_QUARANTINE_PATH -u GIT_OBJECT_DIRECTORY
-u GIT_ALTERNATE_OBJECT_DIRECTORIES make -C "$SNAP" push-admissibility`로
스냅샷 실행 환경을 정화한다(본 문서 Cause가 인용한 githooks(5) env-clearing
요구의 이행). 수정 착지 이후 첫 push(본 문서를 실은 PR의 푸시)가 재측정이다 —
훅이 재발하면 본 문서를 갱신한다.
