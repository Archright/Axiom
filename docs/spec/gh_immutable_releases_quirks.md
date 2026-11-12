# GitHub Immutable Releases — Draft-Publish 절차 Quirks (release-ship axiom-cli 발행 계약)

> AGENTS.md §0.5 Quirk Mandate — documented toolchain quirks live in
> `docs/spec/` (AGENTS.md 본문은 FROZEN — §-1; 본 문서가 그 전문이다).
>
> **Discovered**: 2026-11-10 (release-ship publish 잡의 axiom-cli 자산
> 업로드 422 실패 — run 42554460237 — 근본 수복
> `workstream/release-ship-cli-immutable-draft`).
> **Class**: external platform behavior — GitHub immutable releases 기능의
> 자산 차단 범위와 draft→publish 전환 계약. 인접 문서:
> `docs/spec/gh_api_paginate_output_quirks.md` (동일 워크플로 freeze ⑥의
> gh 출력 형태 quirk), `docs/spec/productization_contract.md` §1b (배포
> 자산 계약).
>
> Tagging: **[measured]** = observed live on the cited command/tool version.
> **[documented]** = quoted from official GitHub documentation (REST API
> reference / GitHub Docs / GitHub changelog — 인용은 아래 각 항목).
> Scratch 검증 저장소 `wintrover/immutable-draft-flow-verify`(private,
> immutable-releases ON)에서 전 시퀀스 실측했다 — 본문의 "실측(스크래치)"
> 표기는 이 저장소를 가리킨다.

---

## Q-G1 — immutable releases가 활성된 저장소에서는 발행(published) 즉시 자산 추가가 차단된다: 단일 POST(발행) → `gh release upload`는 HTTP 422 "Cannot upload assets to an immutable release"로 실패한다

### Symptom

release-ship publish 잡의 §1b 단계(수정 전)는 axiom-cli에 release를
`draft=false`로 생성(단일 POST — 태그 자동 생성)한 뒤 `gh release upload`로
자산 4종을 올렸다. run 42554460237(2026-11-09, v0.6.0)에서:

```
AXIOM_CLI_PUBLISH: ① OK — no existing release/tag v0.6.0 on Archright/axiom-cli
AXIOM_CLI_PUBLISH: ② OK — release v0.6.0 created
HTTP 422: Cannot upload assets to an immutable release. (https://uploads.github.com/repos/Archright/axiom-cli/releases/439862479/assets?label=&name=attestation-bundle.jsonl)
##[error]AXIOM_CLI_PUBLISH: FAIL — ③ asset upload failed (release exists — 수동 조정 필요, 자동 삭제 없음)
```

Axiom 저장소 측 PATH A 발행은 성공했다(PUBLISH_RESULT=success, peel 단언
통과) — 차이는 저장소 설정이다. **[measured]**:

- `GET /repos/Archright/axiom-cli/immutable-releases` →
  `{"enabled":true,"enforced_by_owner":false}` (repo 단위 활성)
- `GET /repos/Archright/Axiom/immutable-releases` →
  `{"enabled":false,"enforced_by_owner":false}`

관리자(wintrover) 토큰으로도 자산 업로드가 동일 422로 차단됨 — 권한
문제가 아니라 정책 차단이다.

### Documented / measured basis

- **[documented]** GitHub Docs — Immutable releases
  (<https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases>):
  - "Release assets cannot be modified or deleted: All files attached to
    the release (such as binaries and archives) are protected from
    modification or deletion."
  - "Git tags cannot be moved: Once an immutable release is published, its
    associated Git tag is locked to a specific commit, cannot be changed,
    and cannot be deleted while the release exists."
  - "Only the assets and tag are locked. You can still edit the title and
    release notes of a published immutable release…"
- **[documented]** GitHub changelog — Immutable releases GA
  (<https://github.blog/changelog/immutable-releases-are-now-generally-available/>):
  "Once enabled: All new releases are immutable (i.e., assets are locked
  and tags are protected)." — POST /releases에 `immutable` 입력
  파라미터는 존재하지 않는다(응답 전용 필드). REST reference
  "Create a release"의 body 파라미터 목록에 `immutable` 없음
  (<https://docs.github.com/en/rest/releases/releases#create-a-release>).
- **[measured]** 업로드 차단은 422로 재현된다(스크래치: 발행된 immutable
  release에 `gh release upload` → `HTTP 422: Cannot upload assets to an
  immutable release.` — run 42554460237과 동일 문구·URL 형태).

### Resolution

발행 절차를 GitHub 공식 권장 3단계로 전환한다(release-ship publish 잡의
axiom-cli §1b 단계): ① 부재 단언(published release/git tag/pending draft
전부) → ② draft 생성 → ③ 자산 업로드(draft에 허용) → ④ 바이트 readback
(draft 상태) → ⑤ PATCH draft=false 발행. 공식 권장 문구: **[documented]**
"Best practices for publishing immutable releases — We recommend you use
the following workflow for publishing an immutable release. 1. Create the
release as a draft. 2. Attach all associated assets to the draft release.
3. Publish the draft release. This ensures that all assets are in place
before the release becomes immutable, preventing the need to work around
immutability restrictions."

---

## Q-G2 — draft release에는 자산 업로드가 허용된다; `gh release upload`는 pending tag name으로 draft를 해석한다

### Behavior

- **[documented]** GitHub Docs — Managing releases in a repository
  (<https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository>):
  draft를 먼저 만들고 자산을 모두 첨부한 뒤 발행하라는 권장(Q-G1 인용)은
  draft에 자산 첨부가 가능함을 전제한다.
- **[measured]** `gh release upload TAG files…`(gh 2.102.0)가 draft
  release에 성공한다(스크래치: draft v0.9.9에 4자산 업로드 성공). gh의
  `FetchRelease`(pkg/cmd/release/shared/fetch.go, v2.102.0)은 REST
  `/releases/tags/{tag}`(published 전용)와 GraphQL
  `repository.release(tagName:)`(draft의 pending tag)을 병행 조회해
  어느 쪽이든 먼저 발견된 release를 반환한다 — "FetchRelease finds a
  published repository release by its tagName, or a draft release by its
  pending tag name." 이 병행 조회는 gh ≥ 2.60에 존재한다(v2.60.0 소스
  실측 확인 — GitHub-hosted 러너 gh 버전 대역에서 유효).
- **[measured]** REST `GET /releases/tags/{tag}`는 draft를 반환하지
  않는다(스크래치: draft 상태에서 404, 발행 후 200). **[documented]**
  REST reference는 이 엔드포인트를 "Get a published release with the
  specified tag"로 기술한다 — draft readback은 release id
  (`GET /releases/{id}`)로 수행해야 한다.
- **[measured]** draft의 자산도 `GET /releases/assets/{id}` + `Accept:
  application/octet-stream`으로 바이트 재취득·재해시 검증이 가능하다
  (스크래치: 4자산 전부 로컬 sha256과 일치).

---

## Q-G3 — PATCH /releases/{id} draft=false가 발행이며, 태그는 이 시점에 target_commitish에서 자동 생성된다

### Behavior

- **[documented]** REST reference — Update a release
  (<https://docs.github.com/en/rest/releases/releases#update-a-release>)
  의 body 파라미터 `draft`: "true makes the release a draft, and false
  publishes the release." Create의 `draft`는 "true to create a draft
  (unpublished) release, false to create a published one. Default:
  `false`" — `target_commitish`는 "Unused if the Git tag already
  exists. Default: the repository's default branch."
- **[measured]** draft 생성 시점에는 태그가 존재하지 않는다(스크래치:
  `GET /git/ref/tags/v0.9.9` → 404). PATCH draft=false 응답은
  `draft:false`, `immutable:true`, `published_at` 세팅. 발행 직후 태그가
  자동 생성돼 있다(lightweight — `object.type == "commit"`).
- **[measured]** 태그 대상 결정론: draft 생성 시 `target_commitish`에
  커밋 SHA를 명시하면(핀) main이 이후 전진해도 발행 시점의 태그는 핀된
  SHA에 생성된다(스크래치: T1 핀 → main을 T2로 전진 → 발행 → 태그 =
  T1). 핀하지 않으면 발행 시점의 default branch tip에 생성된다(첫
  실측: target_commitish="main" → 발행 태그 = 당시 main tip).
- **[measured]** 발행 후 자산 바이트는 불변으로 유지된다(스크래치:
  발행 전후 자산 sha256 동일).

### Resolution (release-ship 적용)

②에서 `GET /git/ref/heads/main`으로 axiom-cli main tip을 캡처해
`target_commitish`로 핀하고, ⑤ 발행 후 태그가 핀된 SHA에 존재함을
단언한다 — 업로드/검증 사이 axiom-cli main 전진과 무관하게 태그 대상이
결정론적으로 유지된다.

---

## Q-G4 — POST /releases는 동일 tag_name의 중복 생성을 거부하지 않는다: 유일성은 소비자(발행 경로)의 부재 단언이 담당한다

### Behavior

- **[measured]** 동일 tag_name으로 두 번째 draft 생성이 성공한다
  (스크래치: published immutable release v0.9.9가 존재하는 상태에서 같은
  tag_name의 추가 draft POST → 201, 별도 id 발급). 즉 POST는 유일성
  게이트가 아니다.
- **[measured]** REST `GET /releases` 목록은 draft를 포함하지만("Only
  users with push access will receive listings for draft releases" —
  **[documented]** List releases) draft 생성 직후에는 빈 목록을 반환했다가
  수십 초 내에 반영되는 eventual-consistency 지연이 관측됐다(스크래치:
  생성 직후 length 0 → 재조회 length 1). 즉시·정확한 pending-draft 조회는
  GraphQL `repository.release(tagName:)`이다(gh FetchRelease가 쓰는 경로
  — 생성 직후에도 즉시 해석됨, 실측).

### Resolution (release-ship 적용)

① 부재 단언은 세 조회로 구성한다: REST `/releases/tags/{tag}`(published)
404 + REST `/git/ref/tags/{tag}`(git tag) 404 + GraphQL
`release(tagName:)` null. 잔여 draft가 있으면 이전 실패 run의 부분
상태이므로 fail-closed FAIL(수동 조정) — POST의 중복 허용(Q-G4)을
이 단언이 닫는다. 불명확 응답(5xx/네트워크/GraphQL errors)도 전부 FAIL.

---

## Q-G5 — repo 단위 immutable-releases 설정의 확인·변경 API는 존재한다(운영자 전용 — 워크플로는 소비하지 않는다)

- **[documented]** REST reference — Repos
  (<https://docs.github.com/en/rest/repos/repos>):
  - `GET /repos/{owner}/{repo}/immutable-releases` — "Shows whether
    immutable releases are enabled or disabled. Also identifies whether
    immutability is being enforced by the repository owner. The
    authenticated user must have admin read access to the repository."
    응답 `{enabled, enforced_by_owner}`; 미활성 시 404.
  - `PUT /repos/{owner}/{repo}/immutable-releases`(활성, admin, 204/409),
    `DELETE …`(비활성, admin) 및 org 정책 엔드포인트군
    (`PUT /orgs/{org}/settings/immutable-releases/repositories…`)이
    함께 문서화돼 있다.
- **[measured]** `GET` 실측값은 Q-G1 참조(axiom-cli enabled:true /
  Axiom enabled:false — 2026-11-10).
- release-ship 워크플로는 이 설정을 **소비만** 한다(활성 상태를 전제로
  draft 절차를 수행하고 ⑤에서 `immutable:true`를 단언). 설정 변경은
  운영자 판단 대상이며 이 저장소의 발행 경로가 수행하지 않는다.
