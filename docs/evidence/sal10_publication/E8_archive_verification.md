# E8 — Axiom-archive 폐쇄적 자산 인벤토리·기계 검증 (Archive Closure)

**실행일**: 2026-11-09 (관측창 2026-11-09T05:00Z–05:51Z) · **판정**: 문서 말미 `ARCHIVE_MIGRATION_RESULT` 블록

**기계 판독 manifest**: [E8_archive_closure_manifest.json](E8_archive_closure_manifest.json) (카테고리 수량·disposition·artifact 전체 ID 6,661개·표본 digest)

## Ultimate Purpose

3세대 체인의 구 정본 `Archright/Axiom-archive` (repo id **1182104685**, private)에 남은 **모든 GitHub 관측 가능 자산**에 대해 폐쇄적(closed-universe) 인벤토리를 실측하고, 표본 무결성 테스트·신선 클론 복원 테스트로 원본 보존 상태를 기계 검증한다. 아카이브의 최종 용도는 **원본 보존(원천 봉쇄·사후 조사 원본)**이며, 이 문서는 그 폐쇄(closure)가 관측 표면 전수에 대해 완료되었음을 증명한다.

## 관측 원칙·경계

- **아카이브 mutation 0**: 전 관측이 REST GET·GraphQL query·`git ls-remote`·`git clone`·`gh repo clone`이다. 아카이브에 push·PUT·POST·DELETE 없음 (아카이브 main은 자체 ruleset 20303214 — 필수 검사 5종 + merge queue — 으로 원천 봉쇄).
- **시크릿 실값 미조회**: `/actions/secrets`는 이름만 기록 (GitHub API가 실값을 노출하지 않음 — NON_TRANSFERABLE 근거).
- **Webhook 상세 폐기**: hook `config.url`은 host만 기록 관례 — 실측 결과 **0건**으로 본 규칙의 적용 대상 없음.
- **집합 정적성 근거**: 아카이브 Actions `enabled:false` (GET `/actions/permissions` 실측) — 신규 run·artifact 발생 원천 없음. artifact 집합은 감소(90일 보존 만료)만 가능.

## 1. 기준값 재확인 (지시 기준값 2026-11-09 vs 본 실측)

| 항목 | 기준값 (지시) | 본 실측 (2026-11-09T05:41Z) | 판정 |
|---|---|---|---|
| main tip | `b4c08e94e1128cc6ae886289b56969b552fcaae6` | `b4c08e94e1128cc6ae886289b56969b552fcaae6` (ls-remote `refs/heads/main`·`HEAD` 일치) | 일치 |
| 커밋 수 | 3,992 | 3,992 — `gh api -i '…/commits?per_page=1&sha=main'` Link `rel="last"` `page=3992` | 일치 |
| 브랜치 | 112 | 112 — `ls-remote` `refs/heads/` 112행 (main 1 + `gh-readonly-queue/*` 6 + 기타 105) | 일치 |
| 태그 ref | 139 | 139 (peeled `^{}` 포함) — **unique 태그 85** (재산출) | 일치 |
| PR refs | ≈1,275 | 1,275 = head 1,274 + `refs/pull/1274/merge` 1 | 일치 |
| Actions runs | 34,956 | 34,956 — `/actions/runs?per_page=1` `.total_count` | 일치 |
| Artifacts | 6,689 / 1,133,125,505 B | **6,661 / 702,585,144 B** (동일일 선행 실측 대비 Δ−28 / Δ−430,540,361 B) | 수량 근접·bytes 불일치 → §5 |
| 자체 ruleset | 4종 active ("main" 20303214) | 4종 active — `main` 20303214 (필수 검사 5종 + `merge_queue` 1)·`artifact-hygiene` 23969951·`cas-probe-scratch` 23916707·`execution-surface-create` 23967915 | 일치 |

## 2. 자산 인벤토리·disposition 매트릭스

Disposition 어휘 (닫힌 집합): **TRANSFERRED**(동일 내용 현행 이월) / **ARCHIVED**(아카이브 원본 보존이 최종 처리 상태) / **RECREATED**(재작성·재구성 세대로 현행 존속 — SHA 불변 아님) / **NON_TRANSFERABLE**(이전 수단 부재 — API 미제공) / **EXPIRED**(90일 보존 만료 소실) / **NOT_REQUIRED**(이월 계약상 불요 — org 스코프 등) / **NOT_PRESENT**(부재·0건).

| # | 카테고리 | 수량 (실측) | Disposition | 증거 (명령 → 관측) |
|---|---|---|---|---|
| 1 | Git 커밋 (main 이력) | 3,992 | **RECREATED** | Link header `page=3992`; 현행 repo main 재작성 세대 실측 `git rev-list --count HEAD` = **97** (E7 전체 이력 재작성 세대 — 커밋 수 축소는 재작성·스쿼시 세대 특성, 원본은 아카이브 보존) |
| 2 | main tip | `b4c08e94` | **RECREATED** | 아카이브 HEAD ↔ 현행 main `70d1b66f` (E7 commit-map + PR #25/#42 병합 세대) |
| 3 | 브랜치 (non-main) | 111 (`gh-readonly-queue` 6 포함) | **ARCHIVED** | E6 "미이월(의도적): 워크스트림 브랜치 111개·gh-readonly-queue/*" — 아카이브 보존, 현행 refs/heads 3 (main·axiom/certificates·axiom/evidence-cas) |
| 4 | 태그 (unique) | 85 (ref 139 = 대상 85 + peeled 54) | **ARCHIVED** | 아카이브 `ls-remote refs/tags` 85종; **현행 repo 태그 0종 실측** (`git ls-remote …refs/tags/*` → 0행) — E6 부트스트랩이 85종을 1차 clean-origin(삭제됨)에 이월했으나 3세대 재생성 시 미재이월. 원본은 아카이브에 온전 (복원 테스트 §4: `v0.6.0` checkout 성공) |
| 5 | PR | 1,274 (closed 1,274·open 0·merged 1,148) | **ARCHIVED** | `search/issues type:pr state:closed` 1,274 · `state:open` 0 · `is:merged` 1,148; PR refs 1,275와 정합 (아래 번호 공간 참조); E6 "issues/PR 메타데이터" 의도적 미이월 |
| 6 | PR 리뷰 | **0** | **NOT_PRESENT** | GraphQL 전수: `pullRequests(first:100)` 13페이지 × `reviews{totalCount}` → 노드 1,274·리뷰 총합 0 (전 PR 리뷰 객체 부재 — 실측 사실) |
| 7 | Issues | 12 (closed 12·open 0) | **ARCHIVED** | `search/issues type:issue state:closed` 12 · `state:open` 0; 번호 공간 참조 |
| 8 | Discussions | 0 (기능 비활성) | **NOT_PRESENT** | GraphQL `hasDiscussionsEnabled`=false · 카테고리 0 · `discussions.totalCount` 0 |
| 9 | Actions runs | 34,956 (최신 2026-11-07T14:12:08Z) | **ARCHIVED** | `/actions/runs?per_page=1` total_count 34,956; E6 시점 34,548 → 동결 직전까지 +408; 현재 `enabled:false` 실측 |
| 10 | Actions workflows | 33 (active 31·disabled_manually 2) | **ARCHIVED** | `/actions/workflows` total_count 33; 워크플로 **파일 본체**는 재작성 이력에 포함되어 현행 존속(현행 등록 워크플로 27종 실측 — 세대 차이 반영); 아카이브의 33종 레지스트리 객체는 원본 보존 |
| 11 | Actions variables | 2 (`CI_RUNNER_MAP`·`REARM_APP_ID`) | **RECREATED** | 아카이브 `/actions/variables` 이름 2종 ↔ 현행 repo 동일 2종 실측 (E6 재구성 기록과 정합) |
| 12 | Actions secrets | 2 (이름만: `REARM_APP_PRIVATE_KEY`·`REARM_ARM_TOKEN`) | **NON_TRANSFERABLE** | 실값 판독 API 부재 (E6 "시크릿 실값(값 이전 API 미제공)"과 정합); 현행 repo는 값 미이전 상태로 재생성 대상 — 본 관측은 이름 목록만 |
| 13 | Artifacts | 6,661 / 702,585,144 B | **ARCHIVED** (생존분) + **EXPIRED** 5,511 (§5) | 전수 페이지네이션 67/67페이지 (502 재시도 포함, page 1–67·total_count 6,661 2회 교차)·중복 ID 0·`expired` 전 항목 false; 표본 13종 다운로드 무결성 13/13 PASS (§3) |
| 14 | Releases·첨부 assets | 0 | **NOT_PRESENT** | `/releases?per_page=10` → `[]`; `/releases/latest` → 404. (표본 asset 다운로드는 대상 0건으로 수행 불가 — 부재 자체가 관측) |
| 15 | Wiki | 콘텐츠 0 | **NOT_PRESENT** | repo 플래그 `has_wiki:true`이나 `git ls-remote …/Axiom-archive.wiki.git` → "Repository not found" (위키 저장소 미생성 — 플래그와 콘텐츠 부재 구분 기록) |
| 16 | Pages | 없음 | **NOT_PRESENT** | `/pages` → 404; `has_pages:false` |
| 17 | Packages — container | 1 (`axiom-ci`, org 스코프) | **NOT_REQUIRED** | `/users/Archright/packages?package_type=container` → id 12706580·private·생성 2026-06-09T11:11:40Z·versions 16·갱신 2026-08-01; 연결 저장소 없음(`/orgs/…/repositories` 404 = repo 비연결 org 패키지). **소비자 = Axiom CI 러너 인프라**: 현행 repo `data/nimtry_compiler_lock.json` 핀 `ghcr.io/archright/axiom-ci:nim-2.2.10-lean-4.29.0-v2` + `docs/spec/hermetic_build.md` (아카이브 워크플로는 `vars.CI_RUNNER_MAP` 러너 그룹 경유 소비 — 30개 `runs-on` 관측). repo 이월 대상 아닌 org 자원 — 폐쇄 영역 밖 존속 |
| 18 | Packages — npm | 0 | **NOT_PRESENT** | `/users/Archright/packages?package_type=npm` → 빈 |
| 19 | Environments | 3 (`ci-provider-router`·`diagnostic-authority`·`release-authority`) | **RECREATED** | 아카이브 `/environments` 3종 ↔ 현행 repo 동일 이름 3종 실측 (E6 재구성 기록과 정합) |
| 20 | Deployments | 3,357 | **ARCHIVED** | `--paginate /deployments?per_page=100` 합산 3,357 — 과거 배포 이력, 이월 계약상 미대상·원본 보존 |
| 21 | Collaborators (direct) | 0 | **ARCHIVED** (접근통제 유지) | `/collaborators?affiliation=direct` → 빈; 접근은 org 팀 경유 |
| 22 | Teams | 1 (`architect`, push) | **ARCHIVED** | `/teams` → `architect` 1팀 push. 현행 repo는 팀/직접 collaborator 0 실측 (소유자 직접 통치로 전환 — 세대별 권한 모델 차이 기록) |
| 23 | Topics | 0 | **NOT_PRESENT** | `/topics` → `[]` |
| 24 | Labels | 16 | **ARCHIVED** | `--paginate /labels` 합산 16; 현행 repo 11종 실측 (메타데이터 미이월 — 이월 계약상 불요) |
| 25 | Milestones | 0 | **NOT_PRESENT** | `/milestones?state=all` → 빈 |
| 26 | Webhooks (hooks) | 0 | **NOT_PRESENT** | `/hooks` → 빈 (기록 폐기 규칙[^1] 적용 대상 0건) |
| 27 | Deploy keys | 0 | **NOT_PRESENT** | `/keys` → `count: 0` |
| 28 | Projects V2 | 0 | **NOT_PRESENT** | GraphQL `projectsV2{totalCount}` = 0 |
| 29 | Projects (classic) | 관측 불가 | **UNABLE_TO_OBSERVE** | `/projects` → 404 (classic Projects REST API 폐지 — projectsV2=0이 현행 신호; 클래식 잔존은 API 비노출) |
| 30 | Org installations (GitHub Apps) | 8종 org 단위 | **NOT_REQUIRED** | `/orgs/Archright/installations` total 8 (`axiom-ci-elastic`·`axiom-release-authority`·`ubicloud-managed-runners`·`axiom-ci-provider-router`·`northflank-cloud-build-run`·`axiom-runner-registrar`·`axiom-rearm`·`axiom-cli-release-authority`); 'selected' 5종의 저장소 목록 `/installations/{id}/repositories` 전건 404 → 권한 미달로 미관측 (§7). org 스코프 — repo 이월 대상 아님 |
| 31 | LFS 객체 | 1 KEEP (`docs/spec/SVF-SVC_Software_Verification_Using_SVF.pdf`) | **RECREATED** | 아카이브: `git lfs ls-files -l` OID `8c744d79…461eaa`·`git lfs pull` 후 실측 **10,076,526 B**·sha256 == OID (§4); 현행 repo 동일 경로·동일 OID·동일 byte 실측 — 세대 간 무결 이월 |
| 32 | 자체 rulesets | 4 active | **ARCHIVED** | `/rulesets` — main 20303214 (필수 검사 5종: admission-check·bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice + merge_queue) 외 3종. 아카이브 main 변경 원천 봉쇄 장치로 보존. 현행 repo는 이름 해석 기반 4종으로 재구성 (E6 관측 정정 참조) |
| 33 | repo 설정 스냅샷 | — | **ARCHIVED** (기록 보존) | `GET /repos/Archright/Axiom-archive` 전체 JSON 저장 (비밀 없음): private·archived:false·disabled:false·default main·생성 2026-03-15T03:28:36Z·pushed 2026-11-06T05:17:11Z·size 65,642KB·language Nim·license NOASSERTION·merge: MERGE 만 허용·auto_merge 허용·delete_branch_on_merge true·forking 금지 |

[^1]: 비밀성 값 폐기 규칙 — hook URL은 host만 기록한다. 실측 결과 hook 0건으로 실제 적용 없음.

### PR 번호 공간 완전 해명 (refs 1,275의 정합성)

`ls-remote refs/pull` 고유 번호 1,274 (최소 #2·최대 #1290) + `refs/pull/1274/merge` 1 = 1,275 refs. 번호 1–1,290 (1,290개) = PR 1,274 + 이슈 12 + **삭제된 번호 4** (#1·#72·#73·#74 — `GET /issues/{n}` 410 "This issue was deleted"). 잔여 결손 번호(#701·#735·#739·#746·#747·#1033·#1038·#1071·#1072·#1078·#1108·#1248)는 전부 이슈(`pull_request:false` 표본 검증) — 번호 공간 100% 소진, 수량 정합.

### PR 표본 5 — 본문 sha256 (위·변조 대조 기준선)

| PR | 상태 | merged | head | 본문 sha256 |
|---|---|---|---|---|
| #2 | closed | false | `5d37c317cc3e` | `a851fd66d1c90320234c2030036895f67de4f2fe115a61f245a523c920e6cd7c` |
| #300 | closed | false | `2dc0168f1bdf` | `40e2255b33ff6906c95d506c513769aa8f7f7d22d971d0ded26596af2651b346` |
| #700 | closed | true | `9543b9f02a5e` | `a02eb5b25bf02e8f4233b0c60e8d425e2dadf4e0f92ea09f87ee9b7add3e9787` |
| #1000 | closed | true | `3516951e644a` | `57e65e8333df8a97e66c53af39d9bd6b6efd080c94e7293498c179a3edd2d772` |
| #1290 | closed | true | `233b89a0f522` | `c2587e226ec77aac781d602c60bc272578b98c3b174232065702211f051bbcb6` |

관측: `gh api /repos/Archright/Axiom-archive/pulls/{n}` → `jq -r '.body' \| sha256sum`. 표본 5종 리뷰 수 전부 0 (전수 관측과 정합).

## 3. 표본 무결성 테스트 — Artifacts 13종

선정: 최고령 3·최신 3·최대 2·최소 2·중간 3 (결정론적 위치 선정). 각 항목 `GET /actions/artifacts/{id}/zip` 다운로드 후 `stat -c%s`·`sha256sum`을 API `size_in_bytes`·`digest`(sha256)와 대조.

| Artifact ID | 이름 | bytes (실측/API) | sha256 실측 = digest | size | sha |
|---|---|---|---|---|---|
| 9550283026 | gate-telemetry | 653/653 | `34853540…699ae0bf` | OK | OK |
| 9550284301 | gateway-tests | 1727/1727 | `a5c9ac27…ca7342d5` | OK | OK |
| 9584595937 | gate-telemetry | 631/631 | `c5118129…4332c93d` | OK | OK |
| 13480356089 | axiom-operational-slice-r3 | 2216/2216 | `6fd82b17…206cc` | OK | OK |
| 13480012279 | axiom-operational-slice-evidence | 11701/11701 | `c37b44af…dcdc61` | OK | OK |
| 13479691221 | admission-verdict-b4c08e94…-1 | 1191/1191 | `b823ea68…1734fcd7` | OK | OK |
| 12574857672 | subject-certificate-1 | 4441076/4441076 | `f837caef…3065ef3` | OK | OK |
| 12882122408 | subject-certificate-1 | 4439866/4439866 | `d580c34d…37f73ba0` | OK | OK |
| 12261621362 | tested-tree-digest | 182/182 | `b0add583…0991` | OK | OK |
| 12325634055 | tested-tree-digest | 183/183 | `77233823…a49cf6a` | OK | OK |
| 13127420764 | observer-payload-9381cb3a…-1 | 453/453 | `2d423971…eaee061d` | OK | OK |
| 12968641478 | axiom-operational-slice-r3 | 2223/2223 | `6a047548…9b6c54` | OK | OK |
| 12311301021 | observer-payload-d0d23da5…-1 | 455/455 | `fb4506af…ddebc3f2` | OK | OK |

**판정: 13/13 PASS** (size 13/13·sha256 13/13). 전체 digest 표는 manifest 참조. 이 결과는 `size_in_bytes`가 실측 zip byte 수와 정확히 일치함을 검증 → §5의 총 bytes 실측(702,585,144)이 신뢰 기반임을 뒷받침.

## 4. 복원 테스트 — 신선 클론

| 단계 | 명령 → 관측 | 판정 |
|---|---|---|
| 클론 | `GIT_LFS_SKIP_SMUDGE=1 gh repo clone Archright/Axiom-archive /tmp/vsa-archive-clone` → exit 0 | PASS |
| HEAD | `git rev-parse HEAD` → `b4c08e94e1128cc6ae886289b56969b552fcaae6` | PASS (기준값 일치) |
| 커밋 수 | `git rev-list --count HEAD` → **3992** | PASS |
| 객체 무결성 | `git fsck --full --no-dangling` → 출력 0행·exit 0 | PASS (dangling 포함 이상 0) |
| 태그 checkout | `git checkout v0.6.0` → `c36af94ce24b1d9018caa92e37378e5ffcecbeba` | PASS |
| LFS KEEP | `git lfs ls-files -l` → OID `8c744d7975602f179d5f079ac37b6b13b540bc1e6c10312676c310f655461eaa` | PASS (E6 기록 OID 일치) |
| LFS 실체 | `git lfs pull` 후 `stat` → **10,076,526 bytes**·`sha256sum` == OID | PASS (기준값·E6 기록 일치) |

아카이브는 임의 시점 완전 복원 가능함이 실증됨 (refs·객체그래프·LFS 객체 전부 서버 존재·정상).

## 5. EXPIRED 소실 범위·bytes 불일치 정직 기록

- **EXPIRED 산출**: E6 기록(2026-11-06) artifacts **12,172** → 본 실측 생존 **6,661** = **5,511 EXPIRED** (90일 보존 만료 — repo별 retention null → org 기본 90일 적용; 생존 최고령 2026-08-25T05:21:43Z·최신 2026-11-06T05:24:58Z).
- **동일일 선행 기준값과의 차이**: 6,689 → 6,661 (Δ−28): 집합이 감소만 가능하므로 만료 지속 진행으로 설명 가능. 총 bytes 1,133,125,505 → **702,585,144** (Δ−430,540,361 B): **원인 관측 불가** — 삭제 완료된 artifact의 size는 관측 표면에서 소실되며(본 실측 생존 최대 4.44MB), 28개 평균 크기로는 설립되지 않는다. 본 실측값은 전수 페이지네이션 67/67·total_count 2회 교차·중복 ID 0·표본 13종 다운로드 대조로 재현 가능하며 **실측 권위값으로 채택**한다. 선행 기준값의 산출 방식은 본 관측 표면으로 검증 불가 — `UNABLE_TO_OBSERVE` (§7).
- 만료는 지속 진행 중이므로, 본 문서의 artifact 수량은 **관측 시각 2026-11-09T05:41Z 기준 스냅샷**이다.

## 6. 폐쇄성 명시 (closed universe)

본 인벤토리의 관측 표면 전수 — 이 목록이 GitHub REST/GraphQL의 repo 스코프 자산 노출 표면 전부임을 명시한다:

- **refs**: `git ls-remote` (heads·tags·pull·HEAD 전수 1,527 refs = 1 HEAD + 112 heads + 139 tags + 1,275 pull)
- **REST**: `/repos/{r}`·`/commits`·`/pulls[/{n}]`·`/issues[/{n}]`·`/releases`·`/pages`·`/keys`·`/hooks`·`/labels`·`/milestones`·`/topics`·`/teams`·`/collaborators`·`/environments`·`/deployments`·`/projects`(폐지)·`/rulesets[/{id}]`·`/actions/{runs,workflows,variables,secrets,permissions,artifacts[/{id}/zip]}`
- **GraphQL**: `repository{hasDiscussionsEnabled, discussionCategories, discussions, projectsV2, pullRequests{reviews}}`
- **org 스코프**: `/orgs/Archright/installations`·`/users/Archright/packages`·`/orgs/Archright/packages/container/axiom-ci[/repositories,/versions]`
- **Git/LFS**: clone·fsck·checkout·`git lfs ls-files/pull`

**API 비노출 표면** — 서버 내부 캐시·인덱스 지연 상태, 시크릿 실값, 삭제 완료 자원(410 이슈 본문·만료 artifact 바이트), classic Projects 잔존 여부, 설치별 저장소 접근 목록(권한 미달 404)은 **"관측 불가 — 처리 결과 대상 아님"**으로 기록한다 (폐쇄 범위는 노출 표면에 한정하며, 비노출 표면을 추정해 채우지 않는다).

## 7. 한계·관측 불가 (UNABLE_TO_OBSERVE) 정직 목록

1. **Artifacts 총 bytes 기준값 불일치 원인** (§5) — 선행 실측 1,133,125,505 B 대비 Δ−430,540,361 B의 구성(어느 artifact가 소실됐는지)은 소실 후 비관측.
2. **Installation 저장소 목록** — 'selected' 5종 GitHub App의 `/installations/{id}/repositories` 전건 404 (토큰 권한 미달 추정 — 원인 자체도 미확정).
3. **Classic Projects** — REST API 404(폐지)로 잔존 여부 비노출; projectsV2=0만 신호.
4. **삭제된 이슈 #1·#72·#73·#74** — 410 Gone: 존재(번호 공간 소진)는 실측, 내용·종류는 비관측.
5. **Actions 동결 정확한 시점** — org 감사로그 `phrase=repo:Archright/Axiom-archive` 조회 빈 응답(보존 창/문법 불명확); 현재 상태 `enabled:false`·최신 run 2026-11-07T14:12:08Z 실측만 기록.
6. **PR 리뷰 0건** — 결함이 아니라 실측 사실이나, "리뷰 없는 병합" 관행의 이유는 관측 영역 밖 (AGENTS 회고가 아닌 API 관측 문서).

## 8. 관측 순수성

본 문서의 모든 아카이브 접근은 GET/query/clone이다 — mutation 0 (작업 실패 조건 준수). 현행 repo `Archright/Axiom`에도 본 인벤토리 단계에서 mutation 없음 (증거 문서 PR은 본 문서가 속한 workstream 브랜치 경로).

---

## ARCHIVE_MIGRATION_RESULT

```text
repo:                  Archright/Axiom-archive (id 1182104685, private, 구 정본 1세대)
observedAt:            2026-11-09T05:00Z–05:51Z (artifact 스냅샷 05:41Z)
accessMode:            read-only GET/query/clone — 아카이브 mutation 0

inventory:             33 카테고리 disposition 완료 — 누락 0
  RECREATED:           5  (main 이력·main tip·variables 2종·environments 3종·LFS KEEP 1)
  ARCHIVED:            13 (브랜치 111·태그 85·PR 1,274·Issues 12·runs 34,956·
                           workflows 33·artifacts 생존 6,661·deployments 3,357·
                           collaborators 0(통제 유지)·teams 1·labels 16·rulesets 4·설정 스냅샷)
  NON_TRANSFERABLE:    1  (secrets 실값 — 이름 2종만 기록)
  EXPIRED:             1  (artifacts 5,511 — E6 12,172 → 생존 6,661, 90일 보존 만료)
  NOT_REQUIRED:        2  (container package axiom-ci — org 스코프·CI 인프라 사용 중,
                           org installations 8종)
  NOT_PRESENT:         11 (PR 리뷰 0·Discussions·Releases 0·Wiki 콘텐츠·Pages·npm packages·
                           Topics 0·Milestones 0·Webhooks 0·Deploy keys 0·Projects V2 0)
  UNABLE_TO_OBSERVE:   1  (classic Projects 잔존 여부 — 폐지 API 404; §7에 부기 관측 불가 5건)

integrity:             artifact 표본 13/13 PASS (size+sha256 digest 전 일치)
restore:               신선 클론 PASS — fsck 이상 0·rev-list 3992·v0.6.0 checkout·
                       LFS OID 8c744d79… + 10,076,526 B 실측 일치
discrepancies:         artifacts bytes 기준 1,133,125,505 vs 실측 702,585,144 — 원인 비관측(§5);
                       현행 repo 태그 0 (E6 이월분이 1차 clean-origin 삭제로 소멸 — 아카이브 원본 보존)

VERDICT:               ARCHIVE_CLOSED_VERIFIED
                       — 관측 표면 전수에 대해 인벤토리·disposition 완료, 원본 보존·복원 가능성
                         기계 검증됨. 처리 잔여 없음 (비노출 표면은 대상 외로 명시).
```
