# E3 — Actions Log Exposure Scan Report (Final — Gate 2-E3)

**상태**: **최종 보고 — 전수 스캔 완료(2026-11-06)**. 90일 창 33,026 run 전수 처리(완료 판정: 잔여 0·UNKNOWN 0). 자격증명형 히트 0 — candidate 5건은 전건 오탐 분류 기록(공개 워크플로 마커 리터럴·§7). 중간 보고서(`E3_actions_scan_interim`)에서 승격.
**기준**: 2026-11-05~06 관측. READ-ONLY 준수 — 저장소 무변경(porcelain 빈 출력 확인), run·artifact·로그 무삭제(GET만), /tmp 외부 파일 생성 없음, 마스킹 무결성(프리뷰 = 접두 4자+길이) 유지.

## 1. 방법·증거 명령

| 단계 | 명령/스크립트 | 검증 |
|---|---|---|
| 전수 열거 | `/tmp/ax_e3_enumerate.sh` — 주간 윈도우 `created=a..b&per_page=100&page=N` 반복, `fetched < total` 감지 시 윈도우 절반 재귀 분할, 최종 `unique_by(.id)` | 853페이지 호출, 창 기록 103건 |
| 로그 스캔 | `/tmp/ax_e3_scan.sh <ids_file>` — logs GET→zip→unzip→패턴 grep→마스킹 히트→zip·해제본 즉시 삭제 | 410·200 경로·합성 히트 파이프라인 종단 테스트 통과, **전체 비밀값 누출 0**(프리뷰 = 접두 4자+길이) |
| 배치 선출 | `/tmp/ax_e3_select.sh` — (a) 정규식 매칭 전수, (b) created_at 역순 300, (c) `random.Random(42)` 300((a)∪(b) 제외) | |
| 분리 실행 | `setsid nohup bash /tmp/ax_e3_bigscan.sh &` — 세션 리더(자체 SID), 에이전트 세션과 무관 생존 | `ps -p 1780435` 확인, 90초 진행 관측(618→698 done) |
| 집계 | `/tmp/ax_e3_aggregate.sh` | §6 최종 실측 |

## 2. 열거 통계 — 90일 창 전수 33,026건

- 창 [2026-08-07T00:00Z, 2026-11-05T08:33Z], `/tmp/ax_e3_runs.jsonl` 정본. 전체 34,549와 정합(창 밖 08-07 이전 1,523건).
- **API quirk 실증 2건**: ① 페이지 캡 1,000(page 11 → 0건 반환, total_count까지 0 오염) ② total_count 상한 2,500(부모창 2,500 vs 자식창 합계 >2,500 모순). 열거 완전성은 `fetched < total` 절반 재귀 분할로 확보.
- 워크플로 상위: ci-cache-publisher 11,367(34.4%)·ci-provider-router 3,199·landing-integrity 2,713·admission-gate 1,667·repository_surface 1,599·observation 1,598·bsec-integrity 1,363·probe-merge-queue 1,213·trusted-writer-set 1,108·admission-gate-v2 963.
- event: workflow_run 15,186·pull_request 8,878·merge_group 5,971·push 1,853·pr_target 511·dispatch 302·schedule 221·dynamic 104. conclusion: success 24,099·skipped 4,079·failure 2,540·cancelled 2,174·startup_failure 134(진행중 0).

## 3. 경계 모델 — "생성 후 정확히 90일" 소멸 실증

- 규격 20run 가용성 검증: **410×10 / 200×10** — 최고령 10건(08-07T00:30~04:13) 전부 410(**"부재 검증" = 노출 축 실증** — 2차 비평 ②의 소멸 run 판정 근거), 주간 앵커 9건(08-15~10-10)+10-31 앵커 전부 200.
- 경계 정밀 프로브: 08-07T06:53 → 410(90일 경과), 08-07T09:18 → 200(90일 19분 전) — 관측 시각 08:59Z와 정확히 일치. 08-08~08-12 일별 첫 run 5건 모두 200.
- **대규모 확증**: 분리 스캔 진행 중 410 전환 21건(스캔 처리 대기 중 90일 경과로 로그 소멸) — §6 `http410=21`. 부재 검증·노출 아님.
- 창 좌측 경계 실시간 이동 → 분리 스캔은 **최고령 순** 처리로 침식 구간 우선 확보.

## 4. 1차 배치(큐레이션 619건) 집계 — 히트 0

구성 = 10-31 앵커 1 + (a) 소규모 18(release-ship 12·probe 6) + (b) 최신 300 + (c) 시드 42 무작위 300.

- **실자격증형 히트 0건** — 패턴 11종(ghp_·github_pat_·gh[ousr]_·AKIA·PEM 헤더·sk-·xox·AIza·Bearer·password/token 실값형). candidate/fixture/synthetic 전부 0(히트 자체가 없음).
- 스캔 실측: 606 run unzip 스캔(파일 2,694·라인 2.12M·263MB), 1,047초(36 runs/min).
- **`***` 마스킹 5,463회 / 585 run 관측** — 등록 시크릿 자동 마스킹 정상 작동.
- 29건 "실패" 실체 규명: **21건 = 빈 zip 22바이트**(skipped/cancelled run은 로그 없음, 200+빈 zip 반환 — 실증), **8건 = 404**(failure/startup_failure 계열 로그 부재). 정상 종료 상태 — 스캐너 수정(빈 zip·404 → done 처리) 후 bigscan 재처리.
- (a)의 "publish" 매칭이 ci-cache-publisher 11,367건을 포함 — 이름 규격 그대로 적용, 전체 창 분리 스캔이 초월 커버.

## 5. 분리 스캔 — 완료 기록

- **PID 1780435**, 시작 2026-11-05T09:36:04Z, 종료 2026-11-06T00:32~00:45Z(약 15.0h — `secs_total` 54,554초=15.2h), `setsid` 세션 리더, 최고령 순 처리.
- **최종: done 33,026/33,026(전수)·UNKNOWN 0** — 처리량 36 runs/min(200 기준)·rate 최고 사용 4,034/5,000·소진·403 이벤트 0건(403/429/5xx 재시도: remaining<30 reset 대기·sleep 60·sleep 10×3).
- 로그: `/tmp/ax_e3_bigscan.log`(5분 간격 PROGRESS), 상세 `/tmp/ax_e3/scan.log`, 상태 `/tmp/ax_e3/state.jsonl`, 히트 정본 `/tmp/ax_e3/hits.jsonl`.

## 6. 최종 집계(aggregate 실측 2026-11-06)

per-run state 총계(원본 출력): `records=33056 http200=32558 http410=21 http404=477 unknown=0 bad_zip=21` · `scanned_runs(unique done)=33026`

- **http200 = 32,558 run 실스캔** — 파일 109,029개·라인 92,701,286줄·12.0GB(12,003,061,230 bytes)·`***` 등록 시크릿 마스킹 254,253회 / 25,108 run(자동 마스킹 정상).
- 404×477(failure/startup_failure 로그 부재)·410×21(스캔 중 90일 경과 소멸)·bad_zip×21(skipped/cancelled 빈 zip) — 전부 **로그 부재 계열**(§4 29건 실체 규명과 동일 기전)·노출 축 아님. records 33,056 vs unique done 33,026 차이 30 = 스캐너 재시도 중복 기록.
- **hit_runs = 5** — §7.

## 7. 히트 5건 — 전건 오탐 분류(공개 워크플로 마커 리터럴)

히트 분류 분포(원본 출력): `candidate/prod_context` · pattern `kv` · occurrences 5 · records 5.

| run | 워크플로 | 로그 파일:라인 | 프리뷰 | 실체(소스 근거) |
|---|---|---|---|---|
| 39686297503 | drift-signal | 0_drift-signal.txt:282 | `drif…(len=9)` | `TOKEN="drift-red"` — `.github/workflows/drift-signal.yml:194` |
| 40075207815 | drift-signal | 0_drift-signal.txt:293 | `drif…(len=9)` | 동일 |
| 40308449175 | drift-signal | 0_drift-signal.txt:265 | `drif…(len=9)` | 동일 |
| 41634943972 | drift-signal | 0_drift-signal.txt:282 | `drif…(len=9)` | 동일 |
| 39723921869 | closure-watcher(job drift-freshness) | 2_drift-freshness.txt:264 | `drif…(len=11)` | `TOKEN="drift-stale"` — `.github/workflows/closure-watcher.yml:675` |

- 전건 `tracking issue created (token=${TOKEN})` 로그 라인 — TOKEN 값은 **이슈 제목 검색용 하드코딩 마커로 이미 공개 저장소 소스에 존재하는 상수**(자격증명 아님). 마스킹 프리뷰 길이(9·11)와 소스 리터럴 길이 정확 일치.
- **처리: 분류 기록으로 잔존 허용**(B2 §(c) 오판 분류 전례) — run·로그 삭제 0건(임의 삭제 금지 준수: 완료 판정 시 hits>0 → 정지·보고 후 본 분류로 종결).
- 계측 아티팩트 기록: bigscan PROGRESS 라인의 `hits=52→65`는 hits.jsonl 물리 줄 수(레코드×13줄) — 정본 카운트는 state/aggregate의 5.

## 8. UNKNOWN 해소 (완료 판정 실측 — 2026-11-06 09:45 KST)

```
REMAINING=0   # comm -23 <(jq -r .id /tmp/ax_e3_runs.jsonl | sort -nu) \
              #          <(sort -nu /tmp/ax_e3/done.txt) | wc -l
UNKNOWN=0     # jq -c 'select(.http == "UNKNOWN")' /tmp/ax_e3/state.jsonl | wc -l
aggregate     # unknown=0 · hit_runs 5(§7 분류) · scanned_runs(unique done)=33026
```

- **미스캔 구간 0** — 중간 보고의 "UNKNOWN ≈ 32,239" 해소. 패턴 11종 실자격증형 히트 0.
- **열거 스냅샷(2026-11-05T08:33Z) 이후 신규 run은 미포함** — flip 직전 델타 재스윙은 별도 단계(공개 전 동결 창과 연동·B5 flip runbook P2-e). 본 보고의 전수 결론은 스냅샷 시점 기준.

## 9. 신뢰도

- **열거 완전성: 높음**(33,026 vs 34,549 정합·이중 캡 재귀 분할 우회·instant 해석 검증[6h=378 vs 전일=1,096]).
- **경계 모델: 높음**(410/200 플립 19분 정밀도 실증 + 분리 스캔 중 410 전환 21건 확증).
- **마스킹 무결성: 검증됨**(합성 누출 테스트 0건, hits/state에 전체 값 기록 없음).
- **비밀 스캔: 전수 완료 — 실자격증형 히트 0**(candidate 5건 전건 오탐 분류·§7).

## 10. 완료 판정 명령(재현)

```bash
ps -p "$(cat /tmp/ax_e3_bigscan.pid)" >/dev/null 2>&1 && echo RUNNING || echo EXITED   # → EXITED
tail -6 /tmp/ax_e3_bigscan.log
comm -23 <(jq -r .id /tmp/ax_e3_runs.jsonl | sort -nu) <(sort -nu /tmp/ax_e3/done.txt) | wc -l  # → 0
jq -c 'select(.http == "UNKNOWN")' /tmp/ax_e3/state.jsonl | wc -l                               # → 0
/tmp/ax_e3_aggregate.sh   # §6 최종 집계
# 잔여·UNKNOWN >0 시 재개: /tmp/ax_e3_scan.sh /tmp/ax_e3_batches/full_remaining.txt
```
