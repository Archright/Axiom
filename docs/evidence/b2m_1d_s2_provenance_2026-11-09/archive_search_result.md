# 아카이브 저장소(Archright/Axiom-archive) 검색 결과 (2026-11-09)

대상: `Archright/Axiom-archive` (private, default branch main, created 2026-03-15,
last push 2026-11-06T05:17:11Z — 2026-11-06 rip-and-replace 재생성 이전 히스토리 보존).
클론: `b2m_1d/provenance/archive_clone/` — `git clone --filter=blob:none --no-checkout`
(커밋 3,992개; 캠페인 dir 하위-only 규칙 준수).

## 검색 방법·결과

1. **GitHub code search API** (default branch tip 전체 트리):
   `gh api "search/code?q=repo:Archright/Axiom-archive+capsule_min_measure"` → total_count **0**

2. **git log pickaxe (-S)** — 용어 창시(2026-11-05 10:59 KST) 이후~아카이브 tip(2026-11-06 05:16 UTC) 전수:
   - `git log --all --since=2026-11-04 -S'capsule_min_measure' --oneline` → **0건**
   - `git log --all --since=2026-11-01 -S'1,795' --oneline` → **0건**

3. **메커니즘 검증(음성 대조)** — pickaxe가 실제 blob을 읽어 검색함을 확인:
   `git log --all --since=2026-11-01 -S'b2_hermetic_proof_capsule' --format='%h %ci %s'` →
   `1acd5c47 2026-11-04 17:45:59 +0900 docs(evidence): B-2 detached cold acceptance — MERGE_SHA에서 캡슐 재현 확인`
   (알려진 문자열이 정상 검출됨 → 위 음성 결과는 유의미)

## 한계

- blobless clone 특성상 전체 3,992커밋 전수 -S 스캔은 blob 지연 fetch로 수백 초
  초과 미완료 — 대신 (a) tip 코드 서치, (b) 2026-11-01 이후 pickaxe 전수로 대체.
- 2026-11-05 10:59 이전 커밋에 용어가 존재할 수 없음: 'capsule_min_measure'는
  2026-11-05 세션(a99ee6f7)에서 최초 생성된 관측 보고서 명칭이며(세션 wire.jsonl
  71626행 첫 등장·파일 타임스탬프 2026-11-05 10:59), 그 이전 기기·저장소에 해당
  문자열의 존재 증거는 없다.
- 결론: **재생성 전 커밋 히스토리에 capsule_min_measure·1,795(본 맥락) 등장 0건** —
  용어의 커밋 기록상 첫 등장은 재생성 후 1d 계약(66c7a47, 2026-11-08)이다.
