# merge queue 1차 시도 실패 규명 — attest/admission-check manifest.txt 부재 fail-closed (2026-10-31)

> **종류**: 사건 포렌식 기록(incident forensics) — PR #1132의 1차 merge-queue 시도(merge-group 런 `41070945674`)에서 `attest / admission-check` 잡이 다운로드 아티팩트 내 `manifest.txt` 부재로 fail-closed 종료한 원인을 실측으로 규명한다. 본 문서는 관측·분석만 수행하며 코드·워크플로·게이트·판정 의미론을 변경하지 않는다(§0.12 — 구현 없음, 권고만).
> **권위**: 런/잡/아티팩트 존재·타임스탬프·conclusion = GitHub Actions API(GET-only), 잡 로그 원문 = `GET /repos/Archright/Axiom/actions/jobs/{id}/logs`, PR 큐 이벤트·actor = Issues timeline API, merge-admission 판정 = GitHub merge commit `53e49e1139a35d854946f3d7d8d4a78b37a66e31`. 본 문서는 Reporter다 — GitHub의 판정을 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).
> **플랫폼 시맨틱 출처**: GitHub 공식 문서 — [Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue), [Store and share data (아티팩트 digest 검증·불변성)](https://docs.github.com/en/actions/tutorials/store-and-share-data). Context7(`/websites/github_en_actions`) 경유 인용(2026-10-31 기준).
> **측정 기준**: 시각 = 러너 로그 타임스탬프(ISO-8601 UTC), 바이트 = API/로그 원문 수치. file:line 인용의 워크플로 정의는 실패 런이 실행한 merge-group 커밋 `53f0f399`와 관측 시점 main `53e49e113`에서 **바이트 동일**함을 `git diff 53f0f399 HEAD -- .github/workflows/admission-check.yml .github/workflows/merge-queue-rearm.yml` (빈 출력)로 검증했다.

---

## 1. 판정 요약

**근본 원인(실측 확정 부분)**: 결함은 아티팩트 생산·업로드·서버 저장이 아니라 **소비 잡(`attest / admission-check`, 러너 `gr1rhamqsqa22m8dyy8cp6cztj`)의 41.4 MB 아티팩트 다운로드 스텝이 압축 해제 시작 직후 정상 완료 시퀀스(digest 검증·완료 4줄)를 출력하지 않은 채 소멸**한 것이다. 다운로드 스텝은 `##[error]` 없이 "실패 아님"으로 결론되어 다음 스텝이 실행됐고, `_base-artifacts/manifest.txt`가 존재하지 않아 `admission-check.yml:927`의 fail-closed 검사가 exit 1로 종료했다.

**온전성 역증명(독립 관측 3건)**: 동일 아티팩트(ID `12985041732`, 41,427,705 bytes, zip digest `sha256:08b54c85ffc6fae59f811e5b1c0149ca84766898d0828223c575619a01552340`)는 (i) 같은 런의 `verdict / admission-check` 잡이 2분 뒤 완전 다운로드해 digest 일치 + `MANIFEST VERIFIED`, (ii) GitHub 공식 문서상 download-artifact는 다운로드물의 digest를 자동 계산해 upload-artifact 출력과 검증하며 v4 아티팩트는 불변 — 미완료 다운로드가 digest 검증을 통과해 멤버가 빠진 zip을 노출할 수 없다, (iii) 실패 직후 같은 소비 잡에서 같은 blob 엔드포인트(sa13)로의 소형 아티팩트 2건이 0.4초 내 전체 성공 시퀀스로 다운로드됐다. 업로드 절단·캐시된 불완전 아티팩트·다른 잡 산출 혼입 가설은 전부 기각된다(§5).

**UNKNOWN 경계**: 다운로드 프로세스 소멸의 **직접 사인(OOM 종료·프로세스 크래시·러너 인프라 개입)**은 러너 내부 진단이 API·로그로 접근 불가하여 확정 불가다. 관측으로 확정되는 것은 "완료 시퀀스 없는 무음 종료 + 79초 무로그 공백"까지다(§5.3).

## 2. 실측 타임라인 (2026-10-30, UTC)

| 시각 | 사건 | 출처(실측) |
|---|---|---|
| 14:05:39 | PR #1132 auto-merge 활성 — actor `wintrover` | Issues timeline |
| 14:16:29 | PR #1132 merge queue 등록 — actor `wintrover` | Issues timeline |
| 14:20:02 | 큐 그룹 형성, MG 런 `41070945674` 생성 (`admission-gate`, `merge_group`, head_branch `gh-readonly-queue/main/pr-1132-efa771da…`, G=`53f0f399…`) | Runs API |
| 14:20:42–14:21:47 | `attest / build-base-artifacts` (job `124114561177`, 러너 `gr7caabdj7st5n7a9t6cpzehg1`) **success** | Jobs API |
| 14:21:30.48 | job1이 `manifest.txt` 생성·출력(build_sha=`efa771da…` + 7멤버 sha256) | job1 로그 :942–951 |
| 14:21:36.65 | 아티팩트 `admission-check-base-artifacts` 업로드 확정 — ID `12985041732`, **41,427,705 bytes**, 8파일, digest `08b54c85…2340` | job1 로그 :976·:987·:989–990 |
| 14:26:15–14:28:47 | `attest / admission-check` (job `124116517068`, 러너 `gr1rhamqsqa22m8dyy8cp6cztj`) **failure** | Jobs API |
| 14:27:17.85 | 소비 잡의 41.4 MB 아티팩트 다운로드 시작 — 같은 ID·크기·digest | 실패 잡 로그 :1002–1005 |
| 14:27:18.33 | 압축 해제 시작 표식(Buffer 경고) — **이후 완료 시퀀스 전무** | 실패 잡 로그 :1006 |
| 14:28:37.27 | (79초 무로그 공백 후) 다음 스텝 시작 | 실패 잡 로그 :1006→:1007 |
| 14:28:37.29 | `FAIL: manifest.txt missing in downloaded artifact` — **exit 1 (fail-closed)** | 실패 잡 로그 :1068–1069 |
| 14:28:38.5–39.8 | 같은 잡의 `if: always()` 후속 다운로드 2건(1,929 B·5,876 B, **같은 sa13 엔드포인트**) 전체 성공 시퀀스 | 실패 잡 로그 :1084–1091·:1106–1113 |
| 14:29:43.68 | `mint-prepare / prepare` (job `124117640395`) failure — `MINT_ART: FAIL — expected exactly one artifact named 'admission-check-53f0f399…-1', found 0` | mint-prepare 로그 :1353–1354 |
| 14:30:30–58 | `verdict / admission-check` (job `124118273192`, 러너 `grebbjqdj5ce2q2qydygm7zp4e`)이 **같은 아티팩트 ID `12985041732`** 완전 다운로드 — digest 검증 일치, `MANIFEST VERIFIED` | verdict 로그 :311·:315–318·:389 |
| 14:36:49 | verdict 잡 자체 판정 `admission verdict NOT-ADMIT (reasonCode=NO_CERT)` — job `124118273192` failure(별도 원인, §8) | verdict 로그 :990·:1013–1014 |
| 14:37:16–22 | 요약 잡 `admission-check` (job `124122227605`) failure — 필수 하류 실패 반영 | Jobs API |
| 14:37:27 | **`removed_from_merge_queue` — actor `github-merge-queue[bot]`** | Issues timeline |
| 14:37:30–14:38:38 | rearm 자동화 런 `41073248120` — 판정 `class=UNKNOWN, action=no-arm` | rearm 로그 :788 |
| 14:46:02 | **`added_to_merge_queue` — actor `wintrover` (수동 재등록)** | Issues timeline |
| 14:46:20 | 2차 MG 런 `41074587078` 생성(같은 head_branch, 같은 G/B) | Runs API |
| 14:46:49–14:47:44 | 2차 job1 (job `124127257604`) success — **새 아티팩트 ID `12987106541`**, 14:47:33 생성, **41,427,705 bytes**(1차와 동일 크기), digest `1004bf7d…eb7` | Artifacts API, 2차 로그 :1012 |
| 14:53:30–55 | 2차 소비 잡 다운로드 — digest 검증 일치 → 7멤버 전부 `OK` → `MANIFEST VERIFIED` (14:53:56.23) | 2차 로그 :1016–1019·:1083–1090 |
| 14:52:30–14:56:12 / 14:58:36–14:59:40 | 2차 `attest / admission-check` (job `124130250738`)·`verdict / admission-check` (job `124133287931`) **success** | Jobs API |
| 15:01:02 | **병합** — merge commit `53e49e1139a35d854946f3d7d8d4a78b37a66e31` (`removed_from_merge_queue` actor `github-merge-queue[bot]`) | PR API, Issues timeline |

## 3. 실패 잡 원문 (1차 시도, job `124116517068` 로그)

다운로드 스텝(`admission-check.yml:901-912` "[check] Download base-built artifacts") — 로그 :989–1006:

```
##[group]Run actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093
with:
  name: admission-check-base-artifacts
  path: _base-artifacts
  ...
  run-id: 41070945674
Downloading single artifact
Preparing to download the following artifacts:
- admission-check-base-artifacts (ID: 12985041732, Size: 41427705, Expected Digest: sha256:08b54c85ffc6fae59f811e5b1c0149ca84766898d0828223c575619a01552340)
Redirecting to blob download url: https://productionresultssa13.blob.core.windows.net/...
Starting download of artifact to: /home/runner/work/Axiom/Axiom/_base-artifacts
(node:2407) [DEP0005] DeprecationWarning: Buffer() is deprecated ...   ← 압축 해제 시작 표식
```

**이 줄 다음에 성공 시의 필수 시퀀스 4줄이 없다.** 성공 사례(verdict 로그 :315–318)에서는 반드시 이어진다:

```
SHA256 digest of downloaded artifact is 08b54c85ffc6fae59f811e5b1c0149ca84766898d0828223c575619a01552340
Artifact download completed successfully.
Total of 1 artifact(s) downloaded
Download artifact has finished successfully
```

1차 실패 잡에서는 :1006(Buffer 경고) → :1007(다음 스텝 그룹) 사이에 **로그 0줄, 78.94초 공백**이며 `##[error]` 주석도 없다. 다음 스텝("[check] Verify artifact manifest", `admission-check.yml:919-927`)의 첫 문에서 종료:

```
test -f _base-artifacts/manifest.txt || { echo "FAIL: manifest.txt missing in downloaded artifact"; exit 1; }   (:1011, 워크플로 :927)
...
FAIL: manifest.txt missing in downloaded artifact        (:1068)
##[error]Process completed with exit code 1.             (:1069)
```

스텝 `if` 조건(`admission-check.yml:902·:920`, `scope_sl08 == 'true' && venue == 'landing'`)상 verify 스텝이 **실행된 사실 자체**가 러너가 다운로드 스텝을 "실패 아님"으로 결론했음을 뜻한다(plain `if` 스텝은 선행 스텝 실패 시 skip됨). 즉 이 스텝은 **오답 성공(false-success)으로 결론된 무음 종료**다.

같은 잡의 이전 단계는 건강했다: B-캐리어 exact-hit 복원 + 5/5 digest 검증 통과(:529·:625), `_candidate` 체크아웃(G=`53f0f399…`) 정상. 실패는 다운로드 스텝에서 처음 발생했다.

## 4. 생산자 추적 — manifest.txt는 무엇이 쓰는가

- **생산 경로**: `admission-check.yml` job1 `build-base-artifacts`(:200)의 스텝 "[build] Emit fail-closed artifact manifest (bind to B)"(:534-550). `: > manifest.txt`(:538) 후 `build_sha = <B>`(:541)와 7멤버(`bin/ax`, `bin/install_ax_cas`, `proofs/.lake/build/bin/ircheck`, `bin/gate_hook`, `bin/precompile_gates`, `bin/derive_checker_closure`, `bin/jq`)의 `sha256sum`(:544-548)을 기록한다.
- **업로드 경로**: 같은 job1의 "[build] Upload base-built artifacts"(:552-595) — name `admission-check-base-artifacts`(:557), 경로에 `manifest.txt` 포함(:559-567), `if-no-files-found: error`(:583), `overwrite: true`(:595).
- **1차 런 실측**: job1 로그에서 manifest cat 출력(:942-951, `build_sha = efa771dab358367a3a6c8fa51c80bf0213275571` + 7멤버 digest) → "With the provided path, there will be **8 files uploaded**"(:976) → "SHA256 digest of uploaded artifact zip is `08b54c85…2340`"(:987) → "successfully finalized. Artifact ID 12985041732 ... Final size is 41427705 bytes"(:989-990).
- **재발행 경로의 존재(참고)**: `ci-cache-publisher.yml`는 이 아티팩트를 base b-key로 재발행하는 별도 채널을 갖는다(:19·:118·:224·:477·:499-523) — 단, 그 소비자는 이후 사이클의 캐시 가속이며 1차 MG 런의 소비 잡은 `run-id: 41070945674`로 **런 내 아티팩트**를 직접 내려받았다(실패 잡 로그 다운로드 파라미터). 다른 잡 산출 혼입 경로는 없다.
- **무결성 계약(플랫폼 공식 문서)**: "download-artifact 액션은 다운로드한 아티팩트의 digest를 자동 계산해 upload-artifact 스텝의 출력과 검증한다", 그리고 v4 아티팩트는 불변("artifacts are considered immutable in v4") — [Store and share data]. upload-artifact는 업로드 시 digest 출력을 반환한다. 따라서 (a) 소비자 로그에 digest 검증 줄이 **없었다**는 사실은 다운로드가 검증 단계에 도달하지 못했다는 뜻이고, (b) digest 검증을 통과한 다운로드가 멤버가 빠진 zip을 추출하는 경로는 계약상 존재하지 않는다.
- **가설 정리**: 업로드 절단 가설 — 기각(생산자가 8파일 카운트+digest+확정 로그, §5 역증명). 캐시된 불완전 아티팩트 가설 — 기각(소비 잡은 run-scoped name+run-id로 런 내 아티팩트를 직접 다운로드; 재발행 채널 미경유). 부분 업로드 노출 가설 — 기각(v4 불변+업로드 finalize 후 가시; download-artifact의 자동 digest 검증이 부분 zip을 차단).

## 5. 결함 위치 판정 — 서버 측 아티팩트는 온전했다

### 5.1 독립 관측 1 — 같은 런의 verdict 잡(러너 `grebbjqdj5ce2q2qydygm7zp4e`)

14:30:29–58Z, **같은 아티팩트 ID `12985041732`·크기 41,427,705·digest `08b54c85…2340`**(verdict 로그 :311)를 다운로드해 `SHA256 digest of downloaded artifact is 08b54c85…`(:315) → `Artifact download completed successfully.`(:316) → `Download artifact has finished successfully`(:318) → `MANIFEST VERIFIED: verifier is built from B=efa771da…`(:389). 즉 다운로드 검증을 통과한 소비자에게는 manifest.txt가 존재했다. 이 잡의 failure(14:36:49, `NOT-ADMIT (reasonCode=NO_CERT)`)는 본 결함과 무관한 별도 판정이다(§8).

### 5.2 독립 관측 2 — 실패 직후의 소형 다운로드(같은 잡, 같은 러너)

`if: always()` 후속 스텝의 `go-judgment-lane-0`(ID `12984513820`, 1,929 B)과 `go-judgment-lane-1`(ID `12985196488`, 5,876 B) 다운로드가 14:28:38.56–39.84Z에 **같은 blob 엔드포인트 `productionresultssa13.blob.core.windows.net`**(:1085·:1109 redirect URL)에서 각각 digest 검증+완료 4줄과 함께 ~0.4초 만에 성공했다(:1088-1091·:1110-1113). 네트워크·스토리지·액션 바이너리는 정상이었고, 이상은 41.4 MB 다운로드 스텝의 프로세스에 국한됐다.

### 5.3 소멸 사인의 UNKNOWN 경계

확정된 관측: (i) 추출 시작 표식(버퍼 경고) 이후 로그 0줄, (ii) 완료 시퀀스 4줄 전무, (iii) `##[error]` 없음, (iv) 러너는 스텝을 실패 아님으로 결론. 미확정: 프로세스가 **왜** 종료됐는가(OOM killer 타깃·node 프로세스 크래시·러너 호스트 인프라 개입 등) — 러너 내부(syslog/runner diagnostics)는 GitHub API로 접근 불가하며 본 조사 범위 밖이다. **UNKNOWN으로 남긴다.**

### 5.4 소비 측 부분 추출의 파일 단위 관측 한계

verify 스텝이 첫 문(`test -f _base-artifacts/manifest.txt`)에서 종료했으므로, 나머지 7멤버가 부분 추출물에 존재했는지는 **측정되지 않았다**. 유일한 파일 단위 실측은 "manifest.txt 부재"다.

## 6. 2차 시도와의 차이 — 무엇이 달랐는가

| 항목 | 1차 (런 `41070945674`) | 2차 (런 `41074587078`) |
|---|---|---|
| 큐 진입 | 14:16:29 등록 → 14:20:02 그룹 | 14:46:02 수동 재등록 → 14:46:20 그룹 |
| 생산 job1 | `124114561177`, 14:20:42–14:21:47 | `124127257604`, 14:46:49–14:47:44 |
| 아티팩트 | ID `12985041732` (14:21:36) | ID `12987106541` (14:47:33) — **새로 재생성됨** |
| 아티팩트 크기 | 41,427,705 B | 41,427,705 B (동일 — 동일 B=`efa771da…` 결정론 재빌드) |
| zip digest | `08b54c85…2340` | `1004bf7d…eb7` (상이) |
| 소비 러너 | `gr1rhamqsqa22m8dyy8cp6cztj` | `grkg3tjsvgwj3nnxc44htnjmv0` |
| 다운로드 | 14:27:17 시작 → **완료 시퀀스 없이 소멸**(79초 공백) | 14:53:30 시작 → **14:53:55 digest 검증+완료**(약 25초) |
| manifest 검증 | 실패(exit 1) | 7멤버 전부 `OK` + `MANIFEST VERIFIED`(:1083-1090) |

차이의 실측 결론: 워크플로 정의·B 트리·생산 경로는 동일하고, 달라진 것은 **새 아티팩트 재생성**과 **다른 러너에서의 다운로드**다. 2차에서 동일 결함이 미재현된 것은 재생성된 아티팩트 덕이 아니라(1차 아티팩트 자체도 verdict 잡이 완전 소비했다 — §5.1) **소비 시점 러너에서의 다운로드 프로세스 생존 여부**의 차이로 설명된다. 즉 결함은 재현성이 없는 러너 국면의 일탈이며 코드·워크플로 결정론 결함이 아니다.

## 7. merge queue 시맨틱 — 이탈·재등록의 권위 관측

- **플랫폼 문서(공식)**: merge queue는 필수 체크 실패 또는 베이스 충돌 시 해당 PR을 큐에서 제거하며("the pull request will be removed from the queue"), 제거 사유는 PR 타임라인에 표시된다. 제거 사유 열거(테스트 실패/타임아웃/사용자 요청/브랜치 보호 실패)에 **실패 후 자동 재등록은 존재하지 않는다** — [Managing a merge queue].
- **실측**: 14:37:27Z 제거 actor=`github-merge-queue[bot]`(플랫폼), 14:46:02Z 재등록 actor=`wintrover`(사용자 수동). **관측 기록에 있던 "9분 뒤 자동 재등록"은 플랫폼 자동 재시도가 아니라 사용자의 수동 재추가로 확정**된다.
- **저장소 rearm 자동화의 판정(실측)**: `merge-queue-rearm.yml`의 트랜지언트 재무장 자동화가 14:37:30–14:38:38Z에 런 `41073248120`을 실행했고, 판정 JSON(rearm 로그 :788): `{"class":"UNKNOWN","reason":"no explicit evidence anchor matched (DEFAULT-NO-ARM — a 'failure' conclusion alone never implies TRANSIENT)","action":"no-arm",...}`. 이 결함 클래스는 동작 앵커 T2(b)(아티팩트 다운로드의 HTTP 5xx·curl 전송 오류)와 불일치한다 — 본 건의 다운로드 스텝은 오류 응답 없이 **무음 종료**했기 때문이다. 자동화는 계약대로 DEFAULT-NO-ARM을 지켰고 재등록에 개입하지 않았다.
- **동일 결함의 미재현이 병합을 가능하게 한 경로**: 수동 재등록 → 새 그룹 → 2차 런 전 잡 success → GitHub가 병합(15:01:02Z). merge-admission 권위는 GitHub이며 2차 시도의 통과가 1차 결함의 부정이 아니다(§5.1 — 같은 아티팩트의 양립 관측).

## 8. 연쇄 실패 — 1차 런의 나머지 failure 전부가 하류다

| 잡 | 실패 원문(로그 :행) | 인과 |
|---|---|---|
| `mint-prepare / prepare` (`124117640395`) | `MINT_ART: FAIL — expected exactly one artifact named 'admission-check-53f0f399…-1', found 0 (fail-closed)` (:1353) | attest 잡이 verify 스텝에서 조기 사망해 witness 아티팩트 미업로드 |
| `mint-publish / publish` (`124118271285`) | prepare 산출 부재로 실패(14:30:04–22) | mint-prepare 하류 |
| `verdict / admission-check` (`124118273192`) | `admission verdict NOT-ADMIT (reasonCode=NO_CERT)` (:1013) | 인증서 소스가 런 내 subject-certificate 미발행 상태(`Artifact not found for name: subject-certificate-1` :425) — attest 사망의 하류 판정. 단, 이 잡은 **manifest 검증 자체는 통과**했다(:389) |
| `admission-check` (요약, `124122227605`) | 필수 하류 실패 반영(14:37:16–22) | 종합 |

나머지 7개 워크플로 전부 success(사실 관찰 기록과 일치 — 단일 결함 국소성의 부합 증거).

## 9. 판정

**근본 원인(확정)**: 1차 merge-queue 시도의 실패는 **소비 잡 러너에서 41.4 MB `admission-check-base-artifacts` 다운로드 스텝이 압축 해제 중 완료 시퀀스 없이 무음 종료(오답 비실패 결론)**한 사건이며, 그 결과 `_base-artifacts/manifest.txt` 부재 → `admission-check.yml:927` fail-closed exit 1 → attest 잡 사망 → 하류 4잡 연쇄 실패 → 큐 이탈이었다. 아티팩트 생산·업로드·서버 저장·전송 계약은 3개 독립 관측(§5.1·5.2·2차 재생성)과 플랫폼 무결성 계약에 따라 **온전**했다. fail-closed 검사는 계약대로 동작했다 — 검증 불가 공급은 사용하지 않고 죽는 것이 이 검사의 설계 목적이며, 본 건은 그 올바른 발동이다.

**UNKNOWN**: 다운로드 프로세스 소멸의 직접 사인(OOM·크래시·인프라 개입) — 러너 내부 진단 접근 불가(§5.3). 부분 추출물의 나머지 7멤버 존재 여부 — 첫 문 조기 종료로 미측정(§5.4).

## 10. 권고 (문서 전달분 — 구현 없음, .github FROZEN)

1. **워크플로 로직 변경 근거 없음**: 생산·소비·검증 체계는 본 사건에서 계약대로 동작했다. 결함 국면은 러너에서의 일회성 다운로드 프로세스 소멸이고, 2개 독립 관측에서 동일 바이트 스트림의 완전 소비가 확인됐다(§5). 재시도 가능한 구조(아티팩트 불변+digest 바인딩)는 이미 존재한다.
2. **재무장 분류 공백의 명시(정책 개정 대상)**: 이 결함 클래스("다운로드 스텝이 digest 검증·완료 줄 없이 무음 종료, 하류 fail-closed가 포착")는 `merge-queue-rearm.yml`의 닫힌 앵커 열거에 없어 `UNKNOWN → DEFAULT-NO-ARM`으로 남는다 — 즉 재발 시마다 수동 재등록이 필요하다. 앵커 추가는 헤더의 계약상 **명시적 정책 개정(사용자 결정)**이 필요하며, 본 문서는 그 판단 재료(원문·관측)만 제공한다.
3. **운영 프락시(무변경)**: 재발 판별 프락시로 "대형 아티팩트 다운로드 스텝 로그에 `Artifact download completed successfully.` 줄이 있는가"를 사용할 수 있다 — 성공 시 반드시 출력되는 플랫폼 시맨틱이며, 이 프락시는 본 건에서 1차(부재)·verdict/2차(존재)를 정확히 분리했다(§3·§5.1·§6).

## 11. 관련 맥락 (인용만, 접촉 없음)

PR #1128(`feat/cache-carrier-separation`, OPEN, "ci(cache): separate mg nimcache fold from required attest job — ci-cache-publisher base-seed absorption")은 **캐시 가속 캐리어**(`admission-check-base-nimcache` → ci-cache-publisher base-seed 흡수) 구조를 다루는 타 workstream 작업이다. 본 사건의 결함 채널은 **증거 채널**(`admission-check-base-artifacts` — 8멤버 manifest 바인딩, attest·mint·verdict의 fail-closed 공급)이며 두 채널은 `admission-check.yml:568-582`의 주석 계약대로 분리돼 있다. 본 조사는 PR #1128의 브랜치·worktree에 접촉하지 않았다.

## 부록 A. 증거 인벤토리 (GET 재현 명령)

```
gh api repos/Archright/Axiom/actions/runs/41070945674 --jq '{head_sha,head_branch,event,run_attempt}'
gh api repos/Archright/Axiom/actions/runs/41070945674/jobs?per_page=100
gh api repos/Archright/Axiom/actions/jobs/124116517068/logs   # 1차 실패 소비 잡 (본문 §3 인용)
gh api repos/Archright/Axiom/actions/jobs/124114561177/logs   # 1차 생산 잡 (§4 인용)
gh api repos/Archright/Axiom/actions/jobs/124118273192/logs   # 1차 verdict 잡 (§5.1 인용)
gh api repos/Archright/Axiom/actions/runs/41074587078/jobs?per_page=100
gh api repos/Archright/Axiom/actions/jobs/124130250738/logs   # 2차 소비 잡 (§6 인용)
gh api repos/Archright/Axiom/actions/jobs/124122554566/logs   # rearm 판정 (§7 인용, :788)
gh api repos/Archright/Axiom/actions/runs/41070945674/artifacts
gh api repos/Archright/Axiom/actions/runs/41074587078/artifacts
gh api "repos/Archright/Axiom/issues/1132/timeline?per_page=100"   # 큐 이벤트·actor (§7)
gh api repos/Archright/Axiom/actions/workflows/merge-queue-rearm.yml/runs?created=2026-10-30T14:00:00Z..2026-10-30T16:00:00Z
```

플랫폼 문서: [Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) — 실패 시 큐 제거·제거 사유 열거(자동 재등록 부재). [Store and share data](https://docs.github.com/en/actions/tutorials/store-and-share-data) — download-artifact 자동 digest 검증, upload-artifact digest 출력, v4 아티팩트 불변성. Context7 `/websites/github_en_actions` 경유(2026-10-31).

## 부록 B. 조사 경계

- 본 문서는 잡 로그·API 관측만을 사용했다. 러너 호스트 내부 진단(프로세스 사인)은 플랫폼이 노출하지 않는다 → §5.3 UNKNOWN.
- raw 로그 사본은 조사 중 로컬에만 보관했으며 본 커밋에는 포함하지 않는다. 위 부록 A의 GET 명령으로 원문 전량을 재현할 수 있다.
