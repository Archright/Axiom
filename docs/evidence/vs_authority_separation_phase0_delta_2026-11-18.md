# VS-AUTHORITY-SEPARATION — Phase 0 Authority Fact Freeze (delta, 2026-11-18)

> 범위: `vs/authority-separation` 브랜치의 착수 시점 권한·원장·배포 실측 delta.
> 상위 Phase 0 기록은 `docs/evidence/free_authority_migration_phase0_proof.md`이며,
> 본 문서는 그 이후(Free 전환 착지 후) 관측된 **현재 값**만 추가한다. 중복 서술하지 않는다.
> 기록자 ≠ 승인자: 작성자는 agent, 승인자는 사용자(wintrover)다.

## §1. 기준점

| 항목 | 실측값 | 명령 |
|---|---|---|
| canonical main | `edf811f3199eb327da18dbab25a53639d98e3a81` (2026-11-18T03:17:05Z, PR #164) | `git log -1 origin/main` |
| 작업 브랜치 | `vs/authority-separation` = main (0 ahead / 0 behind), clean | `git rev-list --left-right --count origin/main...HEAD` |
| 저장소 가시성 | `PUBLIC`, default `main` | `gh repo view Archright/Axiom --json visibility,defaultBranchRef` |
| branch protection API | `404 Branch not protected` — 보호는 **ruleset 전용** | `gh api repos/Archright/Axiom/branches/main/protection` |
| default workflow permissions | `read` | `gh api repos/Archright/Axiom/actions/permissions/workflow` |
| repo secrets | `0` | `gh api repos/Archright/Axiom/actions/secrets` |

## §2. Ruleset readback (live)

| id | name | enforcement | 조건 | 규칙 |
|---|---|---|---|---|
| `27097366` | main | active | `refs/heads/main` | required checks 7 + merge queue |
| `27466866` | ledger-no-destroy | active | `refs/heads/axiom/{certificates,evidence-cas,attestations}` | `deletion`, `non_fast_forward`; bypass `[]` |
| `27097369` | cas-probe-scratch | active | `refs/heads/cas-probe/*` | update/deletion/non-FF |
| `27097391` | artifact-hygiene | disabled | — | — |
| `27097390` | execution-surface-create | disabled | — | — |

`27097366` required checks (context → integration_id):

- `admission-check` → **5795152** (App `axiom-admission-verifier`)
- `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice`, `publication-integrity`, `readiness-verdict` → `15368` (GitHub Actions)

`27097366` merge queue: `grouping_strategy=ALLGREEN`, `merge_method=MERGE`, `max_entries_to_build=2`, `max_entries_to_merge=1`, `min_entries_to_merge=1`, `min_entries_to_merge_wait_minutes=0`, `check_response_timeout_minutes=120`. `bypass_actors=[]`.

## §3. 원장 side-ref (live, 계속 증가 중)

| ref | tip | entries |
|---|---|---|
| `origin/axiom/certificates` | `7b1b4771474c4d18b832b2433e1f8d73d33ff618` | **125** |
| `origin/axiom/evidence-cas` | `9f1793a2031fa418015502a7c2647af685860f8e` | **541** |
| `origin/axiom/attestations` | `f16bd508efda2f48c985d01c6a4f47fdc333784e` | (미집계) |

직전 5개 ledger commit의 diff shape는 모두 **정확히 1개 추가**다:

```
7b1b4771  A  d4193fb1….json
41959807  A  0ed438ba….json
f252a7af  A  8800773b….json
329bbf19  A  69385e9f….json
52606f3d  A  b65d4f1e….json
```

## §4. subject/append 모델 (코드 정본)

- `subjectId = sha256("axiom.subject.v2\n" + baseSha + \x1f + headSha + \x1f + headTreeDigest + \x1f + policyDigest + \x1f + scopeDigest + \x1f + evidenceDigest)` — `src/verification/verification_subject.nim:120-132`.
- `evidenceDigest = sha256(canonicalJson({funcSource, funcName, leanSource, smtlib2, toolchainIdentity, llbcDigest, rustToolchainIdentity}))` — `src/verification/attestation_orchestrator.nim:241-260`. **시각·run_id·attempt가 입력에 없다.**
- entry 파일명 = `subjectId`; 그러나 `sha256(bytes) != filename` (125/125 불일치 — identity-addressed, content-addressed 아님).
- `appendCertificate`: blob → `base_tree=tip` tree 1경로 → commit(parent=tip) → `PATCH {force:false}` (`src/verification/ledger_side_ref.nim:433-473, 588-595`). 중복 검사는 **재시도(attempt>1)에만** 존재(`:575-582`); 첫 시도는 존재 검사를 하지 않는다.
- 결과: 같은 subjectId에 **다른 바이트**를 첫 시도로 append하면 `<subjectId>.json`을 **덮어쓴다**. deletion/NFF ruleset은 fast-forward 콘텐츠 변조를 막지 못한다. D6 idempotency는 workflow(`certificate-mint.yml:2263-2279`)에 있고 `appendCertificate`에는 없다.

## §5. 인증서 attestation (권위 아님)

- seed: `"axiom-attestation-v1-sha256"` (공개 literal) → `createKeypair(sha256(seed))` — `src/infrastructure/certificate_attestation.nim:184-187, 222-226`.
- 공개키 literal `7e37ae83…`, `publicKeyId = "sha256:" + sha256(pubkeyHex) = sha256:9a17da48…` — `:192-198`.
- verifier는 attestation 블록 부재 시 **ok(legacy)** — `:266-268`; `src/verification/certificate_verifier.nim:255-265` 동일.
- 판정: 서명은 직렬화·전송 무결성/손상 탐지 앵커다. **authenticity·authorization·non-repudiation 신호가 아니다** (`docs/design/debt464_mint_authority_design_2026-09-18.md:416-433`).

## §6. Freeze 시점 in-flight merge_group

```
44230229467  G=53a64c6f81a6ad6f92423bdc71a1cec6b9d21b20  03:24:44Z  publication-integrity
44230229569  G=53a64c6f81a6ad6f92423bdc71a1cec6b9d21b20  03:24:44Z  axiom-operational-slice
44230229739  G=53a64c6f81a6ad6f92423bdc71a1cec6b9d21b20  03:24:44Z  admission-gate
```

**queue freeze는 위 run의 종료 관측 후에만 유효하다.**

## §7. 마지막 관측 완료 run (판정 → 원장 순서)

`44222364199` (event `merge_group`, workflow_id `420946486`, attempt 1):

- G=`223339b873e66d40f76663a790b5b4a5020121de`, created 02:19:12Z, updated 02:27:20Z, conclusion `success`.
- 동일 G에 App check start 02:19:12Z → completed 02:27:25Z `success`, external_id `v1|…|G|base|ledgerBase`.
- mint-publish 02:25:11Z → 02:27:12Z; ledger commit `329bbf19` 02:26:46Z (parent `52606f3d`).
- **원장 쓰기가 App 판정 완료보다 먼저 일어난다** — 현재 순서는 `ledger append → admission-check`이고, 목표 순서는 `검증 → 판정 → append → success`다.

## §8. Worker(검증자) 정체성 — 현재 기록 불가

| 항목 | 실측 |
|---|---|
| 소스 위치 | `~/.config/axiom-verifier-app/worker/src/index.js` — **git 저장소 아님**, repo 밖 |
| 소스 sha256 | `d613896c6a6a2d1255b804280f245ae32c763126d9e35e41c6d2a79338ddee57` |
| 배포 version id | repo에 기록 없음 (wrangler versions/deployments에만 존재) |
| `wrangler.toml` | name `axiom-admission-verifier`, main `src/index.js`, workers_dev true |
| judge 로직 | `checkTrustSurface(g, base)` = manifest 17경로 blob 동등성 (`index.js:310-338`); `checkLedger` = baseline 이후 added entry에서 `baseSha===base && (headSha===prHead||g)` (`:341-364`) |

## §9. 배포 승인 표면

| environment | protection |
|---|---|
| `release-authority` | required_reviewers `[wintrover]`, **`prevent_self_review=false`** |
| `diagnostic-authority` | 없음 |

Cloudflare에는 deployment approval 기능이 없다(공식 문서 부재 확인). `Workers Scripts:Edit`은 full CRUDL이며 upload-only/deploy-only 권한이 없다. 따라서 승인 게이트는 **GitHub environment required reviewers**뿐이고, 현재 설정은 단일 인간이 initiator이자 approver가 될 수 있다.

## §10. 미해결 DEBT (open)

| id | 상태 | 핵심 |
|---|---|---|
| DEBT#555 | open | `appendCertificate`가 attestation을 검증하지 않고 append → 변조 인증서 영구 기록 가능 |
| DEBT#557 | open | `verify_trusted_writer_set.sh`가 top-level만 파싱 → job-level `contents: write` 6+2+1건 미관측 |
| DEBT#558 | open | trust-surface 17경로에 rotation pin 포함 → 모든 소스 PR이 재앵커를 강제당하고 App이 거부. **현재 소스 PR 착지 불가** |

`#151` (head `666d1d72`, base `a2286003`)은 `MERGEABLE`/`BLOCKED`이며 App summary는
`trust_surface=FAIL — mismatch:config/trusted_writer_set.json`이다.

## §11. 명시적 비주장 (이 slice가 보장하지 않는 것)

- Fork PR admission: 미지원(fail-closed). merge queue + fork 조합은 GitHub 문서에 **미기재(UNKNOWN)**.
- Release tag immutability: **미성립**. tag ruleset은 별도 slice다.
- Cloudflare 배포 2인 승인: **미성립** (`prevent_self_review=false`, reviewer 1명).
- 원장 append-only: **미성립** (§4의 덮어쓰기 경로).
- App이 원장 writer라는 주장: **미성립**. 현재 writer는 `github-actions[bot]`이다.

## §12. 재현 명령

```bash
git fetch -q origin main axiom/certificates axiom/evidence-cas axiom/attestations
git log -1 origin/main --format='%H %cI %s'
git rev-list --left-right --count origin/main...HEAD
gh api repos/Archright/Axiom/rulesets --jq '.[]|"\(.id)\t\(.name)\t\(.target)\t\(.enforcement)"'
gh api repos/Archright/Axiom/rulesets/27097366 --jq '{bypass:.bypass_actors,checks:[.rules[]|select(.type=="required_status_checks")|.parameters.required_status_checks[]|{context,integration_id}]}'
gh api repos/Archright/Axiom/rulesets/27466866 --jq '{bypass:.bypass_actors,refs:[.conditions.ref_name.include],rules:[.rules[].type]}'
git ls-tree -r --name-only origin/axiom/certificates | wc -l
gh api 'repos/Archright/Axiom/actions/runs?event=merge_group&status=in_progress'
gh api repos/Archright/Axiom/environments --jq '.environments[]|"\(.name)\t\(.protection_rules|tostring)"'
sha256sum ~/.config/axiom-verifier-app/worker/src/index.js
```