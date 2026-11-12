# axiom-a-rt 죽은 캐시 선별 삭제 — 실행 기록 (2026-10-17)

> **종류**: 실행 증거 기록. **선행**: [cache_a_rt_duplication_forensics_2026-10-17.md](cache_a_rt_duplication_forensics_2026-10-17.md) §4 판단 입력 (b) — 선별 삭제.
> **권한 근거**: 소유자 명시 허가 "권한이 필요한 부분은 전면 허가한다" (2026-10-17, 반복 확인) — 포렌식 문서 §4 (b)에 판단 입력으로 기록됨. 실행 계정 `wintrover`(ADMIN, native `gh`).
> **절차**: verify-then-delete — 열거 → 엔트리별 사생 검증 → 검증 통과 ID만 DELETE → 사후 전수 대조. STOP 조건(검증 실패 >5% 또는 API 오류)은 발동되지 않았다.

## 1. 절차 준수 사항

- 열거 엔드포인트: 포렌식 §5 재현 명령의 `/actions/cache`(단수)는 404를 반환 — 실제 REST 경로는 `/repos/Archright/Axiom/actions/caches`(복수, `?per_page=100` + `--paginate` 전수). 절차(전수 pagination 열거)는 동일하게 이행.
- open-PR 전제 변동: 포렌식 시점 "open PR 0"과 달리 실행 시점에 **open PR 2개(#901, #902)** 존재 → 해당 merge-ref 엔트리는 살아있는 스코프로 **제외**(아래 §2).

## 2. 스냅샷·검증 (2026-10-17T05:33:45Z 열거)

전수 394엔트리 / 9,713,920,264 bytes (9.047 GiB):

| 계열 | n | bytes | 비고 |
|---|---|---|---|
| axiom-a-rt | 380 | 5,362,723,793 | 단일 key `axiom-a-rt-Linux-8497…-16121bd…` 전수 일치, ref 전수 `gh-readonly-queue/main/pr-N-*`(203) 또는 `refs/pull/N/merge`(177) |
| axiom-a (full) | 3 | 3,396,404,638 | main 1건(생존, 금일 접근) + queue-probe 2건(죽음). **pr-725-queue 1건은 포렌식 이후 자가 퇴거로 이미 소멸**(인벤토리 부재 — 삭제 불가, 1건 미달 보고) |
| axiom-b | 11 | 954,791,833 | 전부 refs/heads/main — 접촉 금지 대상 |

엔트리별 사생 검증 (a-rt 380건 + a-full 죽은 후보 2건):

| 규칙 | 결과 |
|---|---|
| key == 단일 known key (a-rt) | 380/380 통과 |
| ref ∈ {readonly-queue/\*, pull/N/merge} (a-rt) | 380/380 통과 |
| open-PR 소속 아님 (#901/#902 merge-ref) | **2건 제외** — id 9081576231(pr-902), 9081571725(pr-901) — 생존 스코프 |
| last_accessed − created ≤ 1h (무재사용, p50=31s) | **14건 제외** — delta 1.01h–15.86h, 전부 폐쇄 PR merge/queue ref의 재사용 흔적 — 죽음의 재확증 부족으로 보수 제외 |
| a-full queue-probe 2건: branch idle(최종 런 완료 10-15 09:57Z), 생성≈접근 | 2건 통과 |

**검증 실패(제외) 16/380 = 4.2% < 5% → STOP 조건 미발동.** 최종 삭제 목록 = a-rt 364 + a-full 2 = **366 ID**.

## 3. 삭제 실행 (2026-10-17T05:36Z–05:42:28Z)

`DELETE /repos/Archright/Axiom/actions/caches/<id>` 순차 366회 — **366 ok / 0 already_gone / 0 API 오류**. 해제 7,450,479,191 bytes (6.939 GiB).

## 4. 사후 전수 대조 (2026-10-17T05:42:55Z 열거)

**29엔트리 / 2,277,553,494 bytes (2.121 GiB)** — before→after 순감소 7,436,366,770 bytes (6.926 GiB) = 삭제 7,450,479,191 − 신규 유입 14,112,421(스냅샷 이후 생성된 pr-902 queue-ref a-rt 1건, id 9081798795, 생성 05:41:56Z — 포렌식 §3 예측대로의 일일 유입).

| 계열 | after n | 정합 |
|---|---|---|
| axiom-a-rt | 17 | 제외 16건(2 생존 + 14 보수 제외) + 신규 유입 1건 — 삭제 목록 ID 잔존 0/366 |
| axiom-a (full) | 1 | main(id 8783280735) 생존 확인 |
| **axiom-b** | **11** | **무결성 통과** — id·key·ref 전수 스냅샷과 동일(11/11). 유일 차이 = id 9080359414의 `last_accessed_at` 갱신(05:33:00Z→05:40:18Z, main 판독) — 정체 변동 아님 |

예시 잔존 "~10-15엔트리"와의 차이(29)는 산술적 결과다: 포렌식(368)→실행(394) 사이 신규 유입 +26건 중 검증 통과분은 삭제했으나, 유입분 중 생존/보수 제외 17건과 원래 제외 11건(a-full main 1 + axiom-b 11−11)…즉 16 제외 + 신규 1 + main 1 + axiom-b 11 = 29. a-rt 자체는 380→17(−95.5%).

## 5. 재현

```bash
gh api "/repos/Archright/Axiom/actions/caches?per_page=100" --paginate \
  --jq '.actions_caches[] | [.id,.key,.ref,.created_at,.last_accessed_at,.size_in_bytes] | @tsv'
# 기계 데이터: data/ci_optimization/cache_deletion_2026-10-17.json
# 원본 스냅샷/삭제 로그: /tmp/axiom_cache_deletion/{before_all,after_all,deletion_log}.{tsv,txt}
```

잔여 위협은 포렌식 §3 그대로 — 유입 ~59엔트리/일 지속, 구조 수정(§4 (c), A-save runtime 분기 기본 브랜치 스코프 게이트) 착지 전엔 반복 소청. [docs/spec/github_delegation_residuals.md](../spec/github_delegation_residuals.md) R14의 경험 데이터로서 포렌식 문서와 공유.
