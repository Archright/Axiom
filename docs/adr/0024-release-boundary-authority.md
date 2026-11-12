# ADR-0024: Release-boundary authority — tag push 발행 폐기, "검증 → publish" 단일 출하 경로

## Status

**PROPOSED (2026-09-26) — Owner 결정 #15 ratification으로 ACCEPTED 예정.** 본 ADR은 제품 출하
경계(release boundary)의 권위 모델을 고정한다: 모든 제품 Release가 가리키는 v* tag 생성 권위를
`axiom-release-authority` App에 한정하고, 그 앞에 검증(full L2)과 확인(control confirmation)을
강제한다. ADR-0017 Amendment A1.3(:139-153)의 tag-push 발화 메커니즘을 supersede하고,
`docs/spec/certification_continuity_contract.md` §10.2(:357-368)의 GitHub App minter
DEFERRED를 전제 충족으로 재개 비준한다. 표면 등록은 v16 3경로(release-ship.yml, 본 ADR,
`docs/evidence/release_boundary_protocol.md`) — 정책 PR 선행 2단으로 착지한다.

> **[SUPERSEDED-in-part 2026-09-26 — Owner 결정 #16: 릴리즈 사전 제약 폐기]**
> v\* namespace 예약과 App-only 생성 제약이 **폐기**되어 본 ADR의 "v\* tag 생성
> 권위 = release-authority App" 강제는 더 이상 적용되지 않는다 — 모든 태그는
> 개발자 milestone으로 자유롭다. 출하 도구 설계(freeze → full L2 → 확인 →
> 발행, peel provenance, FAIL/UNCERTAIN)는 **선택 도구**로만 잔존하며, 본 ADR의
> 계약 MUST 성격은 결정 #16으로 해제되었다. "태그 push → 무거운 CI 0회"는
> 유지된다.

## Context

- **Authority-first 원인**: 현행 발행 경로는 ADR-0017 A1.3의 "tag push → full L2"로, tag에
  검증을 덧씌운 의미다 — v0.5.5 태그 런(51.88 jobsMinutes)은 동일 SHA main acceptance와 완전
  중복 실측. 임의 행위자가 push할 수 있는 ref에 무거운 검증을 묶는 것은 authority boundary가
  거꾸로다.
- **플랫폼 팩트 (2026-09-26 실측)**: ① Release 객체 creator를 제한하는 native gate 없음 —
  ruleset은 tag/branch 상호작용만 보호 → "App-only publication"은 과장이며 정확한 주장은
  "v* tag 생성이 App-only" ② 기존 tag에 Release 생성 시 `target_commitish`는 unused →
  provenance는 Git object peel ③ annotated tag는 tag object+ref 2단계(`GET /git/ref`의
  `object.sha`는 tag object SHA) ④ `workflow_dispatch --ref` 변조 발화 가능 → freeze의
  `github.ref`/`github.sha` 바인딩 필수 ⑤ timeout/5xx는 "Release 없음" 추정 불가 → FAIL/UNCERTAIN
  ⑥ SHA uniqueness race → `inputs.target_sha` 기준 concurrency로 폐쇄 ⑦ 단일 `POST /releases`는
  `target == default branch tip`이면 Workflows:write 미발동(4단계보다 작을 수 있으나) v* ruleset
  통과 여부가 미문서 → Phase 3 실증 대상.
- **플랫폼 조건**: required reviewers는 Enterprise 필요 — `GET /orgs/Archright` 실측
  `plan: enterprise`. 이는 §10.2 DEFERRED의 재개 전제("플랜 상승 확정") 충족이기도 하다.

## Decision

**Ultimate Purpose (그대로):**

> 고객에게 공개되는 제품은 GitHub Release로 정의한다. 모든 제품 Release가 가리키는 v\* tag는
> release-authority App만 생성할 수 있으며, 그 tag는 exact main SHA에 대한 Full L2 PASS와
> control confirmation 이후에만 생성된다. 따라서 GitHub가 Release creator 자체를 제한하지
> 않더라도, 검증되지 않은 SHA를 가리키는 v\* tag를 인간이 새로 만들어 Release로 공개하는
> 경로는 차단한다.

권위 흐름 (authority-first):

```
wintrover(실행) → FREEZE(4중 바인딩) → FULL L2 @ FROZEN_SHA → release-authority env(확인)
  → axiom-release-authority App v* tag 생성([A] 단일 POST | [B] 4단계) → GitHub Release(peel provenance)
```

**권위 모델 (그대로):**

> Release 객체 자체의 creator는 GitHub native policy로 제한되지 않는다. Axiom이 강제하는 보안
> 경계는 **v* tag 생성 권위**다. 모든 출하 가능한 v* tag는 release-authority App만 생성할 수
> 있고, 정확한 SHA의 Full L2 PASS와 control confirmation 이후에만 생성된다. Release
> provenance는 해당 tag의 peel로 판정한다.

**권위 선언**: 실행 권위 = `authority-first-P-ship`(workflow_dispatch, allowed_actors=[User
53123826]), 확인 권위 = `release-authority` environment(required reviewer = wintrover,
prevent_self_review=false·can_admins_bypass=true [정정 2026-10-20: 종전 "admin bypass OFF(UI 확인)"
기재는 REST 실측과 불일치 — `GET /environments/release-authority`가 true를 반환한다. 따라서 이
environment는 "required reviewer 밖 행위자의 발행 차단 + L2 결과 확인 후 거부 기회 + 감사 기록"
만 보장하며, 동일 관리자의 자기 승인·우회를 막지 못한다]), 발행 경로 = `axiom-release-authority`
App(Contents:write, Axiom 핀, 키=environment 스코프 시크릿; v* tag 생성 권한, Release 객체는
native gate 없음). **미러 파일 금지** — `config/release_authority.json` 등 중복 상태 파일을
만들지 않는다.

**Owner 결정 #15 (선언):**

1. **ADR-0017 A1.3(:139-153) supersede** — tag push → full L2 발화 메커니즘과 수동 tag push
   경로(:151-153)를 폐기한다. "release 경계 = full L2 필수"라는 검증 필수성은 유지되며, 발화가
   dispatch+freeze 뒤 FROZEN_SHA에 대한 Full L2 PASS로 재배치된다. ADR-0017 :5(Status 역참조)·
   :188-197(A1.7 정합 개정 대상)을 동시 개정한다.
2. **§10.2(:357-368) 재개 비준** — GitHub App minter(우선순위 4) DEFERRED의 재개 조건
   ("플랜 상승 확정 후 별도 승인", :363)이 실측 충족(org plan: enterprise) → 본 결정으로
   재개한다. 적용 범위는 릴리스 경계의 v* tag 생성 App에 한정하며, `ax merge publish` minter는
   별도 대상으로 유지된다.
3. **플랜 결정 #1 갱신** — 실행 정책 `authority-first-P-ship`(workflow_path=release-ship.yml,
   allowed_events=[workflow_dispatch], allowed_actors=[User 53123826]) 확정, P-rpool(5564)
   `allowed_events`에 `workflow_call` 추가(신규 파일 정책 등록 선행).
4. **결정 #12(b) ratification** — #12(b)의 "RepositoryRole: Write 기반, named identity 금지"
   (repository_surface_contract.md:171-172)에 대해, release-ship 실행 정책이 단일 운영자
   (User 53123826) named identity를 사용하는 이탈을 릴리스 경계에 한정 ratification한다.
   일반 repository actor 규칙은 유지된다.
5. **DEBT#466 근거 갱신** — A1.3 폐기에 따라 미실행 격자(W1·W3–W7·W9–W11) 등재 자체는
   유지하되, "release tag full L2"의 발화 근거를 tag push → dispatch+freeze로 갱신한다.

**[3] 부정적 정의 (그대로):**

> 현재 조직은 단일 운영자이므로 environment approval은 독립적인 4-eyes review가 아니라
> **명시적 출하 확인(control confirmation)**이다. 본 게이트는 동일 principal의 자격증명으로
> API로도 재현 가능하며, 차단하는 것은 (a) required reviewer 밖 행위자의 발행, (b) L2 결과를
> 보고 거부할 기회, (c) 감사 기록뿐이다. 독립 승인 semantics는 **org에 Write-role 2인 이상
> 실재 확인 시 90일 내 전환 검토 ADR 개정 의무**를 트리거로 전환한다.

본 ADR의 자체 서술에서 이 게이트는 오직 "확인(confirmation)"으로 지칭한다 — "승인"이라는 용어는
인용문과 GitHub environment UI 메커니즘 명칭(approval) 외에는 사용하지 않는다.

**2중 유일성 메커니즘:**

- **동일 SHA** — concurrency `release-ship-${{ inputs.target_sha }}`(cancel-in-progress:
  false)로 직렬화 + freeze의 SHA uniqueness(FROZEN_SHA가 기존 Release의 어떤 tag로도 peel되지
  않음). 같은 SHA로 두 번째 version은 freeze에서 STOP.
- **동일 version** — 마지막 발행이 Git ref 생성(원자적)이므로 이미 존재하는 v* tag 생성은 422.
  서로 다른 SHA의 동시 출하도 ref 원자 충돌로 한쪽만 성립.

**FAIL / UNCERTAIN:**

- definitive(4xx) → Release 없음 확인 후 tag 삭제 → FAIL.
- ambiguous(timeout/5xx) → tag 삭제 금지·보존 → UNCERTAIN → 수동 재확인 전 출하 금지.
- 확인(pending) 전 발행 없음 — 발행은 L2 success ∧ control confirmation 이후에만.

**Provenance (peel 기준)**: `release.tag_name == version` ∧ `peel(tag) == FROZEN_SHA`.
`targetCommitish`는 기존 tag에서 unused이므로 증거로 사용하지 않는다.

**단일 POST A/B 사전 판정 (Phase 3 실험 — 채택 규칙은 실험 전 고정):**

- [A] 단일 `POST /releases`(tag_name + target_commitish=FROZEN_SHA, draft=false) — 실험 통과 시
  채택(더 작음: orphan·ref실패·human race 제거).
- [B] 4단계: ①`POST /git/tags` ②`POST /git/refs` ③peel 단언 ④`POST /releases`.
- 판정 규칙: human의 신규 v* tag 생성 시도(어느 경로든: git push / POST /git/refs /
  POST /releases)가 **BLOCK**이고(결정적 셀) 단일 POST가 App으로 성공 → **[A] 채택**. 아니면
  [B] 유지, 차단 불가 경로는 잔여 한계로 정직 기록.
- **Phase 3 A/B 실험 완료 전 "단일 출하 경로 완성/출하 경로 완결" 선언 금지** — GitHub는 Release
  객체 creator를 ruleset으로 제한하지 않으므로, 최종 판정 전까지 남은 미지수(human `POST
  /releases`의 신규 v* tag 자동 생성 차단 여부)를 미해결로 명시 유지한다. 실험 결과가 이 선언의
  유일 근거다.

**전환 트리거**: org에 Write-role 2인 이상이 실재함이 확인되면, 90일 내 독립 4-eyes 확인
(environment 기반) 전환 검토 ADR 개정 의무가 발생한다. 그때까지 본 게이트는 단일 운영자의
명시적 출하 확인이다.

**무영향 선언**: ADR-0023 Amendment A1.3("수명주기 불변식", :169-186 — 1 VM = 1 jitconfig,
ghost unregistration, external-JIT-only, warmFloor=0)은 본 결정과 무관하며 변경하지 않는다.
"A1.3" 표기 일치는 우연이며, 본 ADR이 supersede하는 것은 ADR-0017 Amendment A1.3(:139-153)뿐이다.

## Amendment G (2026-10-19) — Release version consistency gate

- **verify-metadata**: after freeze (or independently when `validation_only=true`), checkout
  `FROZEN_SHA`, run `nimble dump --json`, and require the input tag version to equal the package
  version. Mismatch, malformed JSON, or a missing version field stops the run before full-l2 and
  publish. `nimble dump --format:json` is not used: Nimble 0.22.2 prints an error for that flag but
  exits 0, so the exit code alone is not a valid failure signal.
- **verify-binary**: after full-l2, require the `ci-bootstrap-artifacts` `bin/ax` to pass
  `--check-provenance` against the `FROZEN_SHA` checkout (embedded `BuildSourceHash` == live `src/`
  tree) and require `bin/ax --version` to equal the tag version. The artifact `sha256` and
  `manifest.txt` are preserved as evidence.
- **validation_only**: `freeze` and `publish` are skipped; `verify-metadata`, `full-l2`, and
  `verify-binary` run. `validation-only-assert` fails unless `publish` is actually `skipped`.
  This is a verification path, not a release path; it cannot create a tag or Release.
- **Authority unchanged**: the App-only publish authority, `release-authority` environment
  confirmation, peel provenance, and FAIL/UNCERTAIN semantics are not modified.
- **Scope**: this gate applies to releases created by `release-ship`. It does not claim that every
  `v*` tag pushed by any actor is version-consistent. Extending the MUST to all `v*` tags requires
  a separate tag-policy decision (Owner decision #16 and the currently absent `v*` ruleset).

## Consequences

**긍정:** 검증 → 확인 → 발행 순서가 서로 다른 GitHub 장치(concurrency · Git ref 원자성 ·
peel)로 각각 강제되어, 검증되지 않은 SHA의 v* tag가 Release로 공개되는 경로가 차단된다. 임의
tag push는 무거운 워크플로 0회(실측 전/후 인과: v0.5.5 → run 36198201979). L2 성공·확인·발행
로그가 감사 기록으로 남는다.

**부정:** 단일 운영자 확인 게이트는 동일 principal 자격증명으로 API 재현 가능([3] 부정적 정의로
영구 수용). 발행 경로 세부가 GitHub 미문서 영역 실험에 의존. workflow_call 경로는 B-cache save
게이트 오프 → 콜드 L2(예산 증가, ledger 다음 round).

**리스크:** 단일 POST가 ruleset을 통과해 tag까지 생성하는지 미문서였으나 — **실험 완료
(2026-09-26)**: human의 신규 v\* tag 생성 전 경로(git push/API refs/Release 자동생성)가
전부 BLOCK, App의 단일 POST가 ALLOW → 사전 판정 규칙대로 **[A] 채택**
(`release_boundary_protocol.md` §5 실측).
UNCERTAIN 시 수동 재확인까지 출하 보류(지연). Immutable tag 재사용 불가 → 확정 실패 시에만
tag 정리 후 version bump(프로토콜).

## 잔여 한계 (Residual Limits)

- **Release 객체 creator 미제한**: 인간이 App이 만든 기존 v* tag로 Release를 수동 생성하는
  경로는 GitHub가 막지 않는다. 핵심 보장은 "검증되지 않은 SHA의 v* tag를 새로 만들어 Release로
  공개하는 경로가 차단"된다는 것에 있다 — "Release publish가 App-only로 플랫폼 강제된다"는
  과장 표현은 사용하지 않는다.
- **미문서 영역 (A/B 실험 대상)**: ① ruleset의 API 생성 ref 적용 여부 ② Release-API가 신규
  v* tag를 ruleset을 거쳐 생성하는지 ③ human `POST /releases`의 신규 v* tag 자동 생성 차단
  여부 ④ App=initiator일 때 `prevent_self_review`의 creator 계산(공식 미문서). ①~③은 Phase 3
  6칸 행렬(행위자 human/App × 연산 git push / POST /git/refs / POST /releases)로 실측해
  채택·잔여를 확정하고, 결과를 `docs/evidence/release_boundary_protocol.md`에 기록한다.
- **범위 밖 (계획서 Out of Scope)**: `config/release_authority.json` 등 미러 파일,
  release-cleanup.yml 별도 복구 경로, 글로벌 출하 lock(SHA 단위 대체), `targetCommitish` 증거
  사용, release-audit.yml, `ax release` CLI 변경, legacy 태그 정리, 두 번째 인간 신원(명시
  금지), workflow 파일 수정 차단 ruleset, AGENTS.md·config.nims·import_encapsulation_gate.nim
  (§-1 불변).

## 연쇄 갱신 문서 (본 ADR과 동시 번들 — In Scope #3)

- ADR-0017 — :5(Status 역참조) · :139-153(A1.3 supersede) · :188-197(A1.7 정합 대상)
- ADR-0019 — :27, :75 (L2/Release tag 행: tag push 발화 → dispatch+freeze)
- `docs/DEBT_REGISTRY.md:80` — DEBT#466 근거 갱신 (발화 경로)
- `docs/spec/incremental_ci_tiers_scheduling.md:48,:52,:71,:119,:131` — Release tag 발화 경로 갱신
- `docs/evidence/canonical_run_graph.md:72` — v* tag 트리거 행 제거
- `docs/agents/rules_workflow.md:211` — runner-pool 행 갱신(v* tag 발화 제거)
- `docs/spec/repository_surface_contract.md` — §Owner 결정 기록 #15 등록
- `.github/workflows/runner-pool-acceptance.yml` — :39(`tags: ['v*']`) 제거, :73(select 가드 →
  `if: !(inputs.force_full || false)`), A1.3 주석 5곳(:25,:36-37,:66,:477,:509) 정비,
  `workflow_call` + inputs 추가, checkout/identity 바인딩 유지
- 신규 — `release-ship.yml`(permissions: contents: read + App 토큰),
  `docs/evidence/release_boundary_protocol.md`

## References

- ADR-0017 [`0017-incremental-verification-engine.md`](0017-incremental-verification-engine.md)
  Amendment A1.3(:139-153)·A1.7(:188-197); ADR-0019 §1(:27)·§5(:75); ADR-0023
  (Amendment A1.3 :169-186은 무영향)
- `docs/spec/certification_continuity_contract.md` §10.2(:357-368)
- `docs/spec/repository_surface_contract.md` §Owner 결정 기록 #12(:161-181) · #15(신규)
- `docs/DEBT_REGISTRY.md:80`(DEBT#466) · `data/debt_registry.json:3819`
- 계획서: release-boundary authority 전환(white-tiger-swamp-thing-big-barda) — Ultimate
  Purpose · 권위 모델 · [3] 부정적 정의 원문 인용
- GitHub 공식 문서 — rulesets · Releases(immutable) · environment approval · App
  인스톨(실측 근거: plan: enterprise 등)

---

*작성일: 2026-09-26. Owner 결정 #15 ratification 전 PROPOSED. A/B 실험(Phase 3) 완료 전
"단일 출하 경로 완성" 선언 금지 — 실험 결과가 유일 근거.*