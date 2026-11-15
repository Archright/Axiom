# VS-C1 — admission-ssot-drift 관찰 SHA 선택기 merged_at 앵커 재작업: 착지 전수 1분 그리드 재생 증거

상태: 재생 측정 증거(관측 시각 2026-11-15T04:42:20Z, gh 2.102.0, 대상 `Archright/Axiom`).
기준: 본 재생은 브랜치 `workstream/vs-c1-drift-merged-at`의 merged_at 앵커 선택기가
`gh pr list -R "$REPO" --state merged --base main --limit 100 --json number,mergedAt,mergeCommit,baseRefName`
→ `mergeCommit.oid != null` + `baseRefName=="main"` + `now-mergedAt >= SETTLE_MINUTES*60`
중 `max_by(.mergedAt)`로 관찰 SHA를 고르는 계약에 대한 것이다. 정본 근거:
`docs/spec/gh_run_observation_quirks.md` Q21, `.github/workflows/admission-ssot-drift.yml`
선택기 주석. 계약처방: 과제 지시(vs-c1 rework) — updated_at 앵커의 두 결함(재실행 이동·
per_page=20 절단) 해소.

## 무엇을 증명하는가

과제 검증 항목 "과거 92 landing 구간 재생 — 새 선별식이 각 시점에서 항상 착지 완료된
SHA를 고르고 빈 선택이 0": 현재 세대 저장소의 **착지 전수**(74 PR 착지; main
first-parent 체인 merge 74개와 1:1 대응, 74/74 `baseRefName=="main"`·`mergeCommit.oid`
존재 — 74가 전부다: "92 landing"은 merge_group run head 96개 기준의 과제 시점 셈이며,
그중 main에 실존하는 착지는 73개 + 큐 미경유 수동 병합 1개(PR #76)다)를 1분 그리드로
재생해 세 선택기를 비교했다.

판정 기준(모니터 leg3와 동일): 시점 T에서 선택된 SHA가 "착지 완료" ⟺ 6개
policy-expected required context(admission-check·bsec-integrity·debt-registry-gate·
generation-acceptance·axiom-operational-slice·publication-integrity) 각각에 대해
그 SHA에 GitHub Actions app(id 15368)이 생성한 check-run이 **T 이전에** 존재
(check-runs 목록 응답은 `started_at`을 운반 — `created_at` 없음, Q21 보조 관측).
빈 선택 = 선택기가 공백을 반환 → fail-closed exit 1.

## 데이터 수집(전부 live API, 2026-11-15T04:1x~04:4xZ)

- PR 병합 기록: 위 `gh pr list` 명령 그대로(74건).
- 각 착지 SHA(74) + 구 선택기가 고른 미착지 그룹 SHA(20)의 check-runs:
  `gh api --paginate "repos/Archright/Axiom/commits/{sha}/check-runs?per_page=100"`
  (Q19 규칙: per_page=100 + 전 페이지 + total_count 대조 — 94 SHA 전수, 4,082 check-run,
  app 전부 (15368, github-actions), max total_count 84 < 100).
- merge_group run 전수: `gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100" --paginate`
  (864 run, 9 page, total_count 864 일치 → 절단 없음; 전부 attempt 1 — 재실행 0,
  따라서 구 선택기의 updated_at 근사가 이 구간에서 정확).

## 결과 (canonical capture, 캡처 2026-11-15T04:42:20Z)

그리드: 1분 그리드 3,569 시점(첫 착지+정착창 2026-11-12T17:14:02Z → now) + 실제
모니터 실행 5 시점(admission-ssot-drift runs 43356861429·43426055447·43591242341·
43673487541·43676091085) = 총 3,574.

| 선택기 | 빈 선택(fail-closed 노이즈) | 미완료 관찰(FALSE RED 노출) | 미착지 SHA 관찰 |
|---|---|---|---|
| `old-main` (현행 main: completed+success `[0]`, per_page=20, 정착창 없음) | 0 | 491 (13.7%) | 112 시점 / 20개 distinct |
| `old-settle` (d653a4e: updated_at + 정착창, per_page=20) | **269 (7.5%)** | 0 | 33 시점 / 7개 distinct |
| `new` (본 변경: merged_at 앵커, PR 기록, limit 100) | **0** | **8 (0.22%)** | **0** |

`new`의 8 시점 예외 전부 동일 원인(2026-11-14T15:53:02Z~16:00:02Z): 회전 경로 수동
병합 PR #76(2026-11-14T15:32:33Z 착지, merge_group run 0건)이 [mergedAt+20분, 다음
큐 착지 PR #74+20분) 동안 최신 정착 착지로 선택된다. 그 커밋에는 6-context 중
admission-check·bsec-integrity·debt-registry-gate·generation-acceptance·
publication-integrity 5개가 영구 부재(큐가 required context 생산 경로) — 경쟁(race,
`late`) 위반은 전 구간 0: `new`의 위반은 `never`(비큐 착지)뿐이다. 실제 모니터 실행
5회 중 이 창에 든 것은 0회. `mergedBy`는 큐/수동 병합에서 동일(wintrover) — PR 목록
필드로 큐 경유 여부를 구별할 수 없다(Q21 경계).

결함 시점 재현(이슈 #57): 2026-11-14T11:41:46Z(run 43591242341, FALSE RED 4/6)에서
`new`는 PR #51 `1eeaecf62f`(2026-11-14T05:32:16Z 착지, 6-context 전부 존재)을
고른다 — 사고는 발생하지 않았을 것이다. 나머지 실제 실행 4 시점의 선택도 전부
6-context 완비 SHA였다(PR#6 573453f8df·PR#22 923633f426·PR#69 5ae980f447·
PR#79 859afebd6b).

여유: 어떤 20분 창에서도 최대 5건 착지(버스트 실측) — `--limit 100`의 20배.

## 재생 출력 전문

```
landings: 74, first 2026-11-12T16:54:02Z, grid start (first+settle) 2026-11-12T17:14:02Z, now 2026-11-15T04:42:20Z

grid points: 3574 (1-min grid + 5 actual monitor execution points)
new        empty=0     complete=3566  incomplete=8    unknown=0
old-settle empty=269   complete=3305  incomplete=0    unknown=0
old-main   empty=0     complete=3083  incomplete=491  unknown=0

new-selector violations (grid time, PR#, never-materialized ctx, late ctx):
   2026-11-14T15:53:02Z PR#76 never=['admission-check', 'bsec-integrity', 'debt-registry-gate', 'generation-acceptance', 'publication-integrity'] late=[]
   2026-11-14T15:54:02Z PR#76 never=[...동일...] late=[]
   2026-11-14T15:55:02Z PR#76 never=[...동일...] late=[]
   2026-11-14T15:56:02Z PR#76 never=[...동일...] late=[]
   2026-11-14T15:57:02Z PR#76 never=[...동일...] late=[]
   2026-11-14T15:58:02Z PR#76 never=[...동일...] late=[]
   2026-11-14T15:59:02Z PR#76 never=[...동일...] late=[]
   2026-11-14T16:00:02Z PR#76 never=[...동일...] late=[]
total new violations: 8

old-settle violations: 0 (first 5):

old-main violations: 491 (first 5):
   2026-11-12T17:51:02Z run 43273669535 never=[] late=['admission-check', 'publication-integrity']
   2026-11-12T17:52:02Z run 43273669569 never=[] late=['admission-check', 'publication-integrity']
   2026-11-12T17:53:02Z run 43273669569 never=[] late=['admission-check', 'publication-integrity']
   2026-11-12T17:54:02Z run 43273669569 never=[] late=['admission-check', 'publication-integrity']
   2026-11-12T17:55:02Z run 43273669569 never=[] late=['admission-check', 'publication-integrity']

old selectors picked never-landed (dropped/failed group) SHAs: 20 distinct
max PR landings in any 20-min window (burst): 5 (limit=100 headroom)
non-landing SHAs picked by old selectors needing check-run fetch: 0
```

## 판정

- 과제 검증 "빈 선택이 0": **성립**(3,574/3,574). 과제가 지적한 per_page=20 빈 선택
  결함은 구 선택기에서 269 시점(7.5%)으로 재현됐다(과제의 "시뮬 9.2%"와 동일
  클래스, 그리드·시점 정의 차이).
- "항상 착지 완료된 SHA": **경쟁(race)·미착지 클래스에 대해 성립**(0건 — 착지
  후 materialize가 덜 끝난 SHA 0건, main에 없는 SHA 0건). 유일 예외는 비(非)큐
  회전 착지 창 8분(0.22%)이며, 이는 착지 경로 자체가 required context를 생산하지
  않는 경계다 — Q21에 경계로 등록했고, 모니터는 그 SHA에서 missing context를
  정직하게 보고한다(드리프트가 아니지만 관측은 참). 실측된 실제 모니터 실행에서는
  한 번도 관측되지 않았다.
- 6-context 판정 기준은 현행 policy(`config/policy/merge_admission.json` v1.22.0 —
  requiredValidations 5 + verdictJob)와 동일하며, 재생 데이터에서 73/74 착지가
  6-context 전부 존재(예외 = PR #76 비큐 착지)로 이 시대 전 착지가 동일 기준으로
  판정 가능함을 확인했다.

## 재생 스크립트(전문 — 검증 시점 기준, /tmp/axiom-replay/replay_grid.py)

```python
#!/usr/bin/env python3
"""1-minute-grid replay of the admission-ssot-drift observation-SHA selectors
over the repo's full landing history (74 PR landings into main).

Selectors compared:
  old-main   : main's deployed selector — newest listed completed+successful
               merge_group run head_sha, no settle window, per_page=20.
  old-settle : d653a4e — same, plus (now - updated_at) >= SETTLE*60.
  new        : this task — gh pr list merged records, merged_at anchor:
               mergeCommit.oid present AND baseRefName == 'main' AND
               (now - mergedAt) >= SETTLE*60, most recent; observe_sha input
               precedence is outside the grid (it is an explicit override).

A pick is COMPLETE at T when, for every one of the 6 policy-expected required
contexts, the landing SHA carries a check-run of that name produced by the
GitHub Actions app (id 15368) with started_at <= T (the check-runs LIST
response carries started_at, not created_at; the monitor's leg-3 judge reads
exactly this existence+producer fact). Empty pick = selector returns "" ->
fail-closed exit 1.
"""
import json, glob, os, sys
from datetime import datetime, timezone

SETTLE = 20 * 60
EXPECTED = ["admission-check", "bsec-integrity", "debt-registry-gate",
            "generation-acceptance", "axiom-operational-slice",
            "publication-integrity"]
ACTIONS_APP_ID = 15368

def epoch(s):
    return int(datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
               .replace(tzinfo=timezone.utc).timestamp())

# ── landing records (the new selector's data source) ──
prs = json.load(open('pr_merged.json'))
for p in prs:
    p['merged'] = epoch(p['mergedAt'])
    p['oid'] = (p.get('mergeCommit') or {}).get('oid')
prs.sort(key=lambda p: p['merged'])
T0 = prs[0]['merged']
NOW = epoch(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
print('landings: %d, first %s, grid start (first+settle) %s, now %s'
      % (len(prs), prs[0]['mergedAt'],
         datetime.fromtimestamp(T0 + SETTLE, timezone.utc).strftime('%FT%TZ'),
         datetime.fromtimestamp(NOW, timezone.utc).strftime('%FT%TZ')))

# ── check-runs materialization per SHA ──
def load_ctx(oid):
    f = 'checkruns/%s.json' % oid
    if not os.path.exists(f):
        return None
    d = json.load(open(f))
    out = {}
    for cr in d['check_runs']:
        app = (cr.get('app') or {})
        if cr['name'] in EXPECTED and app.get('id') == ACTIONS_APP_ID:
            e = epoch(cr['started_at'])  # list response carries started_at, not created_at
            out.setdefault(cr['name'], e)
            out[cr['name']] = min(out[cr['name']], e)
    return out

ctx = {}
for p in prs:
    if p['oid']:
        ctx[p['oid']] = load_ctx(p['oid'])
missing_files = [p['oid'] for p in prs if p['oid'] and ctx[p['oid']] is None]
assert not missing_files, missing_files
# old-selector picks include never-landed group SHAs — load their check-runs too
for f in glob.glob('checkruns/*.json'):
    oid = f.split('/')[-1][:-5]
    if oid not in ctx:
        ctx[oid] = load_ctx(oid)

# ── merge_group runs (the old selectors' data source) ──
runs = json.load(open('mg_runs.json'))
for r in runs:
    r['created'] = epoch(r['created_at'])
    r['updated'] = epoch(r['updated_at'])
runs.sort(key=lambda r: r['created'], reverse=True)
landed_oids = {p['oid'] for p in prs if p['oid']}

def complete_at(oid, T):
    """(known, ok, never-materialized list, not-yet-materialized list)."""
    c = ctx.get(oid, None)
    if c is None:
        return False, None, None, None
    missing = [e for e in EXPECTED if e not in c]
    late = [e for e in EXPECTED if e in c and c[e] > T]
    return True, (not missing) and (not late), missing, late

def pick_new(T):
    asof = [p for p in prs if p['merged'] <= T][:100]
    cand = [p for p in asof if p['baseRefName'] == 'main' and p['oid']
            and (T - p['merged']) >= SETTLE]
    if not cand:
        return None
    return max(cand, key=lambda p: p['merged'])

def pick_runs(T, settle):
    asof = [r for r in runs if r['created'] <= T][:20]
    cand = [r for r in asof if r['status'] == 'completed'
            and r.get('conclusion') == 'success'
            and (T - r['updated']) >= settle]
    return cand[0] if cand else None

stats = {k: {'empty': 0, 'complete': 0, 'incomplete': 0, 'unknown': 0}
         for k in ('old-main', 'old-settle', 'new')}
violations = {'new': [], 'old-settle': [], 'old-main': []}
new_picked_not_landed = 0
picked_shas_old = set()
grid = list(range(T0 + SETTLE, NOW, 60))
# also judge the exact monitor execution points that fall inside the window
exec_points = [epoch(s) for s in (
    '2026-11-13T03:07:48Z', '2026-11-13T12:32:39Z', '2026-11-14T11:41:46Z',
    '2026-11-15T03:41:27Z', '2026-11-15T04:17:13Z')]
grid_set = set(grid)
for t in exec_points:
    if t not in grid_set and t > T0 + SETTLE:
        grid.append(t)

for T in sorted(grid):
    # new selector
    p = pick_new(T)
    if p is None:
        stats['new']['empty'] += 1
    else:
        known, ok, miss, late = complete_at(p['oid'], T)
        if ok:
            stats['new']['complete'] += 1
        elif not known:
            stats['new']['unknown'] += 1
        else:
            stats['new']['incomplete'] += 1
            violations['new'].append((T, p['number'], miss, late))
    # old-settle (d653a4e)
    r = pick_runs(T, SETTLE)
    if r is None:
        stats['old-settle']['empty'] += 1
    else:
        picked_shas_old.add(r['head_sha'])
        known, ok, miss, late = complete_at(r['head_sha'], T)
        if ok:
            stats['old-settle']['complete'] += 1
        elif not known:
            stats['old-settle']['unknown'] += 1
        else:
            stats['old-settle']['incomplete'] += 1
            violations['old-settle'].append((T, r['id'], miss, late))
    # old-main (no settle — main's deployed [0])
    r = pick_runs(T, 0)
    if r is None:
        stats['old-main']['empty'] += 1
    else:
        picked_shas_old.add(r['head_sha'])
        known, ok, miss, late = complete_at(r['head_sha'], T)
        if ok:
            stats['old-main']['complete'] += 1
        elif not known:
            stats['old-main']['unknown'] += 1
        else:
            stats['old-main']['incomplete'] += 1
            violations['old-main'].append((T, r['id'], miss, late))

N = len(grid)
print('\ngrid points: %d (1-min grid + 5 actual monitor execution points)'
      % N)
for k in ('new', 'old-settle', 'old-main'):
    s = stats[k]
    print('%-10s empty=%-5d complete=%-5d incomplete=%-4d unknown=%-4d'
          % (k, s['empty'], s['complete'], s['incomplete'], s['unknown']))
print('\nnew-selector violations (grid time, PR#, never-materialized ctx, late ctx):')
for v in violations['new'][:10]:
    print('  ', datetime.fromtimestamp(v[0], timezone.utc).strftime('%FT%TZ'),
          'PR#%d' % v[1], 'never=%s' % (v[2] or []), 'late=%s' % (v[3] or []))
print('total new violations:', len(violations['new']))
for k in ('old-settle', 'old-main'):
    print('\n%s violations: %d (first 5):' % (k, len(violations[k])))
    for v in violations[k][:5]:
        print('  ', datetime.fromtimestamp(v[0], timezone.utc).strftime('%FT%TZ'),
              'run %d never=%s late=%s' % (v[1], v[2] or [], v[3] or []))

# old selectors picking SHAs that never landed on main
unlanded = [h for h in picked_shas_old if h not in landed_oids]
print('\nold selectors picked never-landed (dropped/failed group) SHAs: %d distinct'
      % len(unlanded))

# burst sizing for the limit-100 margin: max landings in any 20-min window
worst = 0
for i, p in enumerate(prs):
    worst = max(worst, sum(1 for q in prs if 0 <= q['merged'] - p['merged'] < SETTLE))
print('max PR landings in any 20-min window (burst): %d (limit=100 headroom)' % worst)

# check-runs needed for old-selector non-landing picks
need = sorted(h for h in picked_shas_old if h not in ctx)
json.dump(need, open('need_checkruns.json', 'w'), indent=1)
print('non-landing SHAs picked by old selectors needing check-run fetch: %d' % len(need))
```

근사 한계(정직 기록): (1) 구 선택기의 "시점 T에서 completed" 판정은 run의 최종
status/updated_at로 근사한다 — 재실행이 있으면 부정확할 수 있으나 이 구간
864/864가 attempt 1이라 정확하다. (2) runs 목록의 "상위 20"은 created 내림차순
(실측: API 기본 정렬)으로 재현했다. (3) `new`의 100건 윈도는 "시점 T에 병합된
PR 상위 100"으로 재현했다(전체 74건이므로 전부 포함).
