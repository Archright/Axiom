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
```## §13. Live drift observed during Phase 0 (2026-11-18, after §1–§12)

§1–§12는 freeze 시점의 스냅샷이다. 같은 날 후속 실측에서 다음이 관측됐다.

| ref | freeze 시점 | live (관측 시점) | delta |
|---|---|---|---|
| `axiom/certificates` | `7b1b4771…`, 125 | `005ca1f20ebf47c95b28ccb2f23cc518bf6e25b5`, **126** | +1 (`4d20ff6b…json`) |
| `axiom/evidence-cas` | `9f1793a2…`, 541 | `cf1512956ffc45939894d23096b456875241211d`, **542** | +1 |
| `axiom/attestations` | `f16bd508…` | `f16bd508…` | 0 |

- 새 certificate `4d20ff6b788b2c48cd6ec2cdf1f877c1a9af58ae15e114abf8e24c5fbc6570c2.json`
  (blob `82fb6f97…`)의 subjectId 재유도와 Ed25519 검증은 통과한다.
- **로컬 fetch는 live보다 1 append 뒤진다.** 모든 원장 스캔은 `git fetch origin axiom/certificates`
  이후에 수행해야 하며, N은 고정값이 아니다.

### `bin/ax` SourceCoherence 실측 FAIL (하드 블로커)

```
[FATAL] Engine source/source mismatch (SourceCoherence FAIL)
  binary=bin/ax tree=vs1-tree-hash/1:-3557499504198086533
  embedded=vs1-tree-hash/1:6647716839626536744
EXIT=1
```

`src/*.nim` 8개가 바이너리보다 최신이며, `src/generated/build_env.nim`은 빌드 시 재생성되는
비추적 파일이다. 이 상태에서 `ax cert ...`는 dispatch 전에 exit 1이므로 **원장 검증 전에 재빌드가 필수**다.
재빌드는 `make build`를 쓴다 — `make ci-bootstrap`은 `bin/ax`를 symlink로 바꿔 SourceCoherence를
건너뛰는 Trap 3 경로다.

### DEBT#555 의미 한계

`ledger-verify`는 파일과 원장 entry의 `subjectId/baseSha/headSha/certTree`/서명을 비교한다.
원장에서 export한 파일을 검증하면 **내부 일관성**만 증명되며 provenance 증명이 아니다.
`ax cert verify`는 journal 교집합 0으로 전부 `JOURNAL_REQUIRED`다. 따라서 DEBT#555 종결 문구는
"N/N internal consistency at tip T"로 한정한다. `certTree`(68/125는 base가 ancestor 아님)와
`evidence-cas` 542건은 residual/out-of-scope로 명시한다.

## §14. `bin/ax` 재빌드 + 원장 126/126 내부 일관성 스캔 (2026-11-18T03:40Z–03:44Z)

### 재빌드 (블로커 해소)

```bash
make build            # nim c --hints:off -d:allowMissingZ3 -o:bin/ax src/cli/main.nim
./bin/ax --check-provenance
```

관측:

```
AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (vs1-tree-hash/1:-3557499504198086533)
EXIT=0
```

직전 FAIL 값(`embedded=vs1-tree-hash/1:6647716839626536744`)은 더 이상 존재하지 않는다.
`bin/ax`는 regular file(`-rwxrwxr-x`, 28,733,880 bytes)이며 symlink가 아니다.

### 원장 스캔

```bash
export GITHUB_TOKEN="$(gh auth token)"
git fetch -q origin axiom/certificates
mkdir -p /tmp/ledger-certs && git archive origin/axiom/certificates | tar -x -C /tmp/ledger-certs
for f in /tmp/ledger-certs/*.json; do ./bin/ax cert ledger-verify "$f" >/dev/null || echo "FAIL $f"; done
```

관측:

| 항목 | 값 |
|---|---|
| ref | `axiom/certificates` |
| tip | `005ca1f20ebf47c95b28ccb2f23cc518bf6e25b5` |
| 파일 수 | 126 |
| PASS | **126** |
| FAIL | **0** |
| 소요 | ~190s (파일당 4회 Git Data API GET, 총 ~504 GET) |
| 결과 파일 | `/tmp/ledger-verify-20261118T034041Z.tsv` |

개별 성공 형태: `[cert] Ledger verify: OK — record for subjectId <16-hex> consistent
(D6 (A) HOLDS — reconciliation PASS, append count 0)`.

### 이 스캔이 증명하는 것 / 증명하지 않는 것

- 증명: 각 파일의 `subjectId` 재유도, `baseSha/headSha/certTree`의 원장 entry 일치,
  entry 부재/불일치 없음(D6 reconciliation append count 0). **tip `005ca1f2`에서 126/126.**
- 증명하지 않음: provenance(그 코드가 실제로 그 커밋에서 실행되었다는 사실), `certTree`의
  git object 재계산(현재 어떤 CLI도 하지 않음), `evidence-cas` 542건의 동등 검증.
- 따라서 DEBT#555의 종결 문구는 **"126/126 internal consistency at tip `005ca1f2`"**로 한정한다.
- 스캔 중 원장이 전진하면 결과는 tip에 결속되지 않는다. 재현 시 `git fetch` 후 tip을 다시 기록해야 한다.

### `(base, head)`는 유일키가 아니다 — `subjectId`가 유일키다

126건 중 `headSha=a2228604dbc78978bad1bbf9a22f01a11bb7bf5a`가 **2건**이다.

```
subj=7cd0c36cc0686c4a base=a2286003eaf0 head=a2228604dbc7 kind=subject-continuity
subj=eef79163fcc25bde base=983e8360f876 head=a2228604dbc7 kind=subject-continuity
```

동일 head에 대해 base가 전진했기 때문이며, 이는 base-move 계약이 실제로 발생함을 보여주는
실측 증거다. 원장의 항목 이름은 `subjectId`(6필드 해시)이고 `(base, head)`는 lookup index일 뿐이므로,
멱등성 키를 `(base, head)`로 고정하면 서로 다른 정당한 subject를 하나로 collapse한다.

### evidence-cas의 신뢰 위치 (계약 확정용 실측)

- CAS 경로는 `<evidenceKey>.json`이고 **파일명은 content hash가 아니다**(실측: 4건 중 3건 불일치).
- 레코드는 `{evidenceKey, payload, payloadSha256, evidenceDigest, verifierArtifactDigests, storedAtUtc}`이며
  `payloadSha256 == sha256(payload)`를 검증기가 재계산한다(`src/verification/evidence_ledger.nim:168-178`).
- `evidenceDigest`는 producer가 전달하는 **binding digest**이며 payload에서 재유도되지 않는다.
- 따라서 CAS는 그 자체로 판정 권위가 아니다. 판정 권위는 `certificates`(App-only writer 예정)이고,
  CAS는 "증거 생산물 저장소"다. App이 CAS를 소비할 경우 `payloadSha256` 재계산 +
  `certificate.evidenceDigest == record.evidenceDigest` + `entry name == evidenceKey`를 확인해야 한다.
  이 계약을 지키는 한, Actions의 CAS write는 PR이 스스로 합격을 만드는 경로가 아니다.
## §15. Worker v2 배포 기록 (2026-11-18T03:51Z)

### 이전 / 이후

| 항목 | 값 |
|---|---|
| 이전 버전 | `3ee49b00-4bcf-4dad-b4c5-fab87fe3f572` (2026-11-17T23:46:28Z) |
| 이전 소스 sha256 | `d613896c6a6a2d1255b804280f245ae32c763126d9e35e41c6d2a79338ddee57` |
| 신규 버전 | `5050d518-0464-44e5-b3a2-199ccc5dafc5` |
| 신규 소스 sha256 | `4f393d946c784488282e635b62a03e21180ae786dc8c2a900a63441da68376d8` |
| 배포 명령 | `npx wrangler@latest deploy` (`~/.config/axiom-verifier-app/worker`) |
| `/health` rev | `2026-11-18.3-jsonc-field-aware-venue` |
| 롤백 명령 | `npx wrangler@latest rollback 3ee49b00-4bcf-4dad-b4c5-fab87fe3f572` |

### 로컬 회귀 (배포 전)

`node test/run.mjs` → **PASS 24/24**. 포함된 계약:
- JSONC(`//`, `/* */`, trailing comma) 파싱, 깨진 JSON/중복 key는 null(fail-closed)
- TWS: closure sha가 subject tree blob과 일치할 때만 수용, 불일치/보호 필드 변경/신규 필드/누락/타입 변경 거부
- PR venue: 3-dot touched-path, merge-base를 diff base로 사용( stale `pr.base.sha` 미사용 ), 300-file/페이지 상한 초과 시 fail-closed
- merge_group: 비-TWS 16경로 byte-equal 유지 + TWS는 G tree에 결속된 field-aware
- merge-base 부재, tree truncated, compare diverged → fail-closed

### 배포 후 관측

```
GET https://axiom-admission-verifier.wintrover.workers.dev/health
{"ok":true,"check":"admission-check","workflow":".github/workflows/admission-gate-v2.yml",
 "mode":"base-anchored","rev":"2026-11-18.3-jsonc-field-aware-venue","app_id":"5795152"}
```

### 수용 시험

`#151` head `666d1d72`의 `admission-gate` run `44211806914`을 attempt 2로 rerun.
기대: App `admission-check` = success (field-aware가 closure re-anchor 1건을 수용).

### 수용 시험 1 — App field-aware PASS, 그러나 mint A0 guard FAIL

run `44211806914` attempt 2 (head `666d1d72`, run 시점 main `53a64c6f`)의 관측:

```
App admission-check (5795152):
  trust_surface=PASS — venue=pull_request manifest_ref=53a64c6 touched=4
                       manifest_touched=1 closure_reanchored=1 reasons=none
  reasons=conclusion=failure
  → App 판정 실패 사유는 워크플로 자체의 conclusion=failure 하나뿐이다.
```

즉 **DEBT#558의 교착은 실제로 해소됐다**. 실패는 App이 아니라 다음 job에서 발생했다.

```
mint-prepare / prepare:
  MINT_A0_ACTIVATION: FAIL — PR #151 base.sha 'a2286003eaf0' != baseSha input '53a64c6f81a6' (fail-closed)
```

### 새로 발견한 in-repo base-move 결함 (MUST 후보)

`admission-gate-v2.yml:236`은 `BASE_SHA = needs.anchor-resolve.outputs.B_STAR || github.event.pull_request.base.sha`다.
`anchor-resolve`는 **현재 main tip**(`53a64c6f`)을 B*로 해석한다. 반면 mint의 A0 guard는
`GET /pulls/151`의 `base.sha`(`a2286003`, PR이 마지막으로 갱신될 때의 base)와 **문자열 동일**을 요구한다.

- 두 계약이 서로 다른 시점의 base를 가리키므로, **main이 전진한 뒤에는 어떤 PR도 mint될 수 없다**.
- 이는 사용자가 지적한 base-move 문제의 in-repo 판본이며, "PR branch update 강제" 정책을
  사실상 강제하는 구조다. 즉 merge-aware anchoring(B*)을 도입했지만 A0 guard가 따라오지 않았다.
- 단기 회피는 branch update(merge main → base.sha 갱신)이고, 근본 수정은 A0 guard를
  `PR.base.sha ∈ ancestors(B*)` + `B* ∈ main`으로 바꾸는 **trust-surface 변경**이다.
  후자는 `certificate-mint.yml`(manifest 17경로) 수정이므로 별도 계획·승인이 필요하다.

### 수용 시험 2 — branch update 후

`#151` head를 `2e17d9a`로 갱신(origin/main `53a64c6f` 병합). 병합 트리에서
TWS `trustedCheckerTreeClosure` **890개 전부**가 해당 경로의 blob SHA와 일치(`bad=0`)함을 확인.
`PR.base.sha == B_STAR == 53a64c6f`가 성립하므로 A0 guard가 통과 가능하다.

### 수용 시험 3 — merge queue를 통한 실제 착지 (DEBT#558 종결)

`#151`을 `gh pr merge --merge`로 enqueue한 뒤 관측한 전체 사슬이다.

| 단계 | 관측값 |
|---|---|
| merge group | `G=9c8f172fee43a78f11801f84a7afc66f1658f09b` |
| base (G.parent[0]) | `53a64c6f81a6ad6f92423bdc71a1cec6b9d21b20` |
| PR head (G.parent[1]) | `2e17d9a5ac6086f6ebadfc275ea632fc3c5abce3` |
| merge_group gate run | `44236148853` attempt 1, **conclusion=success** |
| App trust_surface | **PASS** — `venue=merge_group manifest_ref=53a64c6 touched=17 closure_reanchored=1 reasons=none` |
| App ledger | **PASS** — `1 entry bound to (base, pr_head)`, baseline `005ca1f2` |
| App check on G | `admission-check` @5795152 **success** |
| GitHub merge | **MERGED** at `2026-11-18T04:24:59Z`, merge commit = `9c8f172f…` = G |
| canonical main | `9c8f172f…` |
| ledger | `005ca1f2…` → `2bff7b9e…`, **126 → 127 entries**, 추가 파일 정확히 1개 |
| 신규 entry | `69bc646a…json`, `kind=subject-continuity`, `base=53a64c6f…`, `head=2e17d9a…` |
| 신규 entry 검증 | `ax cert ledger-verify` → `OK — record for subjectId 69bc646a… consistent (D6 (A) HOLDS, append count 0)` |
| main의 TWS | `trustedCheckerTreeClosure` **890/890** blob 일치, `ledger_side_ref.nim` = `3d356878…` |

이로써 다음이 **실제 운영에서** 성립한다.

1. TWS closure re-anchor를 포함한 PR이 App의 field-aware 판정을 통과했다.
2. merge_group venue에서도 동일한 계약이 적용되어 `closure_reanchored=1`이 수용됐다.
3. App이 merge candidate G에 대해 독립적으로 ledger entry를 확인하고 success를 발행했다.
4. GitHub가 App success 없이는 병합하지 않았고, 실제 MERGE가 일어났다.
5. 원장은 정확히 1개 entry만 증가했고, 그 entry는 검증 가능하다.

**DEBT#558의 교착은 종결됐다.** 남은 것은 이 slice의 다른 축(단일 writer, Rule A, negative control)이다.
