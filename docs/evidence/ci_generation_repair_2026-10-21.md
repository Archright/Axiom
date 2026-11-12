# CI generation repair — judgment plan B-clean 실행 세대 전환 (2026-10-21)

> **분류**: 실행 증거 (관측·검증 기록) · **작업 주체**: Axiom Agent (`wintrover` 계정, repo/org admin, 사용자 전면 허가 하에 실행)
> **성격**: 이 문서의 착지 자체가 본 수리의 운영 acceptance다 — N-제외 `.md`만 변경한 PR(판정 closure는 기존 기록과 동일)이 merge queue를 통과하면, 종착 상태가 실증된다.

## 1. Ultimate Purpose / Terminal Outcome
- **Ultimate purpose**: GitHub 병합 권한이 신뢰할 수 있는 검증 결과에 의해서만 행사되도록 유지하면서, 검증기 자체의 결함도 신뢰 경계를 무너뜨리지 않고 수리할 수 있게 한다.
- **Terminal outcome**: docs-only PR이 실제 merge queue를 통과해 main에 MERGED되고, 그 landing run에서 s1a가 `basis=EXECUTED`, `verdict=PASS`로 관측된다.

## 2. 수리 전 결함 (관측으로 확정)
- **D1 — SourceCoherence/실행 순서.** lane이 후보 `src/`를 B 작업공간에 overlay한 뒤 B-built `bin/ax`를 실행했다. `src/cli/main.nim:60-74`는 live `src/` 해시와 `BuildSourceHash`를 비교해 불일치 시 종료한다. PR #1006의 merge_group run `39537491732`에서:
  `[FATAL] Engine source/source mismatch (SourceCoherence FAIL) tree=4001324870617279706 embedded=-4862258572969452841`.
  armed attest는 B-pristine 작업공간에서 closure를 재도출하므로(`judgment_cas.nim:1962-1976`), plan이 B-clean에서 실행되지 않으면 decision key 자체가 어긋난다. B/M 세대 강제(`34f34a86e`, 2026-10-20 21:19Z) 이후 `src/**/*.nim`을 변경한 PR은 0건 착지했다.
- **D2 — s1a REUSED 모순.** plan은 landing venue에서도 `basis=REUSED`를 낼 수 있었으나 GO lane(`admission-check.yml:3483`)과 attest(`:1705`)는 s1a REUSED를 하드 실패시켰다. PR #1005가 이 이유로 차단됐다. 계약 문서(`docs/spec/test_judgment_cas_contract.md`)는 여전히 REUSED를 유효 basis로 규정한다 — 이는 POLICY 결정이며 본 수리는 "s1a는 landing에서 항상 실행" 방향으로 구현했다(계약 개정은 후속).

## 3. Authority Preflight (실측)
| 권위 | 소유 | 관측된 권한 |
|---|---|---|
| GitHub merge admission (rulesets/required checks/merge queue) | GitHub | 플랫폼 |
| org rulesets 25218071/23943917 | org admin(`wintrover`) | token `admin:enterprise, admin:org, gist, repo, workflow`, org role `admin` |
| org controller `Archright/.github` | org admin | repo `admin:true` |
| Axiom repo/queue | repo admin | repo `admin:true` |
| `AXIOM_READONLY_TOKEN` | org architect | Actions secret 존재(값 미열람) — `pin-promotion-gate`가 human PR에서도 읽음(실증) |
| s1a 영구 재사용 정책 | 인간 아키텍트 | 본 슬라이스에서 미결정(후속) |

## 4. 수리 체인 (실제 SHA·run id)
1. **PR #1007** (`fix/bclean-judgment-plan`, head `3da56c2c0b746faad5bf49340e22f4c33c33d23f`):
   - `candidate-identity` step(M sha/tree, B tree, M 객체 executor로 fetch, overlay digest) → **Judgment CAS plan을 overlay 이전 B-clean에서 실행**(`git diff --quiet HEAD -- src` 벨트) → overlay(등가성 벨트) → evidenceId contract check → GO-critical tests.
   - 테스트 step에 `AXIOM_JUDGMENT_CAS_TESTED_TREE_OID == M_TREE`, overlay digest, `decision.probeTreeOid == M_TREE` assert 추가.
   - A2 triple: workflow blob `50ddd8a38049cdb05d678b3d358d4c951ab3c979` == TWS `trustedAdmissionWorkflowSha` == epoch `productionExecutionPin` (동일 커밋).
   - 로컬 검증: `verify_trusted_writer_set.sh` PASS, `validate_workflow_shell.sh` 193/0, `test_admission_check_stages.nim` PASS, A2 pin-pairing 3-way PASS. (기존 red: `test_admission_venue_split.nim` 32 vs 33 — 본 PR 이전부터 존재, 본 PR은 ungated step 추가로 count 불변)
   - **착지**: merge_group run `39548963944`, group commit `7e0caa62af61f33224618c0c1912d7ae365ddbc9` — `attest / go-critical-lane (0)·(1)` success, aggregate `admission-check` success(check-run `119057876261`), PR #1007 MERGED 2026-10-21T05:35:20Z.
2. **org PR #245** (`Archright/.github`, `ci/pin-admission-check-repair`): attest/verdict의 `uses:` 두 곳 → `7e0caa62…`. `pin-promotion-gate (DEBT#473)` PASS(5s) — `AXIOM_READONLY_TOKEN`이 human PR에서 유효함을 실증. MERGED → org main `c1752d7ebbcff1d01d82c922a5f97d5b86622880`.
3. **Ruleset 재핀** (REST PUT 성공): 25218071/23943917 모두 `workflows[].sha = c1752d7e…`; readback byte-consistency — sha 외 전 필드 불변, `enforcement=active`, `bypass_actors=[]`.
   - 3-way 결속: ruleset sha `c1752d7e`(controller commit) → controller `uses: admission-check.yml@7e0caa62`(callee commit) → callee blob `50ddd8a3` == Axiom main TWS == epoch pin.
4. **PR #1006** (`fix/s1a-landing-executed`, update-branch 후 head `f2059675431068d412dfb436b50f1cf5b306b4d1`):
   - `enqueuePullRequest(expectedHeadOid=f2059675…)` → `isInMergeQueue=true`, entry `QUEUED`.
   - merge_group run `39552882263`, group commit `6e69671e611d9134c5e3da3a8ab038badeab818b`.
   - **E1**: `run.referenced_workflows` = `admission-check.yml@7e0caa62…` (새 callee 실제 실행). **E2**: lane/attest job log `Uses: Archright/Axiom/.github/workflows/admission-check.yml@7e0caa62…`.
   - lane 0(job `119066294687`): `[candidate-identity] M=6e69671e tree=f8231fea B tree=8b7f5dc9` → `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` → `exec-record[s1a] verdict=PASS basis=EXECUTED evidenceKey=b098164f6289` (s1a 실행 599,710ms) → `s1a EXECUTED+1/1`.
   - attest(job `119070470935`): `[go-exec] exec record[s1a] OK — verdict=PASS basis=EXECUTED decision=EXECUTED` (+ 3개 extension subject 모두 OK).
   - PR #1006 MERGED 2026-10-21T06:19:42Z → main = `6e69671e…`, 큐 0. **main의 B-built 바이너리가 이제 s1a force를 포함한다**(`judgment_cas.nim:1571-`).

## 5. 본 PR의 acceptance (자기 참조)
- 이 PR은 `docs/evidence/`의 `.md` 하나만 추가한다(N-제외 → 판정 closure는 #1006 착지 기록과 동일 → 수리 전이라면 REUSED → lane 하드 실패).
- 기대 관측: landing run에서 `AXIOM_JUDGMENT_CAS: EXECUTED — s1a on the landing venue is the terminal acceptance judgment — always executed (never reusable)` + `exec-record[s1a] verdict=PASS basis=EXECUTED` + MERGED + `mergeQueue.entries.totalCount=0`.

## 6. 검증 명령 (재현)
```bash
gh api repos/Archright/Axiom/actions/runs/39552882263 --jq '.referenced_workflows[]|{path,sha}'
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/119066294687/logs | grep -a 'AXIOM_JUDGMENT_CAS\|exec-record'
gh api orgs/Archright/rulesets/25218071 --jq '.rules[]|select(.type=="workflows")|.parameters.workflows'
gh api "repos/Archright/Axiom/contents/.github/workflows/admission-check.yml?ref=7e0caa62af61f33224618c0c1912d7ae365ddbc9" --jq .sha   # 50ddd8a3…
gh api graphql -f query='query{repository(owner:"Archright",name:"Axiom"){mergeQueue(branch:"main"){entries{totalCount}}}}'
```

## 7. 기록된 deviation / 후속 (본 수리 밖)
- B-clean에서 closure 구성요소 ①+②(test source + 전이 import closure)·③(golden fixtures)은 **executor의 B 복사본**을 측정한다. M-결속은 ⑤(`semanticSetDigest`, M^{tree} 전체)와 exec record의 `candidateTreeOid`/`overlayManifestDigest`가 담당한다(⑤는 ①의 파일 집합을 포함하는 더 강한 결속).
- 후속: `JudgmentKeyScheme` v4→v5 컷, `docs/spec/test_judgment_cas_contract.md`의 ①/② 성분 의미 개정(또는 deviation 항목), `test_admission_venue_split.nim` count 32→33 정합, org repo 자체 `admission-gate-v2`의 20/20 runs·0 jobs 조사, 2026-10-20 24초 비상 창 감사 기록 복구.
- 이 슬라이스는 s1a의 **영구** 재사용 정책을 확정하지 않는다 — acceptance 요구(EXECUTED)와 영구 정책은 분리됐다.