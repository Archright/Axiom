# config.nims Hermetic Cache Identity Quirk (DEBT#417)

> 이 문서는 `config.nims` hermetic pre-build cache(`hermeticPreBuild envHash`)가
> **VCS staging state 대신 빌드 입력 콘텐츠**를 identity로 삼도록 변경된 사실과,
> 그 변경이 지우는 것/남기는 것/남기는 위험을 기록합니다.
> 모든 에이전트는 hermetic cache identity / envHash 관련 변경 시 이 문서를 먼저 참조해야 합니다.
> AGENTS.md §0.5 — Quirk Mandate (Documentation-First)의 실행 부속서입니다.
> Registry linkage: `data/debt_registry.json` → id `DEBT#417` (resolution `FIXED`, status `closed`).

---

## §1. Registry Linkage

| 필드 | 값 |
|---|---|
| Debt ID | `DEBT#417` |
| Title | hermetic cache identity contained VCS staging state (`.git/index`) instead of build-input content |
| Symbol | `config.nims hermeticPreBuild envHash` |
| LineRange | 변경 전 `config.nims:442`, `:448-457`, `:465-474` (2026-10-05 커밋에서 삭제) |
| Resolution | `FIXED` (2026-10-05) — `WONT_FIX`에서 변경 |
| Severity | `medium` |
| Category | `Architecture` |

**2026-10-05 정정 — 이전 판정의 근거가 사실과 달랐다.** 이전 판본은
"`config.nims` is in the §-1 immutable set"을 이유로 `WONT_FIX`를 유지했으나,
이는 §-1 보호 범위를 과장한 것이다:

- AGENTS.md §-1(`AGENTS.md:12-17`)가 보호하는 대상은
  `src/gate/runners/import_encapsulation_gate.nim` + **`config.nims`의
  importEncapsulation 블록**이다. 파일 전체가 아니다.
- 그 블록은 현재 `config.nims`에 존재하지 않는다. `grep -i encapsul config.nims`
  → 0건. 잔재는 `config/strict.nims:326-330`의 `MOVED to runtime` 주석으로 남아 있다.
- `src/gate/runners/import_encapsulation_gate.nim`의 `checkFile`(`:63-82`)은
  import 줄만 파싱하고, `runImportEncapsulationScan`(`:86-94`)은
  `walkDirRec(repoRoot / "src")`에서 `*.nim`만 수집한다. `config.nims`를 읽지 않는다.

**실제 기계 강제 경로는 따로 있었다.** `config/repository_surface.json:215-231`의
`FROZEN` 목록이 `config.nims`를 포함하고, pre-push `check-repository-surface`
(`Makefile:393-398`, `PUSH_ADMISSIBILITY_GATES`의 일원 — `Makefile:54`)가
base policy × 브랜치 diff로 이를 fail-closed 집행한다. 이 변경은 인간 오너의
명시적 승인을 받아 해당 경로를 통과했다.

`src/gate/orchestrator/hook/memo.nim:30`의 `{.axiomDebt: "DEBT#417".}` 마커는
**의도적으로 유지**했다. DEBT가 `closed`로 전환된 이상 `debt_integrity_gate`가 요구하는
마커 의무는 사라지지만(AGENTS.md §0.5c), 삭제는 이 문서 커밋에서 판단할 사안이 아니라
은퇴 슬라이스의 사안이다. 마커 위의 설명 주석만 현재 동작에 맞게 갱신했다.

---

## §2. Symptom (변경 전, 실측)

- **자가무효화 루프 (결정적 근본)**: `MISS` 분기는 `bin/hermetic_build`를 실행하고,
  이 도구는 `git status --porcelain`(`tools/hermetic_build.nim:1248`),
  `git diff --name-only HEAD`(`:1256`), `git diff --cached`(`:1726`)를 실행한다.
  git은 이때 stat cache를 갱신하며 **`.git/index`를 재작성**한다. 그런데 `.git/index`
  해시가 envHash에 포함되어 있었으므로, **MISS가 자기 자신의 트리거를 만든다.**
  실측: 빌드 없이 2분간 `.git/index` 해시 불변(`ea2ae49e…`), `nim c` 1회 후
  `3d44661d…`로 변경. 결과적으로 **한 번 MISS에 들어가면 이후 모든 빌드가 영구 MISS + purge**다.
- **과잉 무효화**: 비의미한 staging(`git add` of a docs file)만으로 envHash가 뒤집힌다.
- **Cold rebuild 결합**: `MISS`는 `rmDir("build/nimcache")` purge를 유발해 629 CC 라인
  (약 45초) 전체 재컴파일로 이어졌다. 위 항목들이 모두 하나의 purge 트리거가 된다.
- **정상 상태 도달 불가**: 무변경 재실행(B warm control)이 629 CC로 측정되었다.
  즉 보고서에 있던 "warm 51 CC" 상태는 이 트리에서 재현되지 않았다.

> **line 기준 주의**: 이 문서의 line 참조는 **변경 전** `config.nims` 기준이다.
> 변경 후 블록이 약 45줄 단축되므로, 구현 확인은 line 번호가 아니라 심볼
> (`hermeticPreBuild`, `envHash`)과 앵커 문자열로 한다.

## §3. Root cause (변경 전)

The NimScript VM has **no stat/mtime operation** — only `readFile`/`writeFile`/
`fileExists`/`dirExists`/`walkDir` are registered. 언어 네이티브로 "트리가 바뀌었나"를
질의할 수 없어, `.git/index` content hash가 *등가 touch check*로 쓰였다.

하지만 `.git/index`는 **VCS staging state이지 compiler semantic state가 아니다.**
이 proxy는 두 방향으로 실패했다: (a) 위 §2의 자가무효화 루프, (b) 캐시 키가
`toolchain/config/source/dependency`의 순수 함수라는 정의에서 벗어난다.

### 3.1 envHash가 통제하던 것과 통제하지 않던 것

`envHash`는 **Axiom 자체 오케스트레이션 도구의 실행 타이밍**만 결정한다:
`MISS` 분기에서 `exec bin/hermetic_build`가 type registry 재생성 → invariant hash →
scope lock → manifest → debt codegen을 수행한다(변경 전 `config.nims:555-562`).

`envHash`는 **컴파일 identity가 아니다.** Nim이 그 일을 소유한다(§6).
이 구분이 이번 변경의 전부다: Axiom은 자기 도구의 재실행 시점만 통제하고,
재컴파일 판정은 컴파일러에 반환한다.

---

## §4. Why FIXED

- 실제 차단 경로는 §-1이 아니라 `repository_surface.json` FROZEN 래칫이었고,
  인간 오너의 승인을 받았다.
- `AXIOM_CI_PRESERVE_CACHE=1`로 dirty-marker를 끄는 CI 완화는 **불완전**했다.
  그 변수는 로컬 개발에는 설정되지 않으므로 로컬에서는 자가무효화 루프가 그대로 돌았다.
  임시 우회는 문제를 해결하지 못했다(§2 실측).
- state-of-the-art hermetic caching의 정답은 지연이 아니라 **입력 콘텐츠 키**다(§7).
- Determinism은 악화되지 않는다 — 키의 비결정성 원인이 제거된다(§6.5).

---

## §5. The change (2026-10-05)

`config.nims` `hermeticPreBuild` envHash 구간에 다음 변경이 적용되었다.
line은 **변경 전** 기준.

| # | 위치 | 변경 |
|---|---|---|
| 1 | `config.nims:442` 삭제 | `envHash &= "git:" & gitHeadRef` — **git HEAD를 cache key에서 제거** |
| 2 | `config.nims:448-457` 삭제 | `.git/index` LOCAL-only dirty-marker 블록 전체 제거 (`AXIOM_CI_PRESERVE_CACHE` 게이트 포함) |
| 3 | `config.nims:419` 직후 추가 | `envHash &= computeSourceTreeHash("src")` — source-tree 콘텐츠 해시 폴드 |
| 4 | `config.nims:465-474` 삭제 | `MISS` 분기의 `rmDir("build/nimcache")` purge 제거 (`AXIOM_CI_PRESERVE_CACHE` 게이트 포함). `[hermetic] Environment changed (MISS)` echo는 유지 |

동일 커밋에서 함께 정정한 것:

| 파일 | 정정 |
|---|---|
| `config.nims:378-385` | "Nim의 content-hash(`.sha1`) 캐시" 설명 → §6의 실제 판정 경로로 교체 |
| `config.nims:394-406` | 캐시 키 설명 갱신(HIT/MISS가 무엇을 생략하는지 — sync_topology와 decision binding은 원래도 무조건 실행) |
| `src/gate/orchestrator/hook/memo.nim:28-30, 91-93` | DEBT#417 마커 위 설명 주석 (pragma 자체는 유지) |
| `config/vendors.nims:85-98` | lease guard 설명 — 플래그가 이제 no-op임을 명시 |

### 5.1 유지된 것

- `computeSourceTreeHash`(정의 `config.nims:352-361`) — 변경 전에도 `config.nims:511`에서
  무조건 계산되어 `BuildSourceHash`에 주입되고 있었다. 변경 후 동일 함수가 envHash 폴드에도
  쓰인다. **신규 helper가 아니며 추가 filesystem 비용도 0이다.**
- `gitHeadRef` 계산(`config.nims:424-441`) — envHash에는 더 이상 쓰이지 않지만
  `config.nims:509`의 `__AXIOM_GIT_HASH__` → `BuildEnvGitHash*` 치환에 **계속 사용된다.**
  HIT/MISS와 무관하게 매 평가마다 live 값으로 실행된다.
- MISS-only `exec bin/hermetic_build` 트리거(`config.nims:555-562`).
- `bin/hermetic_build` 자체 빌드, `sync_topology` stale-binary 가드, decision binding check,
  envHash stamp(temp+mv).

### 5.2 변경 후 envHash 구성

```
config.nims / config/lint.nims / config/strict.nims / axiom.nimble /
tools/hermetic_build.nim / src/gate/topology_spec.nim /
config/gates.manifest.toml / src/generated/build_env.nim.default   → $hash(readFile)
src/gate/manifest.d/*.json (정렬)                                  → $hash(readFile)
src/**/*.nim (정렬, /generated/ 제외)                                → computeSourceTreeHash
proofs/ 존재 여부 → "lean:present"|"lean:absent"
```

즉 **전부 빌드 입력 콘텐츠 또는 그 존재 여부**다. VCS metadata는 하나도 없다.

### 5.3 수렴성(fixed point) — `/generated/` 제외는 우발이 아니라 수렴 조건

MISS 분기의 `bin/hermetic_build` 실행은 `src/generated/build_env.nim`과
`src/generated/type_registry_metadata.json`을 **그 자체로 다시 쓴다.** 이 파일들을
fold에 포함하면 envHash가 MISS 도중 변해 stamp 값과 어긋나고, 다음 `nim c`가
무한 MISS에 빠진다. `/generated/` 제외는 envHash가 고정점임을 보장한다 —
갱신 결과가 갱신 입력에 영향을 주지 않는다. §9-E가 이를 관측한다.

### 5.4 runtime 입력과 컴파일 입력의 분리

`src/generated/type_registry_metadata.json`은 **컴파일러에 보이지 않는 runtime 입력**이다.
`src/core/encoding/type_logic_registry.nim:54`의 `loadFromMetadata`가 `parseFile(path)`로
런타임에 읽는다. 이 JSON은 `staticRead`/`slurp` 의존 그래프에 없고 `.nim.c` 재컴파일
트리거도 아니다. 따라서 envHash에 넣으면 안 된다(§5.3의 수렴 조건 위반).

대신 이 JSON은 src tree의 순수 함수이므로, `src/**/*.nim` 콘텐츠가 바뀌면 envHash가 바뀌고
→ MISS → `bin/hermetic_build`가 JSON을 다시 생성한다. 이것이 MISS-only 트리거가
src tree 기준으로 content-based여야 하는 이유이며, 현재 구현이 정확히 그 형태다.

### 5.5 `AXIOM_CI_PRESERVE_CACHE`의 지위 변화

변경 후 `config.nims`는 이 변수를 **읽지 않는다**(삭제된 두 site가 유일한 reader였음).
변수는 CI 워크플로와 게이트 러너들에 의해 계속 **설정**된다
(`.github/workflows/admission-check.yml:153-157`,
`.github/workflows/runner-pool-acceptance.yml:88-92` 등).

§9의 모든 실험은 **이 변수를 설정하지 않은 상태에서** 수행되었다. 실험 결과가
플래그 없이 성립하므로, config.nims 관점에서 플래그는 no-op임이 관측으로 확인되었다.
정리 대상이며 본 슬라이스 범위 밖이다(§10-R2).

---

## §6. Compiler-owned recompilation

변경 전 `config.nims:378-385`의 주석은 Nim이 "content-hash(`.sha1`) cache"로 변경 모듈만
재컴파일한다고 기술했으나, **이 기술은 정확하지 않다.** Nim 2.2.10의 실제 판정 경로:

### 6.1 `.nim.c` 바이트 비교가 재컴파일 판정의 핵심

`compiler/cgen.nim:2215-2237` `shouldRecompile`:

1. 생성 rope와 기존 `.nim.c`가 **바이트 단위로 다르면** → 기록 후 재컴파일
   (`:2219-2229` `equalsFile(code, cfile.cname)`).
2. 같고 `.o`가 `.nim.c`보다 신선하면(`os.fileNewer`, `:2230`) → 재컴파일 안 함.
3. 그 외 → 재컴파일.

`.sha1`는 이 경로에 개입하지 않는다. `(compiler/pipelineutils.nim:24-26`의
`moduleHasChanged`는 2.2.10에서 `result = true`로 하드코딩되어 fast-path가 죽어 있다.)

### 6.2 `-d:` / `--passC` / `--passL` / `-I` 변경도 `.nim.c`를 바꾼다

`compiler/extccomp.nim:657-664` `getCompileCCmd`가 C 컴파일 명령행 전체를 생성된
`.nim.c`에 임베딩한다(실험 확인: `--passC:-DPROBE_MACRO=1` 추가 시 `.nim.c`의 4번째
라인이 `-DPROBE_MACRO=1`을 포함하도록 변경). 컴파일 옵션이 바뀌면 `.nim.c` 바이트가
바뀌고 → §6.1 → 재컴파일.

### 6.3 `.sha1`의 실제 역할 — external C 소스 전용

`compiler/extccomp.nim:674-689` `externalFileChanged`의 호출자는
`addExternalFileToCompile`(`:691`)로 **외부 C 소스**에 국한된다. 이 머신 실측:
`find build/nimcache -name '*.sha1'` → 10건, 전부 `@ped25519@ssrc@*.sha1`.
Nim 모듈에 대한 `.sha1` sidecar는 존재하지 않는다.

### 6.4 non-`.nim` 입력(`staticRead`/`slurp`)은 컴파일러가 이미 추적한다

`compiler/vmdeps.nim:18-30` `opSlurp`는 읽은 파일마다 가짜 include문을 등록한다.
§9-C2에서 관측: `data/i18n/ko.json`의 **소비되는 키**를 바꾸자 정확히 1개 모듈
(`notion_semantic_mapper`)만 재컴파일되고 digest가 바뀌었다. 복원 시 동일하게 1개,
그 다음 빌드에서 0으로 복귀했다.

### 6.5 Determinism note

키에서 VCS staging state가 빠졌으므로 **결정성이 개선**되었다. 동일 트리·동일 도구체인·동일
config/content는 예전보다 더 넓은 집합에서 동일한 `envHash`를 낸다. 동일 입력 → 동일 digest의
근거는 `std/hashes` `hash()`의 inter-process 결정성 실험(`config.nims:398-399` 주석)에 있다.

---

## §7. Factorization (industry context)

State-of-the-art hermetic caching (Bazel, Gradle, rules_rust content-addressed artifacts):
the cache key must be a pure function of the **inputs** (toolchain + config + source +
dependencies). VCS workspace state (`.git/index`, mtimes) is orthogonal and MUST NOT be
part of the key.

**2026-10-05 갱신.** 실제 구현은 이 원칙을 따른다: git HEAD도 키에서 빠지고,
`src/**/*.nim`의 콘텐츠 해시가 그 자리를 차지한다. `AXIOM_CI_PRESERVE_CACHE`로 CI에서만
끄는 방식은 조건부 제외 그 자체가 content-addressing이 아니었다. 이제 예외가 없다.

단, factorization의 *범위*는 §6이 정한다: Nim이 컴파일 identity를 소유하므로
Axiom의 envHash는 그 **하위**에 있는 오케스트레이션 도구의 실행 트리거다. 두 키를
하나로 취급하지 않는다.

---

## §8. Historical — nimcache purge ownership (2026-10-04 기록, 2026-10-05 폐기)

> **Status: HISTORICAL.** 이 절이 기술하는 `rmDir("build/nimcache")` purge는
> 2026-10-05 변경으로 **코드에 더 이상 존재하지 않는다**(§5-4). 아래는 그 quirk이
> 왜 존재했었고 왜 제거되었는지에 대한 기록이며, 현재 시스템의 동작을 기술하지 않는다.

### 8.1 `nimcacheDir()` cannot identify the cache owner

NimScript의 `nimcacheDir()`는 컴파일러가 해석한 nimcache를 읽지만, 실제로 유효한
`--nimcache:` 의 대용이 되지 못한다: `--nimcache:PATH`만 주면 `PATH`,
`switch("nimcache", PATH)`만 주면 `PATH`, **둘 다 주면 VM은 `config.nims`의 값을 보고하면서
객체는 명령줄 위치에 떨어진다.** 이 저장소는 항상 per-mode `switch("nimcache", ...)`를
설치하므로(idempotent-nimcache guard) VM은 명령줄 override를 조용히 가린다.

### 8.2 Shared-parent purge is a concurrency defect

고정 부모 `build/nimcache`를 재귀 purge하는 중 형제 컴파일이 돌면 그 캐시가 컴파일 도중
삭제된다. 2026-10-04 `verify-contract` 병렬 fan-out에서
`ld: cannot find build/nimcache/verify-contract-release-e2e/@<mod>.nim.c.o`로 관측되었고
네 게이트가 함께 실패했다(직렬 baseline은 통과). 이는 verification semantics 결함이 아니라
공유 가변 빌드 상태다.

### 8.3 DEBT#481 — root cause removed at the root

`data/debt_registry.json`의 DEBT#481 등록 근본원인은 정확히 이 purge다. 2026-10-04의 완화는
fan-out을 purge 트리 밖(`build/nimcache-verify-contract/...`)으로 옮기는 **격리**였고
— symptom 위치의 처리였다. 2026-10-05 변경은 **purge 자체를 삭제**했다. 트리거 조건과
파괴 행위가 모두 사라졌으므로 같은 경로의 재발은 구조적으로 불가능하다.

DEBT#481은 `Makefile`의 공유 `-o:bin/ax` writer 등 다른 잔여를 여전히 가지므로,
**이 절은 DEBT#481의 종결 근거가 아니다.**

### 8.4 Lease guard — 후속 정리 후보 (본 슬라이스에서 제거하지 않음)

`config/vendors.nims`의 lease guard는 `.axiom/cache/nimcache_leases/`에 점유를 등록하고,
다른 live build가 namespace를 잡고 있으면 purge를 yield했다
(`AXIOM_CI_PRESERVE_CACHE` 재사용 — purge 직전의 유일한 veto).

purge 삭제로 이 장치는 **목적 상실** 상태다. 특히 `config/vendors.nims:120`의
`putEnv("AXIOM_CI_PRESERVE_CACHE", "1")`은 이제 config.nims에 도달하는 reader가 없다.
삭제하지 않은 이유: (a) `config/vendors.nims`는 `config.nims`와 다른 제어 표면이며
제거는 별도 승인 슬라이스의 사안, (b) 이 guard가 의존하는 NimScript 동작 가정 두 개
(`staticExec`의 CWD = include 파일 디렉터리, `config.nims` 3중 평가에 대한 `$PPID` 키잉)는
여전히 사실이며 다른 곳에서 재사용될 여지가 있다. **후보 등록만 한다.**

---

## §9. Verification (2026-10-05 실측)

브랜치 `fix/config-nims-envhash-content-identity`, HEAD 기준선 `2530e1b9f`,
Nim 2.2.10 `[Linux: amd64]`. 산출물은 prod `bin/ax`를 건드리지 않기 위해
`build/v1probe/ax`로 지정했다. CC 라인 계수는 `nim c --hints:on` 출력의
`grep -c "CC:"`(`compiler/lineinfos.nim:216` `hintCC`).
**모든 실행에서 `AXIOM_CI_PRESERVE_CACHE`를 설정하지 않았다**(§5.5).

| ID | 명령 | 관측값 | 판정 |
|---|---|---|---|
| A 콜드 기준선 | `rm -rf build/nimcache/debug && nim c --hints:on -o:build/v1probe/ax src/cli/main.nim` | 45.7s · **CC 629** · purge 0 · MISS · digest `b80d952e38d15470` | 기준선确立 |
| B 무변경 재실행 (대조군) | 동일 명령 재실행 | 33.6s · CC 43 · **purge 0** · HIT · digest `b80d952e…` | purge 없음 |
| **B2 비의미 편집 + `git add`** | `docs/evidence/topology_part_stale.md`에 줄 추가 → `git add` → 빌드 | 27.7s · **CC 0** · **purge 0** · **HIT** · digest `b80d952e…` (동일) | **PASS — 핵심 조건** |
| B3 HEAD만 이동 | `git commit --allow-empty --no-verify` → 빌드 | 28.6s · CC 4 · purge 0 · **HIT** · digest `685366a0…` (변화, §10-R3) | PASS (아래 해석) |
| B4 복원 | `git reset --soft HEAD~1`, 문서 복원, unstage → 빌드 | 32.8s · CC 47 · purge 0 · HIT · digest `b80d952e…` (복귀) | PASS |
| C 의미적 `.nim` 편집 | `src/cli/version.nim:28`의 `"v"` 리터럴 → `"vPROBE"` | 32.8s · CC 45 · purge 0 · MISS · digest `14b84acf…` (변화) | PASS |
| **C2 소비되는 비-`.nim` 입력** | `data/i18n/ko.json`의 `gates.sieve.name` 변경(실제 소비 키) | 27.6s · **CC 1** · HIT · digest `4534e090…` (변화) | **PASS — false reuse 0** |
| C2 복원 | 원본 복원 → 2회 빌드 | CC 1 → **CC 0** · digest `b80d952e…` (복귀) | PASS |
| D 전체 복원 | C의 `.nim` 편집 원복 → 빌드 | 30.5s · CC 45 · purge 0 · MISS · digest `b80d952e…` (복귀) | PASS |
| E 수렴성(고정점) | C2 복원 후 연속 빌드 2회 | 두 번째 빌드 CC 0 · MISS 재발 없음 | PASS |

### 9.1 변경 전 대조 (같은 프로토콜, 변경 전 코드)

| ID | 관측값 | 판정 |
|---|---|---|
| A 콜드 | 45.1s · CC 629 · digest `90c4b344e67050d8` | — |
| B 무변경 재실행 | 38.9s · **CC 629** · **MISS + `Clearing build/nimcache`** | **FAIL** — 무변경인데 전체 재컴파일 |
| B2 `git add`(무변경 파일, no-op) | 45.3s · CC 629 · MISS + purge | FAIL |
| B3 unstage | 45.5s · CC 629 · MISS + purge | FAIL |

무변경 재실행이 CC 629 + purge였다. 자가무효화 루프(§2)의 직접 증거이며,
보고서의 "warm 51 CC"가 이 트리에서 재현되지 않았던 이유다.

### 9.2 B3 해석 — digest 변화는 결함이 아니다

`bin/ax`는 커밋 해시를 **임베딩**한다(`BuildEnvGitHash*`).
`src/infrastructure/gate_signing/proof_verifier.nim:41`은 이 값을 증명 서명 identity에
사용하므로, HEAD 이동 시 바이너리가 바뀌지 않으면 오히려 **증명 identity가 stale**해진다.
관측된 CC 4는 `build_env.nim` → `constants.nim` import 체인만 재컴파일한 것으로,
purge 0건이다. 즉 **캐시는 무효화되지 않았고(CC 4 ≪ 629), digest 변화는 설계된 상수 갱신**이다.

### 9.3 C2 설계 정정 기록 (중요)

첫 C2 시도는 `data/i18n/ko.json` 최상위에 **소비되지 않는** 키를 추가했다. 그 키를 읽는
코드가 없으므로 codegen이 안 바뀌는 것이 정상이며, CC 0은 false reuse가 아니라
**실험 설계 결함**이었다. 소비 키(`gates.sieve.name` — `src/ui/notion_semantic_mapper.nim:29`
의 `staticRead` 소비처)를 변경하자 정확히 1개 모듈이 재컴파일되었다.
이 기록은 "캐시가 아무것도 안 한다"는 잘못된 결론을 내리는 것을 막기 위한 것이다.

---

## §10. Residual risk

### R1 — 손상된 `.o` 재사용 (purge 삭제로 감수하는 위험)

`compiler/cgen.nim:2230`은 `.nim.c`가 바이트 동일할 때 `os.fileNewer(obj, cfile)`로
폴백한다. 즉 `.o`가 `.nim.c`보다 mtime상 신선하면 **내용이 손상돼도 재사용된다.**

`rmDir("build/nimcache")` purge는 이 위험에 대한 **거친 방어**였고 — 결과적으로
"캐시 삭제"라는 수단이지 정합성 증명이 아니었다. 이 방어는 content-addressed 키(§7)로
교체하면서 **의도적으로 포기**한다. 교체 근거: §6.1 — 정상 경로에서 `.o`는 `.nim.c`가
바뀌면 함께 재컴파일된다. 위험은 **비정상 경로**(디스크 오류, 강제 종료, 외부 도구의 부분
삭제)에만 존재한다. 복구는 `rm -rf build/nimcache` one-shot이며, 자동 복구 로직은
이 문서가 승인하지 않는다.

### R2 — `AXIOM_CI_PRESERVE_CACHE` no-op (§5.5)

변수는 계속 설정되지만 `config.nims`에서 아무것도 하지 않는다(§9는 플래그 없이 수행되었다).
"캐시 보존" 수단으로 이 변수를 인용하는 서술이 여러 곳에 남아 있다. 정리는 후속 슬라이스 사안.

### R3 — HEAD 이동만 있는 경우의 product binary 재링크 (§9.2)

HEAD만 움직이고 `src`/`config` 내용이 동일하면 `build_env.nim`의 `BuildEnvGitHash*`가
live 값으로 갱신되고(`config.nims:509`), 그 import자만 재컴파일되어 digest가 바뀐다.
이는 증명 서명 identity(`proof_verifier.nim:41`)를 최신 상태로 유지하기 위해 **필요한** 동작이다.

### R4 — 정리 안 된 잔여

`config/vendors.nims` lease guard(§8.4)와 DEBT#481의 `Makefile` 잔여는 이 슬라이스에서
닫히지 않았다. §8.2의 "shared-parent purge" 불변식은 purge 부재로 성립하지만,
**guard 코드 자체가 남아 있다**는 사실은 별도 사안이다.

### R5 — 정리 안 된 서술

`docs/agents/constitution_details.md:62`, `docs/spec/canonical_execution_semantics.md:134`,
`Makefile:794`가 여전히 변경 전 동작을 서술한다. 본 커밋에서 정정 대상이었으나
surface·소유권 범위를 넘지 않기 위해 **후속 슬라이스로 남긴다.** 목록:
`docs/agents/constitution_details.md:62`(§0.5b 포인터 — envHash의 `.git/index` 설명),
`docs/spec/canonical_execution_semantics.md:113,121,134`(`.git/index` 선례 인용),
`Makefile:794`(AXIOM_CI_PRESERVE_CACHE = "hermetic rmDir 회피 + .git/index MISS 제거").
`docs/reports/*`, `docs/history/*`는 시점 기록이므로 의도적으로 손대지 않는다.

### R6 — envHash skip이 src 편집 후 재생성을 건너뜀 → stale `BuildSourceHash` (2026-11-04 관측)

`src/**.nim` 편집 후 `make build`를 실행해도 `hermeticPreBuild`의 envHash skip이
`bin/hermetic_build` 재실행을 건너뛰어 `src/generated/build_env.nim`이 재생성되지
않았다(실측: 편집 후 2회의 `make build`에서 build_env.nim mtime·내용 불변,
`BuildSourceHash`가 낡은 값 유지). 그 결과 `bin/ax`는 낡은 해시를 박고 컴파일되고,
첫 `ax prove`가 즉시 `[FATAL] Engine source/source mismatch (SourceCoherence
FAIL) tree=… embedded=…`로 exit 1한다(상태 파일 미생성).

재현·복구(2026-11-04, rwc-pr1 worktree):
1. `src/verification/lean_build_sandbox.nim` 편집 → `make build` →
   `bin/ax prove …` → SourceCoherence FATAL.
2. 복구: `bin/hermetic_build --check-source-hash`(early pass가 build_env.nim을
   재생성) → `make build` → coherence PASS(tree==embedded).

검출 갭: `check-build-state-coherence`(Makefile:428)는 GATES_FAST·
PUSH_ADMISSIBILITY 게이트 유니버스 밖이어서 로컬 어드미션 스위트가 이 상태를
잡지 못한다 — 최초 `ax prove` 런타임 FATAL(fail-closed)이 유일한 검출점이며,
CI는 매 빌드가 신선(ci-compile 경로)해 구조적으로 보호된다. 게이트 유니버스
등재는 후속 슬라이스 사안(등재 시 check-push-admissibility-integrity 정합
갱신 필요).

### R7 — `--skipParentCfg/--skipProjCfg`가 config.nims의 nimcache 리다이렉트를 무효화 → 루트 `.nimcache/` (2026-11-05 관측, 동일 슬라이스에서 수정)

`NIM_TOOL_FLAGS`(`Makefile:22`)는 config.nims 로딩을 건너뛰는
`--skipParentCfg --skipProjCfg`를 포함한다. config.nims는 per-mode
`switch("nimcache", "build/nimcache/<mode>")`를 설치하는 유일한 지점이므로(§8.1),
이 플래그 조합으로 컴파일되는 모든 Makefile 툴 타깃(`bin/nimtry` 등)은
**컴파일러 기본 캐시 위치(CWD 상대 `.nimcache/<name>`)로 떨어진다.**
실측(2026-11-05, canonical main `0941720e1`): `make check-arch`가 루트에
`.nimcache/nimtry/`(모듈 지문 `*.nim.json` — 컴파일 캐시)을 생성했고
`bin/validate_root_manifest`가 `FAIL: .nimcache forbidden`으로 이를 차단했다.
`bin/build_all_gates`는 자체 `--nimcache:build/nimcache_pool`
(`tools/build_all_gates.nim:30,52`)을 지정하므로 무오염 — 동일 우회가 두 경로에서
다른 결과를 낸 이유다. pre-push 게이트 목록(PUSH_ADMISSIBILITY_GATES)에
check-arch가 없어 PR-1 검증에서 이 경로가 실행되지 않았고, P5 작성자별
재생성 시험이 최초로 관측했다(검증 설계의 의도된 동작).

수정(2026-11-05, `workstream/nimcache-tool-redirect`): `NIM_TOOL_FLAGS`에
`--nimcache:build/nimcache/tools` 추가 — 단일 정의점에서 해당 변수를 소비하는
모든 툴 컴파일 타깃을 한 번에 교정한다. `make clean-cache`가 `build/nimcache/`
전체를 제거하므로 새 캐시 루트도 수명 주기에 포함된다. Makefile은 envHash
입력(§5.2)이 아니므로 `BuildSourceHash`·코히어런스에 영향이 없다.

---

**Status**: `FIXED` — content-addressed key로 교체(git HEAD + `.git/index` 제거,
src tree hash 추가, nimcache purge 삭제). §9 관측표는 본 변경과 동일 세션에서 실측.
| **Last update**: 2026-11-05 (R7 추가 — NIM_TOOL_FLAGS nimcache 리다이렉트)
| **Registry**: `data/debt_registry.json` id `DEBT#417`, resolution `WONT_FIX` → `FIXED`,
status `open` → `closed`
| **Files**: `config.nims` (`hermeticPreBuild` envHash fold 및 `MISS` 분기 —
`gitHeadRef` 계산과 `__AXIOM_GIT_HASH__` 치환은 유지),
`config/vendors.nims` (lease guard 주석 — 장치 자체는 §8.4대로 유지),
`src/gate/orchestrator/hook/memo.nim` (DEBT#417 마커 주석),
`data/debt_registry.json` (DEBT#417, DEBT#481 참조)
