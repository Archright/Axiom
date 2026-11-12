# CI L1-a P0 — LTO 병렬화 Cross-Screening 증거 (셀프호스트 x64 러너) — 2026-08-30

> 실측값 단일 출처 = 하네스 `tools/ci/lto_measure_shot.sh`가 셀프호스트 x64 러너에서 생성한
> `_lto_measure/evidence-*.txt` (원문 그대로 재현). 본 문서는 원본 evidence의 읽기 전용 투영이며,
> hand-authored 숫자 소스를 만들지 않는다.
>
> 실험 설계: L1-a = "same LTO semantics, link parallelism 증가".
> P0 = benchmark-only. 변경 이력: workflow `l1a-lto-screening.yml` (immutable `ci.yml` 아님).

---

## 1.요약

| Shot | profile (effective link flags) | buildWallMs | binSize | binSha | 5-level oracle |
|------|--------------------------------|-------------|---------|--------|----------------|
| **A** | serial lto1 (현행) | **202248** (runner-2) | 8054128 | `9641e95d...` | 전부 rc=0, byte-identical |
| **C** (=A 재실행) | serial lto1 (현행) | 364449 (다른 호스트) | 8054128 | `9641e95d...` | 전부 rc=0, byte-identical |
| **B** | parallel lto2 (후보) | **138306** (runner-2) | 8308880 | `b170c322...` | 전부 rc=0, A/C와 byte-identical |

- **동일 호스트 풀(runner-2) 기준 지배 비교**: A **202.2s → B 138.3s = 63.9s ↓ (~32%)**. 컴파일은 동일(동일 소스/콜드/동일 passC `-flto`), 차이는 링크 병렬성뿐 → **직렬 LTO link가 wall-clock 병목이었고 후보 플래그가 이를 감소**.
- **의미론 동등성(P0 게이트)**: 후보 B의 5개 stateless invariant oracle 해시가 현행 A/C와 **byte-identical** → canonical 검증 결과/evidence identity는 플래그 변경에도 그대로 유지.
- **결정론(Determinism)**: C(=A 재실행)가 A와 **byte-identical binary + 동일 oracle 해시** → host 간 결정론 확인(artifact digest 기준).
- **P0 판정**: **GO** (후보가 현행 대비 link wall-clock을 줄이고 oracle 의미론을 보존).

⚠️ **wall-clock 재현성 주의**: A(202s, 단독 실행)와 C(364s, B와 동시 실행)는 같은 serial-lto1이지만
 1.8배 차이 — 동시 부하에 민감. 따라서 절대 wall-clock보다 **oracle byte-identical**이 robust 게이트이며,
 B(138s)가 **동시 부하 상태에서도** A 단독(202s)보다 빨랐던 것이 상대 신호. production 승격 여부는
 P1 로컬 invariance + P2 실제 CI run에서 최종 확인.

---

## 2. 원본 evidence (그대로)

### 2.1 A — serial lto1, run `<redacted>`, runner-2

```
ltoShot=A
runner=<redacted-host-1>
coreCount=2
passlOverride=config.nims-default
toolchain:Nim Compiler Version 2.2.10 [Linux: amd64]
toolchain:gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0
head=8f14c1577a4cdb262a879025792c1828a2812411
buildExitCode=0
buildWallMs=202248
binExists=yes
binSize=8054128
binSha=9641e95d55e2e8d9a4b9b1a35617a220775367027906088a95311aa7d2e17010
linkFlags=-flto -flto-partition=one -flto=1
buildPeakRssKiB=1820520
oracle:scope-hash=rc=0 hash=4dc341806058e29bbc889e60fa1863b22e8179ed9bd8079e197366d7da8334ce
oracle:version=rc=0 hash=e450e1158064dbfdadda886193d1c39d6d956384ca0c99c64f343feab7cb573b
oracle:invariants-sync=rc=0 hash=d2d3775c9d0e727351a481f6eeab149fa58332c7116cb8fce22576a31484ce78
oracle:baseline-check=rc=0 hash=dd1c2d0dc2eced9b6357a20c91fe4d3ae5622c1580cb27426451d8eaa95f758b
oracle:config-validate=rc=0 hash=fa244272601fcfbeb3aa2d2cb035d234da899dbbfcf85fe0ec11db1a22881c56
```

### 2.2 C — 결정론 재실행 (=A), run `<redacted>`, 다른 호스트

```
ltoShot=A
runner=<redacted-host-2>
coreCount=2
passlOverride=config.nims-default
head=8f14c1577a4cdb262a879025792c1828a2812411
buildExitCode=0
buildWallMs=364449
binExists=yes
binSize=8054128
binSha=9641e95d55e2e8d9a4b9b1a35617a220775367027906088a95311aa7d2e17010
linkFlags=-flto -flto-partition=one -flto=1
buildPeakRssKiB=1676496
oracle:scope-hash=rc=0 hash=4dc341806058e29bbc889e60fa1863b22e8179ed9bd8079e197366d7da8334ce
oracle:version=rc=0 hash=e450e1158064dbfdadda886193d1c39d6d956384ca0c99c64f343feab7cb573b
oracle:invariants-sync=rc=0 hash=d2d3775c9d0e727351a481f6eeab149fa58332c7116cb8fce22576a31484ce78
oracle:baseline-check=rc=0 hash=dd1c2d0dc2eced9b6357a20c91fe4d3ae5622c1580cb27426451d8eaa95f758b
oracle:config-validate=rc=0 hash=fa244272601fcfbeb3aa2d2cb035d234da899dbbfcf85fe0ec11db1a22881c56
```

### 2.3 B — parallel lto2 후보, run `<redacted>`, runner-2

```
ltoShot=B
runner=<redacted-host-1>
coreCount=2
passlOverride=--passL:-flto=2 -flto-partition=balanced
head=8f14c1577a4cdb262a879025792c1828a2812411
buildExitCode=0
buildWallMs=138306
binExists=yes
binSize=8308880
binSha=b170c32283f62e35c3b30eff7f15c4d85d609831debb9117c07005aec08d0211
linkFlags=-flto -flto-partition=one -flto=1 -flto=2 -flto-partition=balanced
buildPeakRssKiB=1916284
oracle:scope-hash=rc=0 hash=4dc341806058e29bbc889e60fa1863b22e8179ed9bd8079e197366d7da8334ce
oracle:version=rc=0 hash=e450e1158064dbfdadda886193d1c39d6d956384ca0c99c64f343feab7cb573b
oracle:invariants-sync=rc=0 hash=d2d3775c9d0e727351a481f6eeab149fa58332c7116cb8fce22576a31484ce78
oracle:baseline-check=rc=0 hash=dd1c2d0dc2eced9b6357a20c91fe4d3ae5622c1580cb27426451d8eaa95f758b
oracle:config-validate=rc=0 hash=fa244272601fcfbeb3aa2d2cb035d234da899dbbfcf85fe0ec11db1a22881c56
```

> B `linkFlags`가 기본(`-flto -flto-partition=one -flto=1`)과 override(`-flto=2 -flto-partition=balanced`)를
> 모두 나열하지만, GCC에서 나중 옵션(override)이 최종 승리 → effective = `-flto=2 -flto-partition=balanced`.
> (하네스 `PASSL_OVERRIDE`는 `config.nims` 기본 뒤에 append됨 — evidence의 `effective` 기록은
> nimcache `ax.json` linkcmd에서 추출한 현재 적용 문자열이며, 이것이 "영향을 준 플래그"의 SSOT.)

---

## 3. context7 / 정식 문서 근거 (병렬 서브에이전트 검증)

온라인 정식 문서(GCC optimize options, Nim `nimc.html`) 검증 결과 — L1-a 전제 일치:

- GCC `-flto[=n]`: 독립적인 병렬 link-time jobs 수만 조절. **최적화 pass/결과는 같고 병렬성만 증가**.
- GCC `-flto-partition=one` = 단일 partition(직렬, 메모리 최소) / `balanced` = 동일 크기 chunk들로 분할.
- `one`→`balanced`로 바꿔도 pass 선택·변환 로직은 동일 — **이론상 semantic 동등**.
- 2-vCPU에서 `-flto=2 -flto-partition=balanced`는 직렬 `-flto=1 -flto-partition=one` 대비 link wall-clock
  감소가 GCC 문서상 타당(Amdahl). → **P0 실측이 이를 지지**.
- 문서화된 주의: balanced는 partition별 IR을 동시 보유하여 peak RSS 상승 가능(문서 caveat),
  병렬 LTO는 **layout/주소가 바뀌어 byte-diff가 가능하나 semantic은 동일** — 그래서 P0 게이트는
  **hash 동일이 아닌 oracle(해시 후보) 동등**으로 정의했고 실측 통과.

---

## 4. 교훈 / 다음 단계

1. **원인 재확인**: O1(warm nimcache)이 병목이 아니었고, L1-a 병렬-LTO가 실제 link 직렬성 비용을
   벗겨냄. `NO-LTO 45.7s / LTO 138.5s`(로컬) 대비, 셀프호스트 콜드 전체 shot A≈202s에서 B≈138s로 감소.
2. **P1 로컬 invariance 완료 (GO)**: version/invariants-sync/baseline-check/config-validate = serial·candidate
   byte-identical; scope-hash 차이는 config.nims 내용 포함(빌드 계약 추적)으로 LTO-invariant임을 직접 증명.
   `make verify-contract-unit` **10/10 PASS**, `make test-gateway` **86/86 PASS**, `verify-contract-release-e2e` PASS.
   `ax merge --dry-run`은 GITHUB_TOKEN 필요로 production CI에서 커버.
3. 다음: **P2** `config.nims` `passL`에 `-flto=2 -flto-partition=balanced` 반영 + 문서 + **B1 fresh CI run**.
   여기서 실제 PR critical path 영향(verify-integration 내 contract 비용)을 재측정.
4. **P3 판정**: 실질 개선 시 B1을 새 baseline으로 승격 & L1-b(NO-LTO CI-fast profile) 폐기.
   개선이 유의하지 않으면 L1-b 검토.

> 참고: A와 C의 wall-clock 차이(202s vs 364s)는 동시 부하/호스트 변동이며 artifact 결정론과는 무관
> (C==A byte-identical). promotion의 최종 근거는 P2의 **실제 CI critical path 재측정**.
