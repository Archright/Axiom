# axiom-a-rt 캐시 353중복 — 근원 규명 (2026-10-17)

> **종류**: 포렌식 관측 기록 (읽기 전용 — 삭제 미실행). **질문**: `axiom-a-rt-*` 동일 키 ~353엔트리(≈4.64GiB = 상한 47%)의 기계적 원인.
> **권위**: 캐시 열거 = Actions cache REST(전수 pagination). 공식 의미론: 캐시는 **key+version+branch(ref) 스코프**로 격리되며 PR 트리거 런은 merge ref 스코프로 저장·타 PR/베이스가 복원 불가(docs.github.com *Dependency caching — Restrictions*; actions/cache README *Cache scopes*).

## 1. 전수 (368엔트리, 9.698GiB)

| 계열 | n | 크기 | 비고 |
|---|---|---|---|
| axiom-a-rt | **353** | 4.640GiB | **동일 key+version 1종**(`axiom-a-rt-Linux-8497…-16121bd…`, version `6dfafd31…`), 평균 13.46MiB |
| axiom-a (full) | 4 | 4.172GiB | main 1.03GiB(생존) + 죽은 pr-725-queue 1.03 + queue-probe 2×1.10 |
| axiom-b | 11 | 0.887GiB | 전부 refs/heads/main — 3 현행 + 8 superseded |

## 2. 원인 — ref 스코프 격리 (전수 확정)

| ref 분류 | a-rt 수 |
|---|---|
| `gh-readonly-queue/main/pr-N-*` | 201 |
| `refs/pull/N/merge` (152개 서로 다른 PR) | 152 |
| **동일 ref 중복** | **0** |

- `setup-axiom-toolchain` A-save는 **restore MISS 시 무조건 저장**(first-save-wins, `continue-on-error`, action.yml:908-928). runtime 키(`axiom-a-rt-…`, action.yml:199-204)는 툴체인 불변 시 상수 → **ref마다 1엔트리**. 유일한 runtime 호출부 = `certificate-mint.yml:602-606,1297-1301`(PR lane=merge ref, 큐 lane=readonly-queue ref). 201 시도+152 PR=353.
- last_accessed = created+31s(p50) — 이후 무접근. **현재 open PR 0 → 353 전부 재독 불가**(152 merge ref는 폐쇄 PR 재실행으로만, 201 큐 ref는 소멸).
- 버전 드리프트·동일 ref 중복 부재(유일하게 같은 b키 2건은 a_fp 세대 플립 — 정상).

## 3. 전망·위협

- **자가 치유**: 7일 미접근 규칙으로 10-18(727MiB)→…→**10-23 전량 소멸**. 단 유입 ~59엔트리/일(≈0.79GiB/일) 지속 → 안정 상태 ~5.5–7GiB 롤링 쓰레기가 상한 압박 지속.
- **B캐시 위협(구조적)**: 퇴거는 전역 last-accessed LRU — LRU#1이 axiom-b(main)이며 여유 0.302GiB. **다음 ~23회 a-rt 저장 시 퇴거가 B부터 잡기 시작**(신세대 b 3건은 LRU#358-368로 이번 주 안전). 정확성 무관(J3 — 캐시는 가속), 콜드 회귀 비용만.

## 4. 소유자 판단 입력 (미실행)

- **(a) 대기**: 현재분은 10-23까지 자가 소멸 — 단 롤링 압박·LRU 위협 지속.
- **(b) 선별 삭제**(플랫폼 네이티브·가역·접근가치 손실 0): 353 전부 죽은 ref — 인벤토리 준비됨(`/tmp/axiom_cache_forensics/delete_by_id.sh`, `delete_by_key_ref.sh`, `a_rt_entries.tsv`). 죽은 a 3건 추가 시 +3.24GiB. 매일 유입되므로 (c) 착지 전엔 반복 필요.
- **(c) 구조 수정(계획 필요 — 미구현)**: A-save의 runtime 분기를 기본 브랜치 스코프로 게이트(`github.ref == 'refs/heads/main'`) — publisher의 스코프 위임 관례와 동일. 트레이드오프: PR/큐 mint lane의 same-ref 웜 z3+jq 상실(~21s/재다운로드).
- **R14 실측**: `docs/spec/github_delegation_residuals.md` R14(readonly-queue 스코프 공식 문장 부재)의 경험 데이터 — 201엔트리가 그 미정의 스코프에 기록되었고 타 ref에서 판독 불가임을 입증.

## 5. 재현

```bash
gh api "/repos/Archright/Axiom/actions/cache?per_page=100" --paginate --jq '.actions_caches[] | [.id,.key,.ref,.created_at,.last_accessed_at,.size_in_bytes] | @tsv'
```
