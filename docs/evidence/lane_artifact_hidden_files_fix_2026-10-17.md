# Lane 아티팩트 히든 파일 필터 수정 — upload-artifact v4 `include-hidden-files` (2026-10-17)

> **종류**: 결함 검증 + 최소 수정 기록 (실행 증거). `runner-pool-acceptance.yml` lane 업로드 스텝("Upload bootstrap artifacts", L665–681)의 단일 플래그 추가 1건.
> **권위**: 런/잡/스텝·아티팩트 = GitHub Actions API (GET 전용) + 아티팩트 바이트 열거. 본 문서는 Reporter다 (Authority ≠ Adapter — merge-admission 판정을 대체하지 않는다).
> **소비 계약**: `ci-cache-publisher.yml` lane verify 5파일 fail-closed 집합(bin/ax·bin/gate_hook·bin/precompile_gates·bin/install_ax_cas·proofs/.lake/build/bin/ircheck) — DEBT#502 complete-by-construction writer의 lane 경로.
> **trustSurface 처분**: 본 변경 파일은 `config/policy/merge_admission.json` trustSurface 열거 항목(L26)이다. Axiom 로컬 actuator(merge_cli)의 trustSurface 자동병합 거부는 **사용자 명시 권한**(ci_epoch_cutover.md §2.5 — "권한은 사용자 명시에만 있다") + 전면 허가로 처분되며, 착지 경로 자체는 admission-generation.md §4.1 경로 (a)(정상 큐 → 컨트롤러 핀 회전 → §4.3 ruleset 재핀, 하나의 논리적 단위)를 따른다 — §4.2 자기참조 잠금(ROT_NEW_PIN)은 해당하지 않는다(핀 등록 주체는 컨트롤러).

---

## 1. 결함 검증 요약

### 1.1 증상 — `[publish-skip] proofs/.lake/build/bin/ircheck missing after download` 연쇄

`ci-cache-publisher.yml`가 게이트의 `ci-bootstrap-artifacts`를 다운로드해 lane verify 5파일 대조를 하면 매 사이클 `proofs/.lake/build/bin/ircheck missing after download`로 fail-closed skip하고 lane b-key 시딩을 생략한다. 결함 보고 관측 창에서 **3/3 사이클 실패** — 본 문서의 동일일 전수 추적에서는 **8/8 전부 실패**(§3 표, 2026-10-17T03:54–05:56Z)로 확대 확인됐다. G1 S3 검증(`g1_s3_publisher_verification_2026-10-17.md` §4.1)이 독립 기록한 "Lane 시딩 post-fix 0/5 — 레인 페이로드에 `proofs/.lake/build/bin/ircheck` 결손"과 동일 결함이다.

### 1.2 근본 원인 — upload-artifact v4 기본 히든 파일 필터

lane 업로드 스텝이 `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4`를 기본 입력으로 호출하는데, v4의 `include-hidden-files` **기본값은 `false`**다. 이 기본값에서 액션의 탐색은 **숨김 루트 디렉터리(이름이 `.`으로 시작하는 최상위 경로)를 통째로 생략**한다 — lane 경로 목록 중 `.axiom/cache`와 `proofs/.lake`가 정확히 해당한다. 결과: 아티팩트에서 `proofs/.lake/**`(ircheck 포함)·`.axiom/cache/**`가 전량 소실된다.

**흡연총 원문** — 게이트 런 39007767460 (admission-gate, pull_request, head 443318b18)의 `gateway _ ci-bootstrap` 잡 로그, 동일 스텝 안에 3요소가 모두 기록:

1. 업로드 시점 매니페스트가 ircheck 존재를 바인딩: `9d4309bd6387d17582ecd117c3ab7e0b470236fa6cd10e6fbd83da495efc5890  proofs/.lake/build/bin/ircheck` (manifest `build_sha = 611e558a669db069014e2411e2bdc8a6c1396340`)
2. 액션 유효 입력 에코: `include-hidden-files: false` (핀 버전이 입력을 지원함의 직접 증거이자, 기본값으로 실행됨의 원문)
3. `With the provided path, there will be 2193 files uploaded`

이어지는 publisher 런 39008048027이 **동일 아티팩트**(ID 12092190220, 62,782,554B, Expected Digest `sha256:9c87347e…`)를 다운로드하고 `[publish-skip] proofs/.lake/build/bin/ircheck missing after download`로 종료 — 판정 로그 `guard=true trees=true verify=false key=`.

### 1.3 아티팩트 바이트 열거 (결정적 1차값)

아티팩트 12092190220을 직접 다운로드해 열거한 결과:

| 항목 | 파일 수 |
|---|---|
| 총계 | **2193** |
| `build/nimcache/**` | 2188 |
| `bin/*` (ax·gate_hook·precompile_gates·install_ax_cas) | 4 |
| `manifest.txt` | 1 |
| `proofs/.lake/**` | **0** |
| `.axiom/**` | **0** |

선언된 9경로 중 히든 루트 2개(`.axiom/cache`·`proofs/.lake`)의 기여가 정확히 0이고, 나머지 7개는 전부 수습됐다 — 1.2의 기제와 정량 일치.

### 1.4 파일 수 산술 — 결함 보고 1825와 본 문서 독립 재측정

- **결함 보고 산술**(결함 검증 세션): lane 아티팩트 **1825파일** — 히든 경로 기여 0.
- **본 문서 독립 재측정 — 정확히 재현**: 사이클 4 아티팩트 12088953973(59,594,890B) 열거 = **1825파일**(build/nimcache 1820 + bin 4 + manifest.txt 1; `proofs/.lake/**` 0·`.axiom/**` 0) — 결함 보고 수치와 **바이트-열거 수준에서 일치**. 사이클 8 아티팩트 12092190220(62,782,554B) = 2193파일(§1.3). 파일 수는 트리별 nimcache 크기에 따라 사이클마다 다르다(같은 날 두 형상 59,594,xxx B / 62,78x,xxx B 혼재) — **불변인 것은 절대값이 아니라 "히든 기여 = 0"이라는 산술의 구조**며, 결함 보고 창과 본 문서의 두 독립 열거 모두에서 성립한다.

## 2. 실패한 lane 시드 사이클 (결함 보고 3/3 — 동일일 전수 8/8)

| # | 게이트 런 | 아티팩트(완성 시각 UTC) | 크기(B) | publisher 런 | 판정 |
|---|---|---|---|---|---|
| 1 | 39000043068 | 12088782799 (03:53:44) | 59,594,885 | 39000565103 (03:54:26) | ircheck missing |
| 2 | 39000709296 | 12088762305 (04:00:36) | 62,766,254 | 39000979452 (04:01:11) | ircheck missing |
| 3 | 39000589841 | 12089281601 (04:02:09) | 59,594,344 | 39001102525 (04:03:06) | ircheck missing |
| 4 | 39001025721 | 12088953973 (04:08:51) | 59,594,890 | 39002015880 (04:17:37) | ircheck missing |
| 5 | 39002393855 | 12089018912 (04:27:48) | 62,782,553 | 39002700597 (04:28:34) | ircheck missing |
| 6 | 39003029396 | 12090161228 (04:38:30) | 62,782,553 | 39003358308 (04:39:04) | ircheck missing |
| 7 | 39006232355 | 12090599849 (05:30:23) | 62,782,554 | 39006552169 (05:31:09) | ircheck missing |
| 8 | 39007767460 | 12092190220 (05:51:09) | 62,782,554 | 39008048027 (05:56:02) | ircheck missing |

아티팩트 시각 = 아티팩트 `created_at`(게이트 완성·업로드 시점), publisher 시각 = 런 `created_at`(workflow_run 완결 발화). 8/8 전부 동일 마커 단일 원인 — 우연성·환경성 배제. 결함 보고의 "3/3"은 이 연쇄의 임의 3연속 창으로 성립한다.

## 3. 기각된 대안 (REFUTED)

| 대안 가설 | 판정 | 근거 |
|---|---|---|
| **경로 목록(path list) 불일치** | 기각 | publisher verify의 5파일 집합은 lane 업로드 선언 9경로의 부분집합이고, 아티팩트 내 `manifest.txt`가 5파일 전부를 sha256 바인딩(§1.2 원문 — ircheck 포함). 선언 계약 자체는 정확하며, 소실은 **전송 계층**(v4 필터)에서만 발생. |
| **키 불일치(key mismatch)** | 기각 | 실패 지점은 캐시 상호작용 이전의 verify 단계다(판정 로그 `guard=true trees=true verify=false key=` — b-key 산출 이전 종료). 키 파생은 publisher가 build_sha 트리로 detach checkout해 소비자와 바이트 동일을 강제한다(action 주석·구현). 아티팩트 자체에 파일이 없으므로 어떤 키도 이를 소환할 수 없다. |
| (부수) **ircheck 미빌드** | 기각 | 동일 ci-bootstrap 잡에서 `AXIOM_CACHE_B_PROBE: OK — restored proofs/.lake/build/bin/ircheck present+executable`(사전 복원 페이로드에 존재·실행가능) + 매니페스트 sha 바인딩 — 빌드는 되었으나 업로드에서 탈락. |

## 4. 수정

`.github/workflows/runner-pool-acceptance.yml`의 "Upload bootstrap artifacts" 스텝에 `include-hidden-files: true` 1행 추가(+위치 근거 주석 5행). 그 외 **파일 변경 0건** — 경로 목록·keygen·publisher는 바이트 무변경(§3 대안 기각과 동일 근거로 불변 확인).

## 5. 정직한 기대치 (honest expectations)

- **세대 우선 콜드는 구조적이다.** b-key는 빌드 트리 정체성(`b_identity` = 클로저 digest)에서 파생되므로, 새로 착지한 트리 자신의 키 엔트리는 착지 시점에 존재할 수 없다. 본 수정은 **첫 런을 웜으로 만들지 않는다** — 그 첫 콜드는 캐시 계약이 아니라 키 정의의 필연이다.
- **본 수정이 회복하는 것**: (a) **동일 트리 재소비자의 lane 시드** — 같은 트리의 후행 발화(재실행·동일 사이클 내 재사용)가 lane b-key 엔트리를 실제로 얻는다; (b) **DEBT#502 lane 계약의 부활** — complete-by-construction verify(5파일 fail-closed)가 lane 경로에서 처음으로 도달 가능해져, "불완전 페이로드는 어떤 키에도 저장 불가" 불변식이 lane 경로에서 실제로 작동한다(현재는 lane 자체가 항상 불완전 상태로 탈락해 계약이 죽어 있었다).
- **무영향 확인**: mode=none 게이트(아티팩트 부재 → R6 skip 그대로), base 경로(`admission-check-base-artifacts`는 ircheck를 **명시 파일 경로**로 나열해 원래 정상 — §1.2 기제의 역방향 교차증거), 소비자 b-verify fail-closed(부분 엔트리 DISCARD — DEBT#502 (b)).

## 6. 신규 플래그 후속 — 별개 결정 (본 PR 아님)

**b-key 클로저가 Lean 소스를 배제한다.** `setup-axiom-toolchain/action.yml` keygen의 `closure_lines`는 `src-universe`(src/**, generated 제외) + 개별 열거 파일(axiom.nimble·lean-toolchain·**proofs/proof_witness.json**·**proofs/lean-toolchain**·config·data 문서들)로 구성되는데, **`proofs/**/*.lean`·`lakefile.lean`·`lake-manifest.json`은 클로저에 없다**. ircheck는 proofs/의 Lean 빌드 산물(Lean reference extractor)이므로: Nim 측 정체성이 불변인 채 Lean 소스만 변경된 트리는 b-key가 회전하지 않고, S5 build-skip이 **구(舊) Lean 소스로 컴파일된 ircheck**를 복원할 수 있다(stale-ircheck-on-S5-skip 갭). 이는 키 파생(클로저 정의)의 설계 결정으로, 본 전송 계층 수정과 별개 슬라이스에서 판단한다 — 본 PR은 이를 플래그만 한다.

## 7. 재현

```bash
# 게이트 런 원문 (include-hidden-files: false 에코 + 2193 파일 + ircheck 매니페스트 바인딩)
gh api "repos/Archright/Axiom/actions/runs/39007767460/logs" | funzip | \
  grep -E "include-hidden-files|there will be [0-9]+ files|ircheck$" | head
# publisher fail-closed 원문
gh api "repos/Archright/Axiom/actions/runs/39008048027/logs" | funzip | \
  grep -o "\[publish-skip\] proofs/.lake/build/bin/ircheck missing after download"
# 아티팩트 열거 (히든 기여 0)
gh api "repos/Archright/Axiom/actions/artifacts/12092190220/zip" > /tmp/a.zip && \
  unzip -q /tmp/a.zip -d /tmp/a && find /tmp/a -type f | wc -l && \
  find /tmp/a -path '*proofs/.lake*' -o -path '*.axiom*' | wc -l
```
