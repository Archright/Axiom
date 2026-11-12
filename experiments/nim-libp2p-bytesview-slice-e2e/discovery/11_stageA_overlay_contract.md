Stage A 완료. 파일2개 생성, 기존 파일 무수정, 커밋 없음.

## 생성된 파일 (커밋하지 않음, staged도 안 함)

| 파일 | sha256 | 줄 수 |
|---|---|---|
| `config/spec/nim_libp2p_bytesview_slice.json` | `6033d58661039c1fc04598f1efdb504ceb14ce2aa54b38eaf20c278a3292267b` | 61 |
| `docs/spec/nim_libp2p_bytesview_slice_contract.md` | `ab1624855c706b7e80320ac7a6adf4a4ef9789eea3ff2780c7144d0cc363c4a1` | 140 |

`git status --porcelain` (브랜치 `followup/libp2p-bytesview-slice`, HEAD `0b2564b27`):
```
?? config/spec/nim_libp2p_bytesview_slice.json
?? docs/spec/nim_libp2p_bytesview_slice_contract.md
```
`--untracked-files=all`로 확인한 결과 위2개 외 신규/수정 파일 0건. `jq .` 및 Python `json.load` 모두 strict 파싱 통과 (후행 콤마 없음). JSON 최상위 키 12개는 `toml_d2_agent_spec.json`과 동일 구조/명명.

## 반드시 인지할 차이 2건 (pinned content 대비)

1. **`subject.blobSha256` 1글자 정정** — mission 값 `…e336add8e1e9fd0e…` → 실제 측정 `…e336add0e1e9fd0e…`. worktree와 커밋된 blob 양쪽 sha256 모두 `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee` (mission의 `8`은 `0`의 오타). 커밋 SHA `a130a7f32219909bdcda14b7f1e64d0804fc832c`는 mission과 일치. **측정값을 사용했습니다** — mission이 정의한 필드 의미("sha256 of the module's bytes")와 acceptance criteria(`replay.moduleSha256 == <pin>`, pre/post 동일)가 그대로 성립하려면 실제 바이트 해시여야 합니다. mission 그대로 쓰면 subject 바이트와 불일치해 fail-closed가 됩니다.
2. **`description` 한 절 정정** — mission 원문 "for b>0 matches neither the inclusive view-relative law e-b+1 … nor a half-open law e-b"는 대수상 b=1에서 틀립니다(`e-2b+1 == e-b ⟺ b == 1`, 그리고 defect carrier가 정확히 b=1에 고정됨). mission 자신의 §2(e)도 "coincides with the half-open reading only at b=1"을 인정합니다. 해당 절만 "exactly b elements short of the inclusive law … coinciding with a half-open law e-b only at b=1 (where the template's inclusive interval is mis-derived by subtracting the start offset twice)"로 교체했습니다. **나머지 필드(carriers·semanticCaveats·nonClaims·canonicalSpecIR·provenance 등)는 전부 verbatim**입니다. 되돌리길 원하시면 알려주세요.

## 5줄 요약

1. `config/spec/nim_libp2p_bytesview_slice.json` — `SPEC-LIBP2P-BV-SLICE` / `soExplicit` / `external:libp2p/bytesview/slice-length-law` v1.0.0 오버레이: subject 핀(commit·모듈·sha256), IR 4항(`1<=e`, `e<=5`, `bvSliceLenActual(e)==e-1`, `bvSliceLenControl(e)==e+1`), constructed-IR 캐리어 2개(defect/control), caveats 6개, nonClaims 7개.
2. `docs/spec/nim_libp2p_bytesview_slice_contract.md` — toml_d2 바인딩 계약 구조/문체 모방의 8절 문서: 명제(수학)·근거 사슬(a~e)·캐리어·리플레이·제어 의미·acceptance criteria(7항)·non-claims·adoption 기록.
3. 계약 근거로 실측·인용한 것: Nim 2.2.10 `lib/system.nim:2982-2996`("inclusive", 공식 예제 `s.toOpenArray(1,3) == [1,2,3]`), `noise.nim:314/333`(msg가 `BytesView` — noise.nim:390 — 라 템플릿 직접 호출, b=0, 32바이트 `Curve25519Key` 목적지), 형제 `data` 템플릿(:21-22)의 inclusive 관용구.
4. out-of-tree 프로브(Nim 2.2.10, `/tmp/bv_probe`, subject 무수정)로 실제 관측: b=1 → 길이 `0,1,2,3,4`(=e-1, law `e` 위반), b=0 → `2,3,4,5,6`(=e+1) — 채택 모델과 일치. subject `git status --porcelain`는 프로브 후에도 clean.
5. 유일한 b>0 증인 `tests/libp2p/utils/test_bytesview.nim:14,19`는 템플릿과 **동일 커밋 `aa1c33ffe` (2025-07-07, vladopajic)** 작성분 — 독립 오라클이 아닌 동작 스냅샷으로 계약 §2(e)에 명시.

## 후속(Stage B) 주의점

- 엔진 결합은 아직 없음: `src/cli/axiom_engine.nim`는 overlay를 파일명 문자열로 로드합니다 (`"toml_d2_agent_spec.json"` :1350, `"nim_stew_base36_sidecar.json"` :1834). 신규 overlay은 현재 **inert**이며, `overlayDeclares…Subject`/합성 분기 추가가 별도 PR 대상입니다.
- `docs/spec/spec_registry.json`에 `SPEC-TOML-D2-AGENT`/`SPEC-B36-SIDECAR`가 등록돼 있지 않으므로(5개 항목만), 신규 등록은 선례상 필수가 아닙니다. 등록하려면 기존 파일 수정이 필요해 본 스테이지 금지 범위 밖입니다.
- subject tree는 READ-ONLY 유지(검증 완료), `/tmp/bv_probe` 산출물은 저장소 밖에 있습니다.