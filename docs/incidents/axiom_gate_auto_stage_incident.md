# Incident Report — bin/axiom-gate commit auto-staged protected shadow dirty files

```
Incident:
  bin/axiom-gate commit auto-staged protected shadow dirty files.

Impact:
  protected 3 files entered commit 6c435b5cf.

Data loss:
  none observed.

Push:
  none.

Current HEAD:
  6c435b5cf.

Required:
  reconstruct P0-only commit from main without modifying protected files.
```

## 1. 타임라인 (timeline)

- P0 tool/docs/test 검증 완료 (compile ✅, unit 20/20 ✅)
- base=main 수용 → `p0-local-exact-gate`를 `origin/main(0be7fd3f6)`에서 분기
- 보호 3 dirty + untracked 들이 branch 이관 후 그대로 보존 확인
- main-tree에서 P0 재검증 (20/20 ✅, tool compile ✅)
- `bin/axiom-gate commit` 실행 — 명시 3파일 리스트 전달에도 불구하고 보호 3파일 자동 포함
- 커밋 `6c435b5cf` 생성 (6 files: 3 의도 + 3 보호)

## 2. 영향 평가

- 보호 3파일(PR #27 shadow dirty → 이 세션 hard-rule 무접촉·미커밋 대상)이 커밋에 포함됨
- 데이터 소실 없음, push 없음, 원격 영향 없음
- 증거는 커밋 객체 + worktree에 온전 — forensic으로 재현 가능

## 3. 근본 원인 후보

- `bin/axiom-gate commit`이 명시 파일 리스트에도 불구하고 working-tree의 dirty 수정분을 함께 stage한다는 semantic property (확인 필요 — 별도 tool contract 문서 참조)

## 4. P0 상태 분리 (주의해서 명시)

```
P0 implementation
  → validated
  → not rejected

Commit operation
  → rejected
  → requires controlled recovery
```

## 5. 금지 현재 단계

- push
- PR 생성/업데이트
- amend
- 새로운 commit
- 보호 3파일 내용 수정

## 6. 현재 동결 상태

- branch=p0-local-exact-gate, HEAD=6c435b5cf, push=없음

Incident classified: TOOL_AUTO_STAGE / Date: 2026-09-02
