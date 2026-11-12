# git-filter-repo Quirks (재작성 세대 전환 실측)

> AGENTS.md §0.5 Quirk Mandate. 발견: 2026-11-08 Lane B 실행 중 (Publication Integrity v3.2).
> 실행 기록: [E7_laneb_history_rewrite_execution.md](../evidence/sal10_publication/E7_laneb_history_rewrite_execution.md).
> 대상: git-filter-repo a40bce548d2c (2.47.0, pip) — `~/.local/lib/python3.12/site-packages/git_filter_repo.py`.

## Q1: `--sensitive-data-removal`는 원격 전체 refs를 fetch한다 (+refs/*:refs/*)

### Symptom
fresh clone에서 `git filter-repo --sensitive-data-removal …` 실행 시, rewrite **직전에** 원격에서
`git fetch -q --prune --update-head-ok --refmap "" origin +refs/*:refs/*` (소스 :4444)가 수행되어
clone에 없던 `refs/pull/*` 전체가 로컬로 유입되고 재작성 대상에 포함된다.

### 관측 (2026-11-08)
- 1차 실행: clone 시점 6 refs → 실행 후 refs/pull 22본 등장, FETCH_HEAD에 구 SHA fetch 기록.
- refs/pull 재작성본은 로컬 한정 — GitHub는 refs/pull/* push를 거부하므로 원격 반영 불가(Lane B2/Support 대상).

### Deterministic rule
rewrite 입력 ref 집합은 "clone이 가진 refs + fetch 시점 원격 refs/* 전체"로 확정된다.
실행 간 원격 PR 변동(신규 PR·synchronize)은 ref 집합을 바꾼다 — 세대 전환 절차는 **직전 ls-remote로
ref 집합을 고정 관측**하고, 재실행 시 ref 집합 변동을 commit-map 전수 diff로 잡는다(E7 결정론 증명 참조).

## Q2: 커밋 메시지 hash-fixup은 스트리밍 중 부분 구축 commit-map으로 적용된다 (ref 집합 순서 의존)

### Symptom
메시지 내 구 SHA 참조 치환(기본 동작 — `--preserve-commit-hashes`로 억제)이
`_tweak_commit`(:3950) → `_translate_commit_hash`(:3579)에서 **그 시점까지 구축된** commit-map만 사용한다.
부모-자식 위상 순서가 강제되지 않는 고아 루트 체인(axiom/* 레저 — createLedgerRoot 고아)과
참조 대상 커밋의 상대 처리 순서는 fast-export의 ref 열거 순서에 따르므로, **동일 내용이라도 ref 집합이
다르면 fixup 적용 범위(=출력 SHA 전체)가 달라진다.**

### 관측 (2026-11-08, 동일 입력 내용·상이 ref 집합)
- run1 (pull refs 22본): 메시지 20라인 fixup (레저 append 19 + rebase 노트 1)
- run2 (pull refs 24본 + workstream 1): 동일 커밋 집합에서 **3라인만** fixup — 잔여 참조는 구 SHA로 단절
- 결정론: ref 집합이 동일하면 출력도 동일 — 크래시 후 bundle+fetch 재현으로 commit-map **전 라인 일치** 실증.

### Deterministic rule
1. 세대 전환의 재작성은 **한 번의 최종 실행**으로 확정하고, 핀 회전 등 파생 값은 그 실행의 commit-map만 사용한다.
2. 중간 실행(run1)의 commit-map은 폐기 세대로 명시(`commit-map.run1`) — 혼용 금지.
3. 미치환 단절 참조는 기록 문서의 세대 경계 특성으로 간주(E2 선례) — 재작성 세대에서 구 SHA 해석은
   pre-rewrite bundle(사적 캐시)로만 수행한다.

## Q3: replace-text는 binary blob에 미적용 (NUL in first 8KiB)

E2 4차 실행에서 실측·기록된 기존 quirk (`:3821` — `not b"\0" in blob.data[0:8192]` 조건).
ELF/오브젝트 등 이진 파일의 경로 침소는 경로 제거(pathspec)로만 처리한다.
Lane B에서는 binary 포함 grep(`git grep -a`)으로 이진 침소 0을 별도 관측했다.

## References

- git-filter-repo manual — Sensitive Data Removal subsection
- E2 4차 실행 기록: [E2_cutover_execution.md](../evidence/sal10_publication/E2_cutover_execution.md) "실행 이력 (1~6차)"
- 결정론 증명 절차: E7 "세대 전이 관측"·"결정론 증명"
