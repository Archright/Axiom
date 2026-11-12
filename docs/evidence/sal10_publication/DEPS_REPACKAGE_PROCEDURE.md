# deps.tar.gz 라이선스 고지 삽입 — 재패키징 절차서

**상태**: 절차 문서(조사 완료). **재패키징 미실행** — 실행은 이력 재작성(cutover) 이후 Gate 3 PR 시점으로 유보(§6).
**목적**: 공개 후 아카이브를 단독으로 내려받은 사람에게 라이선스 고지가 전달되도록, 패키지별 라이선스 전문을 `deps.tar.gz` **내부에** 삽입하고 MANIFEST를 재생성한 뒤 `bash bsec/replay.sh verify` → exit 0으로 원장 폐쇄를 증명한다(설계 원칙: 저장소 루트 LICENSE만으로는 불충분).
**근거**: `docs/evidence/sal10_publication/B1_third_party_inventory.md` §1-C·§4-3(재패키징 결정), 스테이징 `THIRD-PARTY-NOTICES.md` §5(재패키징 후 상태 서술), `bsec/README.md` §"MANIFEST 재생성"(재생성 파이프라인 규정).
**조사 방법**: 전 수치·명령 실측(2026-11-05, HEAD `a874a6003e`). 저장소 읽기 전용, 임시 추출은 /tmp 한정 후 전부 삭제. 아카이브 재구축(바이트 동일 재현 실증)은 결정론 파라미터 확정을 위한 /tmp 조사로서, 저장소 파일·아카이브는 무변경.

---

## 1. 현재 아카이브 인벤토리 (실측)

### 1.1 기본 정보

| 항목 | 값 |
|---|---|
| 경로 | `experiments/act2-wp-toml-b1-input-integrity/bsec/offline/deps.tar.gz` |
| 크기 | 128,779 bytes |
| sha256 | `b9acda955d0de1504acf3545f3b58ad268b64be271df78a8696d80316839e223` |
| 생성 | 커밋 `4255ec7de` (2026-10-11, "archive bulk evidence under GitHub's 300-file diff limit" — 777→293 파일, 9개 결정론 tarball화). 커밋 메시지가 생성 플래그 문서화: `tar --sort=name, --owner=0 --group=0 --numeric-owner --mtime fixed, gzip -n; all 9 verified byte-identical on rebuild` |
| 구조 | 90 엔트리 = 디렉터리 12 + 파일 78 (B1 §1-C "90 엔트리"와 일치) |

### 1.2 패키지별 구성 (실측 계수)

| 패키지 | 엔트리 | 디렉터리 | `.nim.vendored` | 기타 파일 | 라이선스 고지 현황 |
|---|---|---|---|---|---|
| `faststreams-0.5.2` | 16 | 2 (`faststreams/` 등) | 13 | `nimblemeta.json` 1 | 인라인 헤더 없음(원본이 LICENSE 파일 표기 방식 — B1 §1-C) |
| `serialization-0.5.4` | 13 | 3 (`serialization/`, `serialization/testing/`) | 9 | `nimblemeta.json` 1 | 1개 파일 인라인 이중 헤더 보유(실측) |
| `stew-0.5.0` | 61 | 7 (`keyed_queue/`, `ranges/`, `shims/`, `sorted_set/`, `windows/` 등) | 53 | `nimblemeta.json` 1 | 31개 파일 인라인 이중 헤더 보유(실측) |

- 실측 합계: 파일 78(= 13+9+53 `.nim.vendored` + `nimblemeta.json` 3) + 디렉터리 12 = 90 엔트리.
- 참고: B1 §1-C "(13/10/56 .nim)" 및 스테이징 `THIRD-PARTY-NOTICES.md` §5 "13/10/56 files"는 계수 기준 차이가 있다(실측 .nim.vendored는 13/9/53, 파일 총수는 14/10/54). 본 절차는 실측값 기준.
- **아카이브 내 라이선스 전문 0건** — `LICENSE-APACHE`/`LICENSE-MIT` 미동봉(`nimblemeta.json`만 동반; nimblemeta에는 `license` 필드 없음 — 실측). 인라인 헤더를 가진 파일은 "Licensed under either of * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE)) * MIT license ([LICENSE-MIT](LICENSE-MIT))" 형태로 **존재하지 않는 파일을 참조** — 이것이 본 재패키징이 해소하는 갭.

### 1.3 tar/gzip 메타데이터 (전 엔트리 균일 — 재생성 파라미터의 근원)

| 항목 | 값 (실측) |
|---|---|
| uid/gid | `0/0`, numeric owner |
| 모드 | 파일 78개 `-rw-rw-r--` (0664), 디렉터리 12개 `drwxrwxr-x` (0775) |
| mtime | 전 엔트리 epoch `1767225600` = 2026-01-01 00:00:00 UTC (`tar -tvz`는 KST 09:00으로 표시) |
| gzip 헤더 | `1f 8b 08 00 00000000 00 03` — FLG=0, **MTIME=0(`gzip -n`)**, XFL=0(기본 압축 레벨 6), OS=3(Unix) |
| 엔트리 정렬 | `--sort=name` (패키지순 f→s→s, 패키지 내 디렉터리 우선 재귀 정렬) |

**재현 실증(조사, /tmp)**: 기존 아카이브를 /tmp에 추출 후 아래 명령으로 재구축 → sha256 `b9acda955…` **바이트 동일**:

```bash
tar --format=gnu --sort=name --owner=0 --group=0 --numeric-owner \
    --mtime='@1767225600' -cf out.tar faststreams-0.5.2 serialization-0.5.4 stew-0.5.0
gzip -n -c out.tar > deps.tar.gz
```

- `--format=ustar`, `--format=pax`은 **불일치**(실측) → GNU 포맷 필수.
- `--mtime='2026-01-01 00:00:00'`(문자열, 로컬 타임존 해석)은 KST에서 불일치(실측) → **`@epoch` 형식 필수**.
- 실측 환경: GNU tar 1.35, gzip 1.12, coreutils 9.4, bash 5.2.21.

### 1.4 패키지 → 라이선스 매핑 (업스트림 핀 원문 실측)

3종 전부 status-im 계열, **Apache-2.0 OR MIT**, © Status Research & Development GmbH. 핀은 아카이브 내 `nimblemeta.json`과 `bsec/offline/deps/identities.tsv`(신원 = vcsRevision)에 기록:

| 패키지 | 버전 | vcsRevision (핀) | 라이선스 원문(핀 커밋에서 실측 취득) |
|---|---|---|---|
| faststreams | 0.5.2 | `059bc2f52546ac14b583639c33372c14b1d46fa3` (status-im/nim-faststreams) | `LICENSE-APACHEv2` sha256 `ab0af3ce8ab22189cb875b657461ff185b0c8b0738d2baa830b7a3e5de1cdaac` (11,364 B) · `LICENSE-MIT` sha256 `575aa5d3809bdc35ae7ff6d068675e9cb3b494f9eb3f017aa71aa38576c56749` |
| serialization | 0.5.4 | `b5473564e80a4908cf6c5a038e4c4a6ca7de2223` (status-im/nim-serialization) | 〃 (3종 전부 바이트 동일 — 실측) |
| stew | 0.5.0 | `4382b18f04b3c43c8409bfcd6b62063773b2bbaa` (status-im/nim-stew) | 〃 |

- `LICENSE-MIT` 본문: "The MIT License (MIT) / Copyright (c) 2018 Status Research & Development GmbH / …" (무수정 원문).
- `LICENSE-APACHEv2` = 표준 Apache 2.0 전문.

### 1.5 스테이징 `LICENSES/` 대조 (실측 — 중요 정정 사항)

| 스테이징 파일 | sha256 | 업스트릭 핀 원문 대조 |
|---|---|---|
| `Apache-2.0.txt` (11,249 B) | `a0c597304efed32edd7efa2e3b3cb3af14c376ec090c96cda652f4d1bc584694` | **바이트 불일치** — diff 86줄 전부 §4b·§6 등 특정 절의 들여쓰기 폭 차이(3↔6 공백). 조문 자체는 동일하나 byte-exact 아님 |
| `MIT.txt` (1,129 B) | `807880b2e012231f32a8683d2b5f282bbcf042755774ec038fe90d4f2b0d33ee` | **저작권자 불일치** — "Copyright (c) 2018 Eugene Kabanov (nimcrypto)"·"Copyright (c) 2015 niv (ed25519.nim bindings)". status-im 패키지의 MIT 원문("© 2018 Status Research & Development GmbH")이 아님. 이 파일은 Axiom 저장소 루트 `LICENSES/`용(nimcrypto·ed25519 고지)으로 작성된 것 |
| `Zlib.txt`, `CC-BY-4.0.txt` | — | 본 아카이브 3패키지와 무관(vendor/ed25519, docs/spec PDF용) |

**결론(절차 규약)**: 과제 조건 "텍스트는 스테이징 LICENSES/에서, **각 패키지 실제 라이선스와 일치해야 함**"의 두 축이 충돌한다 — 스테이징 Apache-2.0.txt는 공백 변형, MIT.txt는 저작권자 자체가 다르다. **"실제 라이선스와 일치"가 구속 조건이므로 아카이브 삽입본은 업스트릭 핀 커밋의 바이트 정확 원문**(§1.4)을 사용한다. 핀 커밋 SHA로 누구나 동일 바이트를 검증할 수 있어 결정론·감사 가능성이 확보된다. 스테이징 `LICENSES/`는 저장소 루트 고지(`THIRD-PARTY-NOTICES.md` §3 등) 용도로 그대로 두며, 아카이브 삽입과는 원문 소스를 구분한다.
**삽입 파일명 규약**: `LICENSE-APACHE`·`LICENSE-MIT`(패키지 루트에). 근거: ① 아카이브 내 인라인 헤더의 상대 참조가 `[LICENSE-APACHE](LICENSE-APACHE)`·`[LICENSE-MIT](LICENSE-MIT)`(실측) — 같은 이름으로 삽입하면 참조가 해소됨. ② 스테이징 `THIRD-PARTY-NOTICES.md` §5가 "the repackaged archive ships `LICENSE-APACHE` and `LICENSE-MIT` inside the archive"로 서술(확정된 L2 계획). 업스트림 파일명은 `LICENSE-APACHEv2`이나(내용 = 삽입본과 바이트 동일) 위 2근거에 따라 `LICENSE-APACHE` 명명을 규약으로 쓰고, 그 명명 차이를 THIRD-PARTY-NOTICES에 명시한다.

### 1.6 MANIFEST 결속 구조 (실험 루트 `MANIFEST`, 3,885행 — 재생성 대상)

| 행 | 내용 |
|---|---|
| 26행 | `file bsec/offline/deps.tar.gz b9acda955…` — offline/ 평문 파일로서의 file 행(verify 1단계가 재계산) |
| 330행 | `archive bsec/offline/deps.tar.gz b9acda955…` — 아카이브 자기해시 행(verify 2단계가 재계산) |
| 331–408행 | `member bsec/offline/deps.tar.gz::<멤버경로> <sha256>` **78행, 연속 블록**(archive 행 직후), `LC_ALL=C` 정렬과 일치(실측 SORTED-OK) |

verify의 결속 방식(`replay.sh:243-351`): ① 모든 `file` 행 sha256 재계산 ② 모든 `archive` 행 자기해시 재계산 + 추출 후 모든 `member` 행 대조 + **미기록 멤버/미기록 아카이브/미기록 offline 평문 파일 전부 FAIL**(fail-closed) ③ `verdict_generations.tsv` 대장 체인·git 도메인 게이트(본 변경과 무관 — 대장은 수정하지 않음).

---

## 2. 단계별 절차 (실행: Gate 3 PR 시점)

**작업 디렉터리는 전부 temp dir(`mktemp -d`)** — 저장소 트리에서 직접 조작하지 않는다. 저장소 반영(Step 4)만 Gate 3 PR 브랜치(§2.1 workstream 격리 — main 아님)에서 수행한다.
**전제 도구**: GNU tar 1.35 계열, gzip 1.12 계열, coreutils sha256sum, jq, git(조사 환경과 동일; 타 구현은 §5 참조).

### Step 0 — 라이선스 원문 준비 (업스트림 핀에서, 해시 검증)

```bash
WORK=$(mktemp -d) && mkdir -p "$WORK/pkg"
# 3패키지의 원문은 바이트 동일(§1.4 실측) — 대표 1곳에서 취득 후 해시로 검증
curl -fsSL "https://raw.githubusercontent.com/status-im/nim-faststreams/059bc2f52546ac14b583639c33372c14b1d46fa3/LICENSE-APACHEv2" -o "$WORK/LICENSE-APACHE"
curl -fsSL "https://raw.githubusercontent.com/status-im/nim-faststreams/059bc2f52546ac14b583639c33372c14b1d46fa3/LICENSE-MIT"     -o "$WORK/LICENSE-MIT"
sha256sum "$WORK/LICENSE-APACHE"   # 기대: ab0af3ce8ab22189cb875b657461ff185b0c8b0738d2baa830b7a3e5de1cdaac
sha256sum "$WORK/LICENSE-MIT"      # 기대: 575aa5d3809bdc35ae7ff6d068675e9cb3b494f9eb3f017aa71aa38576c56749
```

- 오프라인 환경이면 사전 확보본을 쓰되 sha256 대조를 생략하지 않는다(핀 커밋 = 결정적 소스).
- 교차 검증(선택): `nim-serialization@b5473564…`, `nim-stew@4382b18f…`에서도 동일 sha256이 나오는지 확인(실측 동일).

### Step 1 — 현재 아카이브 추출

```bash
tar -xzf "<REPO>/experiments/act2-wp-toml-b1-input-integrity/bsec/offline/deps.tar.gz" -C "$WORK/pkg"
# <REPO> = 저장소 루트 절대경로
```

### Step 2 — 패키지별 라이선스 삽입 (패키지 루트, 모드 0664)

```bash
for p in faststreams-0.5.2 serialization-0.5.4 stew-0.5.0; do
  install -m 0664 "$WORK/LICENSE-APACHE" "$WORK/pkg/$p/LICENSE-APACHE"
  install -m 0664 "$WORK/LICENSE-MIT"     "$WORK/pkg/$p/LICENSE-MIT"
done
find "$WORK/pkg" -type f | wc -l   # 기대: 84 (78 + 6)
```

- **모드 0664 명시 필수**: `install -m 0664`(또는 cp 후 `chmod 0664`). umask 기본 0644로 두면 모드가 tar 헤더에 반영되어 기존 멤버 관례(§1.3)와 어긋난다(모드는 아카이브 바이트에 영향, MANIFEST member 해시에는 무영향 — 해시는 내용만).
- 위치·명명 근거는 §1.5. 업스트림 원문 무수정(저작권 표기 그대로 — 제3자 고지 변경 금지).

### Step 3 — 아카이브 재생성 (§1.3 실증 플래그 그대로)

```bash
( cd "$WORK/pkg" && \
  tar --format=gnu --sort=name --owner=0 --group=0 --numeric-owner \
      --mtime='@1767225600' -cf "$WORK/deps.new.tar" \
      faststreams-0.5.2 serialization-0.5.4 stew-0.5.0 )
gzip -n -c "$WORK/deps.new.tar" > "$WORK/deps.tar.gz"
```

- `--mtime`은 반드시 `@1767225600`(@epoch). 문자열 날짜는 타임존 해석으로 불일치(실측).
- 디렉터리 인자 순서는 `--sort=name`이 전체 정렬하므로 결과 무관하나 위 순서 유지 권장.
- **결정론 자체점검**: 같은 명령을 한 번 더 실행해 sha256이 동일한지 확인(2회 빌드 일치).
- 삽입 후 아카이브 엔트리: 90 + 6 = **96** (LICENSE 6개는 기존 패키지 루트 디렉터리에 추가되므로 신규 디렉터리 없음).
- 소스 멤버 불변 확인(선택): 재추출해서 기존 78멤버 내용 해시가 §1.6의 member 행과 동일한지 대조 — Step 5의 MANIFEST 재생성이 이 대조를 자동 수행하므로 생략 가능.

### Step 4 — 저장소 반영 (Gate 3 PR 브랜치에서만)

```bash
# 전제: 비사소 구현은 전용 workstream 브랜치(§2.1) — main source mutation 금지
cp "$WORK/deps.tar.gz" experiments/act2-wp-toml-b1-input-integrity/bsec/offline/deps.tar.gz
```

### Step 5 — MANIFEST 재생성 (bsec/README.md §"MANIFEST 재생성" — 연산자 전용 기록 행위, replay 동사 아님)

```bash
cd experiments/act2-wp-toml-b1-input-integrity
git status --porcelain   # 변경이 deps.tar.gz뿐인지 확인 — 아래 (1) 루프가 모든 file/archive 행을 재계산하므로
```

**(1) file + archive 자기 해시 행 재계산** — README 게재 파이프라인 그대로(26행 file·330행 archive의 해시가 새 아카이브 해시로 갱신됨):

```bash
while IFS=$'\t' read -r kind rel want; do
  case "$kind" in
    '#'*)    printf '%s\n' "$kind" ;;
    file)    printf 'file\t%s\t%s\n' "$rel" "$(sha256sum "$rel" | cut -d' ' -f1)" ;;
    archive) printf 'archive\t%s\t%s\n' "$rel" "$(sha256sum "$rel" | cut -d' ' -f1)" ;;
    *)       printf '%s\t%s\t%s\n' "$kind" "$rel" "$want" ;;  # member 행은 (2)에서만 재생성
  esac
done < MANIFEST > MANIFEST.new && mv MANIFEST.new MANIFEST
```

**(2) member 행 블록 교체** — README 규정("바이트가 바뀐 아카이브에 대해서만 … 전 멤버를 재해시하고 해당 아카이브의 member 행 블록을 정렬해 교체한다")의 구현. member 행 재생성은 README 게재 예시 파이프라인 그대로; 블록 교체는 실측 구조(78행 연속 블록, archive 행 직후 → 331–408행)에 맞춰 기존 블록 위치에 새 84행을 삽입한다:

```bash
a=bsec/offline/deps.tar.gz
tmpd=$(mktemp -d)
tar -xzf "$a" -C "$tmpd"
# member 행 재생성 (LC_ALL=C 정렬).
# [정오판 2026-11-06 — Gate 3 실행 시 발견] 원문은 출력을 "$tmpd/members.new"에 두었다.
# 리다이렉션이 find보다 먼저 파일을 생성하므로 find가 members.new 자신을 열거해
# 85행이 생성되고 MANIFEST에 가짜 member 행이 들어간다(실측). 출력은 tmpd 밖에 둔다.
members="$WORK/members.new"
( cd "$tmpd" && find . -type f | LC_ALL=C sort | sed "s|^\./|$a::|" ) | while IFS= read -r m; do
  printf 'member\t%s\t%s\n' "$m" "$(sha256sum "$tmpd/${m#*::}" | cut -d' ' -f1)"
done > "$members"
wc -l "$members"   # 기대: 84
# 기존 deps member 블록(78행)을 삭제하고, archive 행 바로 뒤(기존 블록 위치)에 새 블록 삽입
awk -F'\t' -v a="$a" -v ins="$members" '
  index($2, a"::")==1 { if (!d) { while ((getline l < ins) > 0) print l; close(ins); d=1 } next }
  { print }
' MANIFEST > MANIFEST.new && mv MANIFEST.new MANIFEST
rm -rf "$tmpd"
```

- 새 member 행의 정렬 위치: 각 패키지에서 `LICENSE-APACHE` < `LICENSE-MIT` < (기존 파일들) — `LC_ALL=C` 바이트 순서('L' 0x4C < 소문자·'n')로 자동 정렬됨.
- member 행은 **파일만** 기록(디렉터리는 멤버 아님 — verify가 `find -type f`로 전수 대조, 실측 구조와 동일).

**(3) 게이트 — 기계적 증명**:

```bash
bash bsec/replay.sh verify    # 기대: "VERIFY RESULT: OK" + exit 0
```

- 로컬에서 exit 0을 얻으려면 subject 체크아웃 필요(§3 참조 — 환경 조건이지 아카이브와 무관). CI는 §4의 bsec-integrity가 자동 수행.

### Step 6 — PR 착지 (하나의 coherent generation)

- 아카이브(`deps.tar.gz`) + `MANIFEST`를 **하나의 커밋**으로 착지(조각 착지 시 중간 커밋에서 verify FAIL 상태가 존재하게 됨 — fail-closed 게이트가 붉게 노출).
- `verdict_generations.tsv` 등 기록 파일(git 도메인)은 **수정하지 않는다** — 본 변경은 bundle·증거 바이트 도메인만 닿는다.
- bsec-integrity required check가 PR merge 커밋에서 재검증(§4).

---

## 3. 검증 명령과 기대 출력 (전·후)

### 3.1 전 (기준선 — 2026-11-05 본 조사 실측 출력)

명령: `cd experiments/act2-wp-toml-b1-input-integrity/bsec && bash replay.sh verify` (실행 약 29초, /tmp 스크래치만 사용 후 자동 삭제)

```
== verify: MANIFEST + ledger chain + subject identity (READ-ONLY, fail-closed) ==
file entries checked: 128
archive checked: bsec/evidence/raw.tar.gz (self + 20 members, full coverage)
archive checked: bsec/link_a_flavor/raw.tar.gz (self + 24 members, full coverage)
archive checked: bsec/link_b_consumer/raw.tar.gz (self + 138 members, full coverage)
archive checked: bsec/offline/deps.tar.gz (self + 78 members, full coverage)
archive checked: followup/contract/raw.tar.gz (self + 296 members, full coverage)
archive checked: followup/defects3/raw.tar.gz (self + 37 members, full coverage)
archive checked: followup/extend/inputs.tar.gz (self + 18 members, full coverage)
archive checked: followup/extend/raw.tar.gz (self + 114 members, full coverage)
archive checked: followup/utf8/raw.tar.gz (self + 18 members, full coverage)
archive checked: followup/valuemodel/raw.tar.gz (self + 1824 members, full coverage)
archive checked: followup/writer/raw.tar.gz (self + 97 members, full coverage)
archive checked: followup/writer_table/raw.tar.gz (self + 1063 members, full coverage)
coverage: bsec/offline/ fully listed; all *.tar.gz listed as archives
VERIFY-FAIL: subject checkout not found: <subject-repo>
ledger: 84 generation events, 82 lineages
VERIFY RESULT: FAILED (fail-closed)
EXIT=1
```

**환경 조건 해석(실측)**: 아카이브·멤버 전수 검증은 전부 통과(12개 아카이브, 3,727 member 행). 유일 FAIL은 로컬에 subject 체크아웃이 없어서다(`replay.sh:144` `SUBJECT="${SUBJECT_REPO:-<subject-repo>}"` — 이 머신에 부재 실측). 로컬에서 exit 0을 재현하려면:

```bash
git clone https://github.com/status-im/nim-toml-serialization <경로>
git -C <경로> checkout 4aa8e2223649fc0837c490a4acfca7b8b1e756f9   # snapshot subject_head 핀(실측)
SUBJECT_REPO=<경로> bash bsec/replay.sh verify   # 기대: VERIFY RESULT: OK, exit 0
```

(CI `bsec-integrity.yml` Step 4가 같은 핀으로 subject를 체크아웃해 이 조건을 항상 충족 — §4.)

### 3.2 후 (재패키징 실행 시 기대)

| 검증 | 명령 | 기대 |
|---|---|---|
| 엔트리 수 | `tar -tzf bsec/offline/deps.tar.gz \| wc -l` | `96` |
| 라이선스 동봉 | `tar -tzf bsec/offline/deps.tar.gz \| grep -c 'LICENSE-'` | `6` (패키지별 `LICENSE-APACHE`·`LICENSE-MIT`) |
| 재구축 결정론 | §2 Step 3 명령 2회 빌드 → `sha256sum` 비교 | 동일 해시 2회 |
| verify | `bash bsec/replay.sh verify` | deps 라인이 `archive checked: bsec/offline/deps.tar.gz (self + 84 members, full coverage)`로 변한 것 외 §3.1과 동일 구조 + `VERIFY RESULT: OK (every recorded hash verified; ledger chain valid; coverage complete)` + **exit 0** |
| judge (CI가 실행하는 2번째 동사) | `bash bsec/replay.sh judge` | verify 게이트 통과 후 `JUDGE: PASS — re-derived verdicts equal the recorded verdicts AND the current generation of every lineage.` + exit 0 (아카이브 내용은 판정 재유도 입력 아님 — 관측·규칙만 사용) |
| MANIFEST 변경 폭 | `git diff -- experiments/act2-wp-toml-b1-input-integrity/MANIFEST` | ① 26행 file 자기해시 ② 330행 archive 자기해시 ③ member 블록 78→84행(기존 78행의 해시는 **한 줄도 불변** + 신규 6행) — 이 외 변경이 보이면 중단·조사(소스 변형 또는 우발 재계산 흡수) |
| run (선택·신뢰 트리 한정, 로컬 재현성) | `bash bsec/replay.sh run` | 빌드·7사례 A/B 바이트 동일 PASS — run은 아카이브에서 `*.nim.vendored`만 `.nim`으로 rename(`replay.sh:664-666`)하여 빌드하므로 LICENSE 파일은 컴파일 대상 아님(`--path` 지정 패키지 루트의 비-.nim 파일; `nimblemeta.json`이 이미 동봉돼 있는 전례와 동일 구조) |

---

## 4. 테스트 영향 (아카이브를 읽는 테스트·게이트 — 저장소 전체 grep 실측)

| 소비자 | 형태 | 통과 조건 / 영향 |
|---|---|---|
| `.github/workflows/bsec-integrity.yml` (job `bsec-integrity`, workflowId 381835906, pull_request + merge_group, **path filter 없음 — 항상 실행**) | **핵심 게이트**. 신뢰(base) 트리의 `replay.sh verify`+`judge`가 candidate(merge) 트리의 MANIFEST·아카이브를 **데이터로만** 검증(2-tree GATE A 구조). `AXIOM_TARGET_TREE=candidate`, `AXIOM_LEDGER_BASE=base.sha`, subject는 핀 SHA `4aa8e22…`로 체크아웃 | candidate 내부 일관성(새 MANIFEST ↔ 새 아카이브, member 84행 전수, 미기록 멤버 0)이 성립하면 PASS. 검증 프로그램 자체(replay.sh)는 base에서 오므로 본 변경이 검증 로직을 건드리지 않음 |
| `bsec/replay.sh` 4동사 | `verify` 직접 소비; `judge`(내부 `cmd_verify` 게이트)·`freshness`(term 4 = `cmd_verify`, `replay.sh:1086-1092`)·`run`(gate 1 = `cmd_verify` + 번들 스테이징) 모두 간접 소비 | 전부 위 일관성 조건으로 통과. freshness의 나머지 term(subject/consumer 핀)은 본 변경과 무관 |
| `tests/unit/test_merge_ruleset_drift_monitor.nim:39-87` | bsec-integrity 워크플로 **신원**(경로·workflowId·check 이름)의 정책 미러 테스트 | 워크플로·정책 파일을 변경하지 않으므로 무영향 (deps.tar.gz는 이 테스트 입력 아님) |
| `config/policy/merge_admission.json` trustSurface (§: `experiments/act2-wp-toml-b1-input-integrity/bsec/replay.sh` 등재) | trustSurface 파일 변경 PR은 자동거부(auto-merge denial) | 본 변경은 trustSurface에 **등재되지 않은** 경로(deps.tar.gz, MANIFEST)만 수정 → 자동거부 사유 없음. 단 required check(bsec-integrity) 통과는 필요 |
| `data/promotions/baseline/baseline.json` | 과거 관측 스냅샷(policyMergeAdmission의 trustSurface 경로 나열 — 관측 기록) | deps.tar.gz 해시를 고정하지 않음 → 무영향 (실측: 해당 파일에 deps.tar.gz/MANIFEST 해시 참조 없음) |
| 해시 고정 외부 참조 | 전역 grep `b9acda955…` 실측 | **0건** — deps.tar.gz sha256을 MANIFEST 밖에 고정하는 참조 없음 (`data/asset_hygiene_baseline.json`, `logs/binary_freshness_manifest.json` 무관 실측). 문서 참조는 비해시 서술뿐: `bsec/JUDGMENT.md:220`(루트)·`bsec/replay.sh:53,656,663`·`docs/evidence/canonical_hygiene_must_restore_2026-11-03.md:57,62`·`docs/evidence/sal10_publication/B1_third_party_inventory.md`·`B2_copyright_report.md:33` |
| `bsec/replay.sh freshness` term 4 | `cmd_verify` 재실행 | MANIFEST↔아카이브 일관성 유지 시 FRESH 유지 (다른 term은 subject·consumer 세계 이동 감시 — 무관) |

**CI 실행 환경 주의(워크플로 헤더 주석 실측)**: hosted `ubuntu-24.04`(jq 내장) 필수 — self-hosted axiom-ci 러너에는 jq가 없어 replay.sh가 fail-closed된다(2026-09-08 실측 기록). 이는 본 변경과 무관하나 검증 재현 시 참조.

---

## 5. 위험·제약

### 5.1 결정론 (재현 가능한 아카이브 바이트)

- 재현 파라미터 6종(전부 실측 확정): **GNU tar 포맷**(`--format=gnu`; ustar/pax 불일치 실측) · `--sort=name` · `--owner=0 --group=0 --numeric-owner` · `--mtime='@1767225600'`(@epoch 필수; 문자열 날짜의 로컬 타임존 해석 불일치 실측 — KST) · `gzip -n`(gzip 헤더 MTIME=0, 기본 압축 레벨) · 멤버 모드 0664/디렉터리 0775 보존(`install -m 0664` 정규화; 모드는 tar 헤더에 기록되어 바이트에 영향, member 내용 해시에는 무영향).
- **도구 버전 의존**: deflate 출력은 tar·gzip 구현·버전에 따라 달라질 수 있다. 실측 재현은 GNU tar 1.35 + gzip 1.12 기준. 재현 주장(바이트 동일)은 "같은 입력 트리 + 같은 도구 버전" 조건부다 — 원문은 어차피 핀 커밋·sha256으로 검증되므로, 재현 불가 환경에서도 아카이브 무결성은 MANIFEST가 보장한다.
- 인자 순서·호스트 타임존·파일 시스템 atime은 영향 없음(`--sort=name`·`@epoch`·자기해시 구조상).

### 5.2 해시 고정 참조

- 갱신 지점은 MANIFEST 3곳뿐(26행 file 자기해시·330행 archive 자기해시·331행부터 member 블록). 누락·불완전 시 verify가 즉시 FAIL(sha256 mismatch / unlisted archive member — fail-closed). 외부 고정 참조는 실측 0건(§4).
- **주의 — MANIFEST 재생성 루프의 전행 재계산**: §2 Step 5(1)은 모든 file·archive 행을 다시 계산한다. 실행 시점 트리에 다른 변경이 섞여 있으면 그 해시까지 갱신돼 의도치 않은 변경이 장부에 흡수된다 → Step 5 진입 전 `git status --porcelain`으로 deps.tar.gz 외 변경 0 확인, 재생성 후 `git diff`로 §3.2 표의 3곳 변경만 존재하는지 확인.

### 5.3 재생성을 비자발적으로 만드는 요소

- **git 스테이징 경험**: 이 실험 이력에서 `*.sh`·`build/`가 .gitignore에 있어 재현 도구가 누락 착지된 적이 있다(커밋 4255ec7de 메시지). 스테이징 시 변경 경로를 명시한다(`git add experiments/.../bsec/offline/deps.tar.gz experiments/.../MANIFEST`).
- **LFS/바이너리 정책**: `*.gz`가 `.gitattributes` LFS 패턴(`*.pdf *.so *.bin *.png` 4종) 밖이다 — 기존 gzip 5건( deps.tar.gz 포함)이 §0.6b 「패턴 없는 바이너리 형식 추가 금지」 위반 소지로 격리·인간 결정 대기 중(`docs/evidence/canonical_hygiene_must_restore_2026-11-03.md` §4: (a) LFS 전환+패턴 추가 (b) 게이트 baseline 갱신 (c) 명시적 면제 중 택1). 재패키징은 새 gzip blob을 같은 상태로 착지시킨다(문제를 악화하지는 않으나 상속; (a)로 결정나면 절차의 반영·추가 방식이 달라진다).
- **네트워크 의존**: 라이선스 원문 취득(raw.githubusercontent.com)은 실행 시점 온라인을 전제한다. 오프라인이면 사전 확보본 + sha256 대조(§2 Step 0). 핀 커밋 SHA가 소스를 결정적으로 식별하므로 감사 가능성은 유지된다.
- **로컬 verify의 subject 의존**: SUBJECT_REPO 체크아웃이 없으면 로컬 verify는 항상 FAIL(§3.1 — 번들 도메인이 아닌 환경 조건). exit 0 관측은 CI 또는 subject 핀 체크아웃 후에만 가능하다.

### 5.4 라이선스 정합성·법적 제약

- **스테이징 MIT.txt 불일치(실측, §1.5)**: 저작권자가 nimcrypto/ed25519로 status-im 패키지와 다르다. 아카이브에는 절대 그대로 써서는 안 된다 — 업스트릭 핀 원문("© 2018 Status Research & Development GmbH") 사용. 스테이징 Apache-2.0.txt도 공백 변형이라 바이트 불일치(조문 동일). 원문 무수정 원칙: 저작권 표기·연도(MIT "2018" vs 인라인 헤더 "2025" 등 혼재)는 업스트림 상태 그대로 보존한다(제3자 고지 임의 변경 금지).
- **파일명 규약 차이**: 삽입명 `LICENSE-APACHE` ≠ 업스트림 파일명 `LICENSE-APACHEv2`(내용 바이트 동일). 이 규약(헤더 참조·THIRD-PARTY-NOTICES §5 서술과의 일치)을 게시 문서에 명시하여 "무단 개명"으로 오인되지 않게 한다.
- 고지는 아카이브 **내부**에 존재해야 한다는 설계 원칙을 이 절차가 충족한다(패키지 루트에 전문 동봉 → 단독 수령자에게 전달).

### 5.5 절차 무결성

- 본 재패키징은 고지 삽입 + 장부 재생성뿐, 검증 로직(replay.sh)·게이트 구조·판정 기록(verdicts·ledger)은 전부 불변 — verify가 전수 재검증하는 것 자체가 완료 증명(§2.2 "완료는 기계 검증"). 스텁·게이트 우회·극장 요소 없음.
- 조각 착지(아카이브만 커밋) 금지 — 중간 커밋이 fail-closed 붉은 상태로 존재한다(§2 Step 6).

---

## 6. 실행 유보 명시 (→ Gate 3 실행 기록으로 갱신)

- **실행 기록(2026-11-06, Gate 3 PR `work/sal10-gate3`)**: §2 Step 0–6 실행 완료 — 새 아카이브 sha256 `ac5c02c4d7fe5c62013fdc00ae0f384bd203c54a678ed50619021c5ebfda2d71`(2회 빌드 동일·96엔트리·LICENSE 6), MANIFEST member 84행(구 78행 불변), `SUBJECT_REPO` 핀 체크아웃에서 `replay.sh verify` → **VERIFY RESULT: OK·exit 0**(deps: self + 84 members) 실측. Step 5(2) 정오판 1건 반영(위 주석).
- **원문 서술(2026-11-05, 실행 유보 상태로 작성됨)**: 본 문서는 절차서이며 작성 시점에는 재패키징·MANIFEST 재생성·저장소 반영·PR 착지를 전부 실행하지 않았다.
- 실행 시점: 이력 재작성(cutover) 이후 **Gate 3 PR**. 그 시점에 §2 Step 0–6을 순서대로 실행하고 §3.2의 기대 출력과 대조해 기계적으로 폐쇄한다.
- 본 조사는 저장소 읽기 전용(어떤 저장소 파일도 수정·이동·삭제 없음; `git status --porcelain` clean, HEAD `a874a6003e` 확인). /tmp 임시 추출·재구축 실험 잔여물은 전부 삭제 확인(2026-11-05).
- 아카이브·MANIFEST 외에 Gate 3에서 동반 검토할 사항(본 문서 범위 밖 참조): 저장소 루트 `LICENSES/`·`THIRD-PARTY-NOTICES.md` 착지(B1 §4-1~2), docs/spec PDF 판정(B1 §1-D), 스테이징 `MIT.txt`의 용도 구분 명시(§1.5 — 루트 고지용 nimcrypto/ed25519 원문 유지, 아카이브용은 status-im 원문).

---

## 부록 — 조사 증거 명령 (실측에 사용한 대표 명령)

```bash
tar -tzf experiments/act2-wp-toml-b1-input-integrity/bsec/offline/deps.tar.gz | wc -l          # 90
tar -tzf …/deps.tar.gz | cut -d/ -f1 | sort | uniq -c                                          # 16/13/61
tar -tvzf …/deps.tar.gz | awk '{print $1}' | sort | uniq -c                                     # 78×0664, 12×0775
head -c 16 …/deps.tar.gz | od -A x -t x1z                                                       # gzip 헤더 (gzip -n 확인)
awk -F'\t' 'index($2, "bsec/offline/deps.tar.gz::")==1' …/MANIFEST | wc -l                      # 78 (블록 331–408행, SORTED-OK)
git log --oneline --all --follow -- …/deps.tar.gz                                               # 4255ec7de (생성 커밋)
grep -rn "b9acda955d0de150" <저장소 전역>                                                         # 0건 (외부 해시 고정 없음)
grep -rn "deps.tar.gz" --include=… <저장소 전역>                                                  # §4 소비자 목록
# 재현 실증(/tmp): §1.3 명령 → sha256 b9acda955… 바이트 동일; ustar/pax·문자열 mtime 불일치 확인
# 업스트림 원문: raw.githubusercontent.com/status-im/{nim-faststreams,nim-serialization,nim-stew}/<핀>/LICENSE-{APACHEv2,MIT} → §1.4 해시
# 기준선 verify: §3.1 출력 (실행 29초, exit 1 = 로컬 subject 부재 — 번들 도메인 전부 PASS)
```
