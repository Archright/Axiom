# 러너 부트스트랩 B1 — `disable_updates` 적용 기록과 기준선 (2026-10-27)

> **종류**: 실행 증거 + 설정 변경 기록.
> **대상**: GARM scaleset `2` (`ci-axiom-x64`), provider `garm-provider-openstack`, OVH 리전 `SGP1`.
> **권위**: 본 문서는 **기록**이다. 병합 판정 권위는 GitHub ruleset·required checks·merge queue이며 본 문서는 그 판정을 대체하지 않는다 (AGENTS.md §2.3 Authority ≠ Adapter).
> **수치 규약**: 모든 수치는 재도출 명령과 함께 적는다. 재도출하지 못한 값은 **UNKNOWN** 으로 남긴다.

---

## 1. 주장 (Claim)

1. 러너 게스트 부트스트랩 구간(`VM READY → 첫 상태 보고`)은 **B1 적용 이후 실측됐다** — `post_ready` p50 **68.3초**(n=47, §2.3), 독립 창에서 p50 **69.4초**(n=52, §2.3a). 그중 **약 40초가 `gap`**(부팅·cloud-init)이고 소유자는 **UNKNOWN**이다.
   **그러나 B1 "이전" 기준선은 여전히 없다** — OVH VM 삭제로 `updatedAt(READY)`가 소실됐고 모든 관측 창이 B1 적용(06:19:07Z) 이후다(§2.1). 따라서 위 값들은 **상태 기술이며 B1의 효과가 아니다**. B1 이전 값은 `M2_legacy − 42`로 만든 **추정 140초**뿐이다. 근거 등급: 효과 = **UNESTABLISHED**, 현재 상태 = **MEASURED**.
2. 이 배포의 cloud-init은 GARM 기본값에 따라 `package_upgrade: true`(전체 시스템 업그레이드)로 **설정되어 있었다**. 우리가 끄지 않았다. 다만 그 업그레이드가 매 부팅에서 **성공적으로 완료됐는지**는 게스트 로그가 없어 **UNKNOWN**이다.
3. `extra_specs.disable_updates: true`는 이 배포에서 **실제로 배선되어 있다** — provider가 extra_specs를 자기 구조체로 파싱해 cloud-init `package_upgrade`를 끈다. 단 이것이 제거하는 것은 **`dist-upgrade`뿐**이며, `apt-get update`와 `extra_packages` 14종 설치는 **남는다**(§5.1).
4. 적용 결과 `extra_specs` **한 키만** 변경되었고, 보호 필드(`max_runners`·`min_idle_runners`·`runner_bootstrap_timeout`·`image`·`flavor`·`template_id`)는 **불변**이다.

### 명시적 비주장 (Non-claims)

- **효과를 아직 주장하지 않는다.** 본 문서는 변경 *적용* 기록이며, 부트스트랩 감소는 후속 측정으로만 판정한다. 적용 시점까지의 관측은 "N=1 표본"이다.
- **apt 단계의 시간 기여도를 주장하지 않는다.** `VM READY → 첫 sendStatus` 공백 안에 apt가 *포함된다*는 것만 코드로 확정되며, 그 공백 시간의 몇 %가 apt인지는 **UNKNOWN** 이다(§6).
- **이미지 사전 구성을 정당화하지 않는다.** B2는 B1 측정 후 게이트에서만 판단한다.
- **병합 권한·검증 강도를 바꾸지 않는다.** 필수 검사 5종·ruleset·merge queue는 그대로다.
- **`rotate --outdated`를 쓰지 않는다.** `extra_specs` 변경은 `generation`을 올리고, scaleset 인스턴스는 생성 시 `generation`을 복사받지 못하는 upstream 결함이 있어 `--outdated` 필터가 무의미해진다(§7).

---

## 2. 기준선 — 네 축을 분리해서 잰다

`started_at − created_at` 하나를 "부트스트랩"이라 부르지 않는다. 그 값에는 **동시성 상한 대기**와 **러너 프로비저닝**이 함께 들어 있다.

네 축은 **같은 작업 하나의 시간축을 겹치지 않게 나눈 것**이며, 다음 연결식이 성립해야 한다.

```
M1 ≈ M3 + M2 + M4
```

| 축 | 정의 | 단위 | 해석 |
|---|---|---|---|
| **M1** `job_start_latency` | `job.started_at − job.created_at` | 초/잡 | 사용자가 체감하는 전체 작업 대기 |
| **M2** `provisioning_latency` | `vm_ready − garm_instance.created_at` | 초/인스턴스 | 인프라 프로비저닝 (VM 생성 → READY) |
| **M3** `dispatch_latency` | `garm_instance.created_at − job.created_at` | 초/잡 | GARM 인스턴스 생성 **이전** 지연 |
| **M4** `guest_bootstrap` | `job.started_at − vm_ready` | 초/인스턴스 | VM READY 이후 게스트 준비 · 러너 등록 |

> **M2는 M4를 내포한다.** 옛 정의 `M2 = started − instance.created`는 `M4`를 통째로 포함하므로, M4가 줄면 그 정의의 M2도 함께 줄어드는 것이 **정상**이다. 그것을 "표적 오염"으로 읽지 않는다. 본 개정에서 M2를 `vm_ready` 기준으로 교체한 이유가 이것이다.

> **`M3`를 `slot_wait`라 부르지 않는다.** 인스턴스 생성 이전 지연에는 스케일링 판단 · GARM 조정 루프(5초) · API 지연이 함께 들어 있다. "동시성 상한에 막혔다"고 말하려면 그 잡이 실제로 상한에 걸렸다는 **별도 증거**가 필요하다.

> **앵커 규약 (필수).** 네 축을 더하려면 같은 앵커여야 한다. 아래 기준선 표는 **앵커가 서로 다르다** — M1·M3_legacy는 런(`workflow_run.created_at`) 기준, M2_legacy는 GARM 인스턴스 기준이다. 서로 다른 앵커의 값을 한 산술식에 넣지 않는다.

### 2.1 측정값 (merge_group `b19e052e`, 2026-10-27T04:31Z)

**먼저 정의 라벨을 정확히 붙인다.** 아래 M2·M3는 개정 **이전** 정의로 계산된 값이며, 개정된 M2(`vm_ready` 기준)와 **같은 축이 아니다**.

| 축 | 정의 | n | min | p50 | p90 | max | 합계 |
|---|---|---:|---:|---:|---:|---:|---:|
| M1 `job_start_latency` | `started − created` | 21 | 193 | **206** | 437 | 448 | 5,024 |
| M2_legacy | `started − instance.created` | 17 | 172 | **182** | 191 | 195 | — |
| M3_legacy | `instance.created − created` | 17 | 16 | 21 | 259 | 260 | — |
| M4 (추정) | `M2_legacy − 42` | 17 | 130 | **140** | 149 | 153 | — |
| 실제 작업 | `completed − started` | 21 | — | — | — | — | 3,395 |

- M2_legacy 밴드가 172~195초로 좁다 → **프로비저닝+게스트 구간의 합은 결정론적**이다. 큰 변동은 M3_legacy에서 나온다.
- M3_legacy p90 259초는 wave 2의 3건(`closure-deriver`·`trusted-writer-set-pairing`·`attest/build-base-artifacts`)에서 나왔다. 세 잡이 **`max_runners=8` 상한에 막혔다**는 것은 **아직 입증되지 않은 추정**이다 — 상한 대기로 확정하려면 해당 시점의 GARM 인스턴스 수와 잡 큐 길이를 함께 제시해야 한다.
- M4 140초는 **추정**이다. 상수 42초는 정확 분해 표본 `garm-jxd5mf6fvs7u`(push 런)에서 얻은 `OVH created(+10s) → READY(+32s)`이며, M4 정본 정의는 `started − vm_ready`이므로 이 근사는 게스트 구간을 **과대**평가한다.
- **정본 M2·M4 기준선은 사후 복구 불가**다. OVH VM이 이미 삭제되어 `updatedAt(READY)`가 남아 있지 않다. 따라서 새 정의의 기준선은 **이번 merge queue 랜딩에서 새로 측정**한다.

#### 2.1a 정확 분해 표본 1건 — 서로 다른 앵커의 산술 불일치

정확 분해 표본 `garm-jxd5mf6fvs7u`의 구간은 다음 두 값으로 동시에 보고되어 있었다.

| 계산 | 값 |
|---|---|
| 런 생성 앵커: `9.327 + 9.673 + 32 + 135` | **186.0초** |
| GARM 인스턴스 앵커: `started − instance.created` | **176.7초** |

두 값은 모순이 아니라 **앵커가 다른 두 측정**이다. 차이 9.3초는 `instance.created − run.created` 구간이다. **이 표본에서 확정된 것은 `135.000초`(원시값 일치) 단 하나이며, n=1이다.** 이를 M4 p50의 대표값으로 쓰지 않는다.

### 2.2 재도출

```bash
# 잡 원자료
for r in 40450186206 40450186215 40450186240 40450186241 \
         40450186245 40450186253 40450186266 40450186479; do
  gh api "repos/Archright/Axiom/actions/runs/$r/jobs?per_page=100" --paginate
done | jq -s '[.[] | .jobs[]] | unique_by(.id)' > /tmp/b1/jobs.mg.json

# M1/M2/M3/M4 — 개정 정의
python3 - <<'PY'
import json, datetime
p = lambda s: datetime.datetime.fromisoformat(s.replace('Z','+00:00')) if s else None

# GARM 인스턴스: 정확한 created_at (10초 폴링 스냅샷에서 이름별 최초 레코드)
inst = {}
for line in open('/tmp/b1/s1/garm.tsv'):
    r = json.loads(line)
    inst.setdefault(r['name'], r)

# OVH VM: provider_id 로 GARM 인스턴스와 조인. updatedAt 은 전이 시각이 아니라
# "마지막 수정 시각"이므로 READY 최초 관측 시각을 상한으로 쓴다.
vm_ready = {}
for line in open('/tmp/b1/s1/ovh.tsv'):
    r = json.loads(line)
    if r.get('status') == 'READY':
        vm_ready.setdefault(r['id'], p(r['ts']))

rows = []
for j in json.load(open('/tmp/b1/jobs.mg.json')):
    if not (j.get('runner_name') or '').startswith('garm-'): continue
    c, s, e = p(j['created_at']), p(j['started_at']), p(j['completed_at'])
    i = inst.get(j['runner_name'], {})
    ic, pid = p(i.get('created_at')), i.get('provider_id')
    rd = vm_ready.get(pid)
    rows.append(dict(
        m1 = (s-c).total_seconds(),
        m3 = (ic-c).total_seconds() if ic else None,          # instance.created − job.created
        m2 = (rd-ic).total_seconds() if (ic and rd) else None, # vm_ready − instance.created
        m4 = (s-rd).total_seconds() if rd else None,          # job.started − vm_ready
        work = (e-s).total_seconds() if e else None,
    ))

def q(a, f):
    a = sorted(x for x in a if x is not None); k = (len(a)-1)*f
    lo = int(k); hi = min(lo+1, len(a)-1)
    return a[lo] + (a[hi]-a[lo])*(k-lo)
for label in ('m1','m3','m2','m4','work'):
    v = [r[label] for r in rows]
    print(f"{label.upper():5s} n={len([x for x in v if x is not None]):2d} "
          f"p50={q(v,.5):6.1f} p90={q(v,.9):6.1f} max={max(x for x in v if x is not None):6.1f} "
          f"sum={sum(x for x in v if x is not None):8.1f}")
# 연결식 검증: 같은 조인을 가진 행에서만
for r in rows:
    if None not in (r['m1'], r['m2'], r['m3'], r['m4']):
        print(f"link {r['m3']:+7.1f} + {r['m2']:+7.1f} + {r['m4']:+7.1f} = "
              f"{r['m3']+r['m2']+r['m4']:7.1f}  vs M1 {r['m1']:7.1f}  "
              f"Δ={r['m1']-(r['m3']+r['m2']+r['m4']):+.1f}")
PY
```

**한계 — M2·M4의 구간 경계는 ±10초 오차를 갖는다.** OVH v2 `updatedAt`은 문서상 *"Last modification date"* 이지 상태 전이 시각이 아니며, OpenStack `updated` 필드도 특정 전이 시각을 보장하지 않는다. 따라서 `vm_ready`는 **READY 최초 관측 시각(10초 폴링 상한)** 을 쓰고, M2는 하한 쪽, M4는 상한 쪽으로 편향된다. 폴링 간격을 줄이지 않는 한 이 오차는 줄지 않는다.

**가산성 주의**: M1·M3는 **잡별** 값이고 M2·M4는 **인스턴스별** 값이다. 인스턴스 1대가 잡 1개를 받는 ephemeral 구성에서는 1:1이지만, 조인이 실패한 행(`provider_id`가 아직 `null`인 경우)은 **버리지 않고 UNKNOWN으로 센다**. 잡별 대기 시간의 **합**은 큐 벽시계 시간보다 크다(작업들이 동시에 기다리므로 겹친다) — 이를 `wall_partition`에 넣지 않는다.

### 2.3 B1 적용 **이후** 구간의 단계 분해 (게스트 준비의 실제 구성)

두 개의 독립 관측 창을 합산했다 — `s1` 06:23:36~06:50:17Z, `s2` 06:50:26~07:07:16Z (둘 다 B1 적용 06:19:07Z **이후**). 폴링 시점에 이미 `READY`였던 **좌측 절단** 인스턴스는 M2/M4 계산에서 제외했다(첫 관측이 `READY`면 `vm_censored`).

| 단계 | 정의 | n | p50 | max |
|---|---|---:|---:|---:|
| `gap` | `vm_ready` → 첫 `sendStatus` | 47 | **39.4** | 52.5 |
| download | 러너 도구 다운로드 | 47 | 8.3 | 8.4 |
| extract | 압축 해제 | 47 | 4.4 | 5.4 |
| **installing dependencies** | `installdependencies.sh` | 37 | **16.1** | 22.6 |
| configure | 러너 구성 | 37 | 0.5 | 0.6 |
| JIT | JIT 자격증명 | 36 | 2.7 | 2.8 |
| unit → enable | 서비스 등록 | 34 | 1.1 | 1.3 |
| **post_ready 합계** | `vm_ready` → 등록 완료 | 47 | **68.3** | 86.3 |

해석 — **여기서 결론을 내지 않는다**:

- 게스트 준비는 **68초** 규모이고, 그중 **39초(57%)가 `gap`** 이다. `gap`에는 부팅·cloud-init·`apt-get update`·`extra_packages` 14종 설치·(`disable_updates` 이전에는 `dist-upgrade`)·`unattended-upgrades`(§6.3)가 함께 있고 **콜백이 구조적으로 없다** → **소유자 UNKNOWN**.
- 이미지 베이킹이 줄일 수 있는 상한은 `download + extract + deps + configure + JIT + unit` ≈ **33초**다. `gap` 39초는 이미지 베이킹으로 줄지 않는다.
- **B1의 효과는 이 표로 판정할 수 없다.** B1 이전의 단계 분해는 **없다**(s1이 시작된 06:23:36Z도 B1 적용 이후다). §2.1의 M4 140초는 `M2_legacy − 42`로 만든 **추정**이며 다른 앵커를 쓴 값이다. 따라서 *"B1이 게스트 준비를 140초 → 68초로 줄였다"* 는 서술은 **측정된 사실이 아니다.**

#### 2.3a 독립 표본 — PR #1110의 merge_group 창 (08:09–08:19Z)

위 표와 **다른 실행 창**에서 같은 분해가 재현되는지 확인했다(폴링 창 `s2`의 08:09 이후 구간, n=52). 값은 독립적이지만 **결론은 같다**.

| 단계 | n | p50 | max |
|---|---:|---:|---:|
| `gap` | 52 | **39.7** | 52.5 |
| download + extract + deps | 52 | 29.3 | 35.7 |
| configure + JIT + unit | 48 | 4.3 | 4.9 |
| **post_ready 합계** | 52 | **69.4** | 86.3 |

- 08:14:27에 시작한 `admission-gate` 러너(`garm-jy8qxi2vwe5p`)의 `status_messages`는 **8단계가 빠짐없이 정상 순서**로 남았다: `downloading tools`(08:13:41.34) → `extracting runner`(+8.5) → `installing dependencies`(+4.6) → `configuring runner`(+21.4) → `downloading JIT`(+0.5) → `generating systemd unit`(+2.6) → `enabling runner service`(+1.0) → `runner successfully installed`(+1.8). 러너 sw는 **v2.338.0 고정**, 총 40.5초. 단계 생략·캐시 히트에 의한 건너뛰기는 **없다**(C-5).
- **측정 한계(음수 구간)**: `garm-jy8qxi2vwe5p`의 `gap`은 **−241.7초**로 계산된다. 이는 OVH `updatedAt`이 "READY 전이 시각"이 아니라 "마지막 수정 시각"이라 조인이 어긋난 경우다. **음수 구간은 UNKNOWN이며 평균에 넣지 않는다**(p50은 영향받지 않는다).

---

## 3. Gate G1 — 변경 여부 판정

| 조건 | 측정 | 판정 |
|---|---|---|
| M4 **추정** p50 **≥ 60초** | 140초 (추정) | **조건부 통과 → B1 진행** |
| M3_legacy가 지배 | p90 259초이나 3건 국한, p50 21초 | 아님 (상한 대기 귀속은 UNKNOWN) |
| M2_legacy가 지배 | p50 182초, 밴드 29초 | 아님 — 단 M2_legacy는 M4를 **내포**하므로 이 비교로 지배 여부를 판정할 수 없다 |

**판정: 게스트 구간(M4)이 전체 대기의 주 성분이라는 것은 *추정*이며, 정본 M4 기준선은 아직 없다.** G1을 "통과"로 부르되 근거 등급은 **추정(estimated)** 이다 — M4 140초는 `M2_legacy − 42초`로 도출했고, 게스트 내부의 apt vs 템플릿 분해는 **UNKNOWN**(§6)이다. B1 진행 자체는 유효하다 — B1은 되돌릴 수 있는 단일 필드 변경이고, 측정은 랜딩 후 정본 정의로 새로 한다.

---

## 4. 적용한 변경 (2026-10-27T06:19:07Z)

단일 작성자(main agent) 확인 후 적용. 적용 직전 상태: 인스턴스 **0대**, GARM 러너 **0대**(org의 유일 러너 `axiom-control-northflank`는 컨트롤 플레인으로 무관).

```bash
garm-cli scaleset show 2 --format json > /tmp/b1/ss.before.json
ES=$(jq -c '.extra_specs + {disable_updates:true}' /tmp/b1/ss.before.json)
garm-cli scaleset update 2 --extra-specs "$ES"
garm-cli scaleset show 2 --format json > /tmp/b1/ss.after.json
```

### 4.1 변경 delta — 정확히 한 키

```bash
diff <(jq -S .extra_specs /tmp/b1/ss.before.json) <(jq -S .extra_specs /tmp/b1/ss.after.json)
```
```
1a2
>   "disable_updates": true,
```

### 4.2 보호 필드 불변 단언

`del(.extra_specs)` 로 통째로 지우면 **`extra_packages` 목록이 바뀌어도 못 잡는다**. 따라서 `extra_specs` **내부**는 `disable_updates` 한 키만 빼고 비교한다.

```bash
# 1) extra_specs 외부 불변
#    런타임·파생 필드는 반드시 제외한다: instances / desired_runner_count / state /
#    status_messages 는 스케일링에 따라 변하며, 제외하지 않으면 단언이 거짓 실패한다.
D='del(.extra_specs,.generation,.updated_at,.instances,.desired_runner_count,.state,.status_messages)'
diff <(jq -S "$D" /tmp/b1/ss.before.json) \
     <(jq -S "$D" /tmp/b1/ss.after.json)

# 2) extra_specs 내부: disable_updates 제외 전 필드 동일
diff <(jq -S '.extra_specs | del(.disable_updates)' /tmp/b1/ss.before.json) \
     <(jq -S '.extra_specs | del(.disable_updates)' /tmp/b1/ss.after.json)

# 3) 대상 키가 실제로 켜졌는가
jq -e '.extra_specs.disable_updates == true' /tmp/b1/ss.after.json

# 4) extra_packages 14종이 그대로인가 (2번과 별개로 명시)
diff <(jq -S '.extra_specs.extra_packages' /tmp/b1/ss.before.json) \
     <(jq -S '.extra_specs.extra_packages' /tmp/b1/ss.after.json)
```
```
(1) 출력 없음      → INVARIANT_OUTSIDE=PASS
(2) 출력 없음      → INVARIANT_INSIDE=PASS
(3) true           → DISABLE_UPDATES=PASS
(4) 출력 없음      → EXTRA_PACKAGES_UNCHANGED=PASS
```

> **적용 순서 불변식**: 설정 변경 전에 생성됐지만 아직 살아 있는 ephemeral 러너가 있으면 변경 후 측정에 섞인다. 따라서 **변경 적용 후 기존 러너·GARM 인스턴스·OVH VM이 모두 회수된 것을 확인한 뒤** 측정 대상 merge-queue 작업을 시작한다. `rotate --outdated` 는 필요 없다(§7).

| 필드 | before | after |
|---|---|---|
| `max_runners` | 8 | 8 |
| `min_idle_runners` | `null` | `null` |
| `runner_bootstrap_timeout` | 6 | 6 |
| `image` | `7daa4ffe-c4af-47e5-85e0-f86e610e6fe0` | 동일 |
| `flavor` | `c3-4` | 동일 |
| `template_id` | 5 | 동일 |
| `generation` | 0 | **1** (extra_specs 변경 → 예상된 bump) |

> `garm-cli scaleset update`는 `--max-runners`/`--min-idle-runners`/`--runner-bootstrap-timeout`에 **기본값(5/1/20)을 표시**하지만, 실제로는 `cmd.Flags().Changed()` 로만 필드를 전송한다(`cmd/garm-cli/cmd/scalesets.go:397-404`). 따라서 `--extra-specs`만 지정해도 다른 필드는 덮어쓰이지 않는다. `min_idle_runners`가 `null`로 남은 것이 그 증거다.

---

## 5. 메커니즘 — 왜 이것이 가장 작은 레버인가

```
garm-provider-common/cloudconfig/cloudconfig.go:30-40
    PackageUpgrade: true            ← 기본값. 매 부팅 전체 시스템 업그레이드

garm-provider-common/cloudconfig/util.go:143-149
    if bootstrapParams.UserDataOptions.DisableUpdatesOnBoot {
        cloudCfg.PackageUpgrade = false
        cloudCfg.Packages = []string{}
    }
    for _, pkg := range bootstrapParams.UserDataOptions.ExtraPackages {
        cloudCfg.AddPackage(pkg)    ← 14종은 그대로 설치된다
    }
```

이 배포에서 그 스위치가 실제로 배선되어 있는 경로:

| 단계 | 위치 |
|---|---|
| provider 식별 | `garm-provider-openstack` (`/opt/garm/providers.d/`, `/garm/clouds.yaml`) |
| extra_specs 키 | `provider/spec.go:55` `DisableUpdates *bool \`json:"disable_updates"\`` |
| 병합 | `provider/spec.go:276-278` `MergeExtraSpecs` → `m.DisableUpdates` |
| userdata 반영 | `provider/spec.go:289` `ComposeUserData` → `UserDataOptions.DisableUpdatesOnBoot` |
| 스키마 검증 | `provider/spec.go:71-83` `AllowAdditionalProperties: false` → **키 오타는 조용한 no-op이 아니라 인스턴스 생성 실패** |

> GARM 코어의 `params.UserDataOptions` 태그는 `disable_updates_on_boot`(`params/params.go:517`)이라 문서 키 `disable_updates`와 달라 보이지만, 코어는 `ExtraSpecs`를 **불투명 JSON**으로 provider에 넘기고(`doc/extra_specs.md`), provider가 자기 구조체로 파싱한다. 따라서 이 배포에서는 문서 키가 맞다.

**결론**: `disable_updates`는 새 수명주기(이미지 생성·검증·승격·롤백)를 도입하지 않고 **필드 하나**로 게스트 준비 작업의 한 축을 제거한다.

### 5.1 이 스위치가 제거하는 것과 **제거하지 않는** 것

`disable_updates = true`는 **부트스트랩 전체를 끄는 스위치가 아니다.** 정확히는 **전체 시스템 업그레이드(`dist-upgrade`)를 생략**하는 스위치다.

| 작업 | `disable_updates: true` 이후 |
|---|---|
| 전체 설치 패키지 업그레이드 (`package_upgrade`) | **비활성** |
| 패키지 인덱스 갱신 (`apt-get update`) | **반드시 실행** — `packages:`가 비어 있지 않으면 cloud-init이 `package_update`를 강제로 true로 올린다 |
| `extra_packages` 14종 설치 | **계속 실행** (위 코드가 `Packages`를 비운 뒤 다시 채운다) |
| 러너 등록 · 서비스 시작 (`runcmd`) | **계속 실행** |
| 러너 소프트웨어 자동 업데이트 | **무관** — scaleset `disable_update`(§표, `false` 유지)가 별도 제어 |

근거 1 (코드 경로): `garm-provider-common/cloudconfig/util.go`의 `GetCloudInitConfig`는 `Packages = []string{}`를 **먼저** 실행하고 그 **다음 루프에서** `UserDataOptions.ExtraPackages` 14종을 다시 추가한다. 따라서 `disable_updates` 이후에도 `packages:` 목록은 **비지 않는다**.

근거 2 (플랫폼 의미 — [공식 문서](https://github.com/canonical/cloud-init/blob/main/doc/rtd/reference/yaml_examples/apt.rst)): *"The default is false. However, if packages are given, or if `package_upgrade` is set to true, then the update will be done irrespective of this setting."* 즉 `package_update`가 YAML에 없어도 **패키지가 지정되면 `apt-get update`는 실행된다**. `package_upgrade: false`가 생략하는 것은 그 뒤의 `dist-upgrade`뿐이다.

따라서 이 표의 첫 줄만 참이고 나머지 네 줄은 **B1로 줄지 않는다.** B1이 줄일 수 있는 이론적 상한은 `dist-upgrade` 한 단계다.

> **따라서 B1 가설을 정확히 쓴다**: *"`disable_updates: true`는 부팅 시 전체 패키지 업그레이드를 생략한다. 패키지 인덱스 갱신과 명시적 패키지 설치는 남는다. 실제 감소량은 측정으로 판정한다."* 설정 이름과 실제 효과를 혼동하지 않는다.

---

## 6. 해소되지 않은 UNKNOWN — 임의 배분하지 않는다

`VM READY → 첫 sendStatus` 공백에는 **부팅 + cloud-init 초기 + `apt-get update` + (`disable_updates` 이전에는 `dist-upgrade`) + `extra_packages` 14종 설치**가 함께 있다. 이 구간에는 **콜백이 구조적으로 하나도 없다** — cloud-init의 `packages:` 모듈에는 GARM으로 상태를 보내는 코드가 없고, `sendStatus`는 그 뒤에 실행되는 `runcmd` 설치 스크립트 내부에만 존재한다.

- 확정: 공백 안에 apt 단계가 **포함된다**(코드 경로).
- 확정: GARM은 `installing dependencies` · `configuring runner` · `downloading JIT credentials` 등 부트스트랩 단계를 `status_messages`로 노출한다. 이 계측을 **재구현하지 않고 그대로 쓴다**.
- **UNKNOWN**: 공백 시간 중 apt의 **기여도(초/비율)**.
- **UNKNOWN(중요)**: `VM READY → 첫 sendStatus`를 **cloud-init·패키지 설치 시간으로 귀속할 수 없다.** 그렇게 말하려면 렌더링된 실제 설치 템플릿과 게스트 측 로그(`/var/log/cloud-init-output.log`)로 교차 확인해야 한다. 확인하지 못하면 그 시간은 **UNKNOWN으로 남기고 임의 배분하지 않는다.**
- 관측 해상도: GARM 내부 조정 루프 5초(`runner/common/pool.go:26`), 외부 폴링 10초 → 경계 불확실성 **±10초** + API 전달 지연. 10초 폴링은 첫 상태 관측 시각을 **최대 10초 폭 구간**으로 제한할 뿐이다.
- 템플릿 스크립트의 stdout/stderr은 GARM에 저장되지 않는다(게스트의 `/var/log/cloud-init-output.log`에만 남는다).

따라서 B1의 효과는 **"공백이 줄었는가"** 로만 판정하며, 구간별 비율을 사후 배분하지 않는다.

### 6.1 우측 절단(right-censoring)

`runner_bootstrap_timeout`을 늘리는 것은 **관측 범위를 넓히는 것**이지 모든 실제 완료 시간을 보장하는 것이 아니다. 부트스트랩이 여전히 제한 시간을 넘으면 그 표본은 **우측 절단**이며, "완료까지 X초 걸렸다"고 쓸 수 없다. 절단 표본은 **건수로 따로 보고**한다.

### 6.2 관측된 외부 장애 (B1과 무관 — 기록)

2026-10-27 06:26~06:42Z, OVH `SGP1` 러너에서 **외부 egress 실패**가 관측됐다. B1 적용(06:19:07Z) 이후 시점이라는 이유만으로 인과를 주장하지 않는다.

| 시각(UTC) | 대상 | 증상 |
|---|---|---|
| 06:26:51 | `nim-lang.org` | `CURL failed: Failure when receiving data from the peer` |
| 06:30:20 | `nim-lang.org` | `curl: (35) Recv failure: Connection reset by peer` |
| 06:39:56~06:41:25 | apt (러너 의존성) | `failed to install dependencies`, 15초 간격 6회 재시도 후 포기 |

**B1 무관 판정 근거**: B1 적용 후 생성된 인스턴스 `garm-glytewigi8v9`(VM `9ffde8e5`, `generation=1`)가 06:46:17 `installing dependencies` → 06:46:33 `configuring runner`로 **16초에 통과**했다. 동일 설정의 다른 인스턴스가 정상 동작하므로, 위 실패는 설정이 아니라 **일시적 egress 장애**다.

**자원 회수 확인**: 실패한 러너 `garm-ss0qpzlxzlnq`는 06:41:25 `failed` → 06:44:24 `deleting`으로 **GARM이 스스로 회수**했다.

**별건 — 선행 결함**: 기준선(04:36Z) 잡에서도 `AXIOM_CACHE_A_PROBE: FAIL`(툴체인 캐시가 복원됐지만 `compiler/ast.nim`·`Lake.olean` 누락 → 전량 네이티브 재설치)이 관측됐다. **B1 이전부터 존재한 결함**이며 본 슬라이스 범위 밖이다. 다만 잡마다 Nim+Lean+Z3를 다시 내려받게 만들어 **egress 부하를 상시 증폭**시키므로, 위 장애의 취약성을 키우는 요인이다. Follow-up으로 분리한다.

### 6.3 부팅 직후 dpkg 락 경합 — B1이 건드리지 않는 **실제 소유자**

2026-10-27T07:12:25Z, `debt-registry-gate`(run `40463425798`, attempt 3)가 다음으로 실패했다. 실패 스텝은 `Install system deps (canonical system_deps parity — libpcre3)`이다.

```
E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 3606 (unattended-upgr)
E: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), is another process using it?
##[error]Process completed with exit code 100
```

이 실패는 네트워크가 아니라 **락 경합**이며, B1의 전제에 대한 직접 반증이다.

- B1이 끄는 것은 cloud-init의 `package_upgrade` **하나**다. 이미지의 `unattended-upgrades`는 **systemd 서비스**이므로 이 플래그와 무관하게 부팅 시 실행되고 dpkg 락을 잡는다.
- 따라서 "부팅 시 패키지 작업"의 실행 주체는 cloud-init만이 아니다. 본 문서가 측정한 `gap`(p50 **39.4초**, n=47) 안에도 이 서비스의 작업이 남아 있을 수 있으나, **분리 측정되지 않았다 — UNKNOWN**으로 남긴다.
- CI 영향: A 캐시가 MISS이면 툴체인 스텝이 `libpcre3`를 apt로 설치해야 하고, 락이 잡혀 있으면 exit 100으로 죽는다. 즉 이 클래스는 캐시 상태에 따라 **결정적으로** 재현된다.
- 이 시점의 A 캐시 상태는 §6.2의 선행 결함(`AXIOM_CACHE_A_PROBE: FAIL`)과 같은 계열이다 — 캐시가 있어도 프로브가 스스로 폐기하고 네이티브 설치로 떨어진다. 캐시 존재 여부가 성공/실패를 가르는 구조 자체가 취약성이다.

**대체 레버가 플랫폼에 이미 있다 (이미지 베이킹 불필요)**

| 사실 | 출처 |
|---|---|
| openstack provider의 `extraSpecs` 구조체는 `cloudconfig.CloudConfigSpec`을 **임베드**한다 → `pre_install_scripts`가 스키마상 유효한 키다 | `garm-provider-openstack/provider/spec.go:56` (`cloudconfig.CloudConfigSpec`), 스키마 반영 `:60-66` (`AllowAdditionalProperties: false`) |
| `CloudConfigSpec.PreInstallScripts map[string][]byte` (`json:"pre_install_scripts,omitempty"`) — root로 실행, 알파벳 순 | `garm-provider-common/cloudconfig/util.go` (`GetSpecs`) |
| pre-install 스크립트는 `/garm-pre-install/<name>`로 기록되고 **`/install_runner.sh`보다 먼저** `runcmd`에 들어간다 | `cloudconfig/util.go`의 `GetCloudInitConfig` |

→ scaleset `extra_specs`에 스크립트 한 개를 넣는 것만으로 부팅 초기에 락 대기·서비스 정지를 주입할 수 있다. 새 이미지 수명주기(P6)도, 새 아키텍처 계층도 필요 없다. 다만 이것은 **러너 프로비저닝 계약의 변경**이므로 §8.3에 따라 별도 계획으로 다룬다.

### 6.4 병합 차단의 실제 소유자 — `gateway / select`의 무캐시 원격 설치

PR #1110의 필수 컨텍스트는 `admission-check` 하나가 red로 남아 병합되지 않았다. 원인은 우리 변경 내용이 아니었다.

**추적 (2026-10-27)**

| 관측 | 값 |
|---|---|
| 규칙셋 필수 이름 | `admission-check` (집계 job). `attest / admission-check`·`verdict / admission-check`와 **다른 이름**이다 |
| 시도 1 `gateway / select` | job 122056100549, 07:01:41Z→07:04:24Z, 실패 스텝 = 6 `Install Nim 2.2.10 (choosenim, pinned)` |
| 시도 2 `gateway / select` | job 122063481711, 07:23:44Z→07:29:37Z, 같은 스텝 실패 |
| 시도 2 실패 원문 | `Downloading Nim 2.2.12 from nim-lang.org` → 07:24:21Z 시작, 07:29:21Z `Error: unhandled exception: CURL failed: Timeout was reached [CurlError]` (정확히 300초) |
| 같은 스텝의 성공 선례 | run 40450186479(merge_group), job 122014106088, 04:46:18Z→**04:46:26Z (8초)** |

**구조적 원인 (소스 확정)**: `.github/workflows/runner-pool-acceptance.yml:355-364`의 `select` job은 `curl -sSf https://nim-lang.org/choosenim/init.sh | sh -s -- -y` + `choosenim 2.2.10`을 **무조건** 실행하며 `actions/cache` 복원이 없다. 같은 저장소의 다른 필수 게이트(`axiom-operational-slice`, `debt-registry-gate`, `generation-acceptance`, `bsec-integrity`)는 `./.github/actions/setup-axiom-toolchain`으로 A 캐시를 복원하지만 이 job만 예외다(파일 주석의 근거는 "compiler-source self-heal 불필요"이며 **캐시 부재는 그 축소에 딸려 사라진 것**이다).

**따라서**:
- 실패는 우리 PR 내용과 **무관**하고, 같은 스텝이 8초에 끝난 선례가 있으므로 **시간대 의존 egress 실패**다. 재시도가 1차 조치다.
- 그러나 이 job은 **모든 PR·merge_group의 병합 경로에 있는 필수 게이트**이며, 매 실행마다 34MB 원격 다운로드에 의존한다. 재시도가 반복 실패하면 조치는 재시도가 아니라 이 스텝을 캐시 경로로 위임하는 **워크플로 변경**이며, 그것은 별도 결정이다(§2.5 coherent generation, §2.6 authority/state-transition 정의 필요).
- 극장으로 등재하지 않는다: 이 실패는 **fail-closed**다(초록으로 위장하지 않는다). 등재 대상은 §6.2·DEBT#509의 fail-open 캐시 결함이다.

### 6.5 작업 중 게스트 셧다운 — B1이 건드리지 않는 두 번째 실패 클래스

PR #1110 attempt 3(07:42:34Z 시작)에서 `gateway / select`의 스텝 6~9가 **처음으로 전부 성공**했고, 스텝 10 시작 직후 러너가 종료됐다.

| 관측 | 값 |
|---|---|
| GARM 인스턴스 | `garm-tcmfd50o8ddx`, `created_at` 07:42:44.575Z |
| OVH VM | provider_id `e46051cc-e794-4a09-8321-79c57f43974e`, `createdAt` 07:42:55Z, READY 07:43:45Z |
| 게스트 준비 완료 | 07:45:01.905Z `runner successfully installed` |
| 작업 시작 | 07:45:08Z |
| 셧다운 | 07:45:48.6Z `##[error]The runner has received a shutdown signal` → `The operation was canceled.` |
| **같은 시각의 OVH 상태** | **07:45:50Z에도 `READY`** (STOPPING/SHELVED/DELETING 아님) |
| GARM 인스턴스 상태 | 07:46:06Z `deleting` / `terminated` |

**판정**: 셧다운 시점에 OVH 쪽 인스턴스는 여전히 `READY`였다. 따라서 이 종료는 OVH나 GARM의 delete 호출이 **아니라 게스트 OS 내부에서 시작**됐고, GARM은 그 결과(러너 terminated)를 보고 사후에 정리했다. 인스턴스 생성→셧다운은 **184초**다.

**가설(미확증)**: Ubuntu 이미지의 `unattended-upgrades`가 부팅 후 자동 재부팅을 수행했을 수 있다. §6.3이 같은 이미지에서 `unattended-upgr`가 부팅 시 dpkg 락을 잡는 것을 이미 실측했다. 즉 이 서비스는 `disable_updates`와 **무관하게** 부팅 시 실행된다.

**이것이 B1 판정에 주는 의미**: `disable_updates=true`는 cloud-init의 `package_upgrade`만 끈다. 게스트가 스스로 재부팅하면 그 작업은 **러너 수명주기 밖에서** 죽는다. B1은 이 클래스를 줄일 수단이 아니다.

**확증에 필요한 것(아직 없음)**: 게스트 로그(`/var/log/apt/history.log`, `journalctl -b -1`) 또는 이미지의 `/etc/apt/apt.conf.d/50unattended-upgrades`. GARM은 게스트 로그를 보관하지 않으므로(§6) 현재 관측 경로로는 **UNKNOWN**이다. 반증 방향도 함께 기록한다: 같은 구간에 262초(07:32:06Z→07:36:28Z) 동안 정상 완주한 `gateway / ci-bootstrap`이 있으므로, "모든 VM이 2분 뒤 재부팅한다"는 형태의 법칙은 성립하지 않는다.

### 6.6 해소된 UNKNOWN — 유효 부트스트랩 상한은 **6분 하나뿐**이다

초기 계획은 "GARM 문서가 말하는 유효 기한 = `runner_bootstrap_timeout`과 provider `exec_timeout_seconds` 중 **작은 값**이므로, provider에 3분 이하 제한이 있으면 우리 실험이 무효"라는 위험을 열어두었다. 소스로 확인한 결과 **이 위험은 없다**.

| 질문 | 확정 |
|---|---|
| `runner_bootstrap_timeout`을 누가 강제하는가 | provider가 아니라 **scale-set 컨트롤러 워커** — `workers/scaleset/scaleset.go:378-421` `reapTimedOutRunners` |
| 무엇을 타임아웃시키는가 | **부트스트랩 전체(러너 GitHub 등록 포함)**. 인스턴스 생성 자체는 v0.2.1에서 무제한(`workers/provider/instance_manager.go:240`은 plain `i.ctx`) |
| 회수 조건 | `time.Since(runner.CreatedAt).Minutes() >= RunnerTimeout()` **그리고** `RunnerStatus`가 `pending`/`installing` **그리고** GitHub에서 absent/offline일 때만 (`:389`, `:398`, `:402`) |
| 단위·기본값 | **분(minutes)**, 기본 20 (`util/appdefaults/appdefaults.go:23-26`) |
| provider `exec_timeout_seconds` | **v0.2.1에는 존재하지 않는다**(태그 grep 0건). `main`에 2026-07-08 추가(`bc13696cc8`)되었고 **기본값 0 = 비활성**(`config/external.go:57`) |

**판정**: 우리 서버가 v0.2.1이든 `main`이든 **유효 상한은 6분**이다. `exec_timeout_seconds`가 기본 0(비활성)이므로 더 작은 제한이 끼어들 여지가 없다. 따라서 계획 단계의 P0-2 위험("provider에 3분 제한이 있을 수 있다")은 **반증**되었고, 3→6분 실험은 인과적으로 유효하다.

> **측정 한계 등록**: 위 소스 판독은 upstream `v0.2.1` 태그(`1546384`)와 `main`(`33ec092`) 기준이다. 우리가 실행 중인 provider 바이너리 릴리스가 다른 vendored 템플릿을 쓸 수 있으므로, **`status_messages`의 정확한 집합**은 upstream 목록이 아니라 **우리 관측값**을 정본으로 삼는다(§2.3a). 실제로 upstream 목록에는 `installing runner service`·`starting service`가 있으나 우리 관측 8단계에는 없고, 관측은 `enabling runner service` → `runner successfully installed`로 끝난다. 이 차이는 **결함으로 단정하지 않는다**(provider 쪽 vendored 리비전 차이 가능).

---

## 7. 수용한 트레이드오프와 롤백

**트레이드오프**: `package_upgrade: false`는 골든 OS 이미지의 **부팅 시 보안 패치를 끈다**. 이것은 성능 설정이 아니라 **OS 패치 정책 변경**이다. 따라서 유지 여부를 성능만으로 결정하지 않는다.

- CI 러너 VM은 수명이 수 분이며 우리 저장소의 코드만 실행한다 → 이전 작업의 잔여 상태 노출은 줄지만, **실행 중인 VM의 취약한 패키지가 악용될 위험은 남는다.** PR 검증은 외부 기여 코드가 실행되는 환경이다.
- `extra_packages` 14종은 여전히 매 부팅 설치된다(최신 후보).
- 부수 효과로 **결정론이 상승**한다(동일 베이스 이미지 → 동일 패키지 집합).
- 이는 GARM 공식 FAQ가 "러너를 빠르게 만드는 방법" 1번으로 제시하는 경로다(`doc/faq.md:205`). 다만 GARM 문서는 이 설정의 **보안 함의를 언급하지 않는다** — 근거로 쓰지 않는다.

**유지 조건 (성능 결과와 무관하게 충족해야 함)**

1. **OS 패치 책임자 지정** — 기반 이미지의 보안 업데이트를 누가·어떤 주기로 적용하는지 명시한다. 부팅 시 업그레이드를 껐으므로 그 책임은 **이미지 갱신**으로 이동한다.
2. **기반 이미지 갱신 주기 상한** — `image`(`7daa4ffe-…`)를 최대 며칠 방치하지 않는지 정한다.
3. **효과 미달 시 유지하지 않는다** — M4 감소가 **측정 오차(±10초) 이내**이거나 0이면, OS 패치를 끌 근거가 없다 → **원복을 기본값으로 검토**한다. "해가 없으므로 유지"는 근거가 아니다.

> `config.sh --disableupdate`(러너 소프트웨어 자동 업데이트)와는 **별개**다. 본 슬라이스는 scaleset의 `disable_update: false`를 그대로 두었으므로 GitHub의 러너 자동 업데이트 정책은 유지된다. 따라서 OS 패치 문제가 남는다.

**롤백 (1회, 즉시)**

```bash
ES=$(jq -c '.extra_specs | del(.disable_updates)' /tmp/b1/ss.before.json)
garm-cli scaleset update 2 --extra-specs "$ES"
```

기존 러너는 영향받지 않는다 — 러너는 **ephemeral**(1 VM = 1 잡)이므로 변경은 **다음 잡부터 자연 적용**된다. 회전 절차가 필요 없다.

**`rotate --outdated` 사용 금지**: `extra_specs` 변경은 `generation`을 올리지만(`database/sql/scalesets.go:414` — `updates["generation"] = scaleSet.Generation + 1`), `CreateInstance`는 `Generation`을 설정하지 않는다(`database/sql/scaleset_instances.go:52`의 `newInstance := Instance{...}`에 해당 필드 없음). 필터는 `instances.generation < scale_sets.generation`(`database/sql/scaleset_instances.go:77-78`)이므로, bump 이후 **새로 만든 인스턴스까지 전부** `outdated`가 된다. `params/params.go:424-429`의 주석(*"Generation is the pool generation at the time of creating this instance"*)과 코드가 불일치한다.

이것은 우리 배포에서만의 현상이 아니라 라이브로 확인한 upstream 결함이다 — 같은 시각 scaleset `generation=1`, 신규 인스턴스 `generation=0`. **업스트림 등록: [cloudbase/garm#932](https://github.com/cloudbase/garm/issues/932)**.

---

## 8. 다음 판정 — 착지 후 갱신 (§10이 실측으로 닫는다)

| 항목 | 상태 |
|---|---|
| B1 적용 | **완료** (§4) — 라이브 재확인 `extra_specs.disable_updates=true` |
| B1 이후 게스트 준비 분해 | **완료** — `vm_ready → 등록` p50 **68.3초**(n=47, §2.3) / **69.4초**(n=52, 독립 창 §2.3a), 그중 `gap` ≈40초(소유자 UNKNOWN) |
| B1 **이전** 단계 분해 | **복구 불가** — OVH VM 삭제로 `updatedAt(READY)` 소실, 관측 창도 전부 B1 이후 |
| 효과 측정 (B1 vs 기준선) | **판정 불가** — 대조군이 없다. "140초 → 68초"는 다른 앵커의 추정값과의 비교이며 인과가 아니다 |
| C-5 러너 부트스트랩 단계 순서 | **PASS** — 8단계 전부 정상 순서, 건너뛴 단계 없음, 러너 v2.338.0 고정 (§2.3a) |
| C-7 scaleset 불변식 | **PASS** — `disable_updates` 외 `extra_specs` 동일, `extra_packages` 14종 동일, 보호 필드 불변 |
| Gate G2 (B2 진행 여부) | **미정** — 효과 미입증 상태에서 잔여 구간(§2.3·§6.3)을 근거로 재판정 |
| 자원 회수 (3자 0) | **PASS** — 3자 0대, 6샘플, 실측 316초, UNKNOWN 0회 (§10.4) |
| 랜딩 (C-1~C-3, C-7) | **PASS** — PR #1110 MERGED `8f445d2`, 필수 5컨텍스트·main push 3런 전부 success (§10.2) |

### 8.1 종료 판정 — 두 축을 **분리**한다

| 축 | 판정 질문 | 판정 근거 |
|---|---|---|
| **실험 효과** | 부트스트랩 실패가 줄었고 실제 준비 시간이 줄었는가? | M4 p50·p90·max, 우측 절단 건수 |
| **운영 수용성** | 고정 검증기가 완주했고 필수 검사·병합·자원 회수가 정상인가? | 필수 5컨텍스트, main push 런, 3자 자원 0 |

두 축은 **같은 의미가 아니다.** 실험 효과 미달은 운영 실패가 아니고, 운영 안전 통과는 성능 목표 달성이 아니다. 한 축의 결과로 다른 축을 대체하지 않는다.

**롤백은 자동이 아니다.** 다음 중 하나에 해당할 때만 원복을 결정한다.

- 6분에서도 부트스트랩 타임아웃이 발생하고, 그 원인이 **제한 시간 자체**로 확인될 때(다른 제한·준비 실패가 아닐 때)
- 필수 검사 실패가 **시간 제한 변경과 인과**로 연결될 때 (무관한 검사 실패를 시간 제한의 실패로 투영하지 않는다)
- 변경으로 인한 구체적 부작용(자원 회수 지연, 비용 상승)이 관측될 때

효과가 없을 때는 §7의 **유지 조건 3**에 따라 원복을 기본값으로 검토한다.

### 8.2 랜딩 증거 체크리스트 (C-1 ~ C-7)

| # | 조건 | 확인 방법 |
|---|---|---|
| C-1 | 필수 5컨텍스트(`admission-check`·`axiom-operational-slice`·`bsec-integrity`·`debt-registry-gate`·`generation-acceptance`)가 **머지 시각 이전에** success | `gh api repos/.../commits/<sha>/check-runs` + merged_at 대조 |
| C-2 | GitHub **MERGE 커밋**이 main에 존재하고 부모에 PR head가 조상 | `gh pr view --json mergeCommit,mergedAt` + `git merge-base --is-ancestor` |
| C-3 | 병합 커밋의 **main push 런 전부** success | `gh api .../runs?head_sha=<merge sha>` |
| C-4 | M1–M4를 **개별 보고** (연결식 `M1≈M3+M2+M4` 검증 포함) | §2.2 스크립트 |
| C-5 | 새 러너의 `status_messages`가 **정상 순서**(`installing dependencies` → `configuring runner` → JIT), 캐시 히트로 단계를 **건너뛰지 않았음** | `garm-cli runner show <name> --format json` |
| C-6 | **3자(org 러너 / GARM 인스턴스 / OVH VM) 0대가 실측 300초 이상** 지속 | 첫 0 관측부터 마지막 관측까지 **≥300초**, 최소 6샘플, 타이머는 **마지막 잡 완료 후** 시작 |
| C-7 | §4.2의 4개 단언 전부 PASS | §4.2 |

> C-6 산술 주의: 65초 간격 5회는 첫~마지막이 **260초**로 5분에 미달한다. 60초 간격 **최소 6회**여야 300초가 채워진다. 또한 "조회 5회가 모두 0"과 "5분 **연속** 0"은 다르다.

### 8.3 B2 후보 — `pre_install_scripts`는 왜 **계획**이 필요한가

§6.3이 보인 다음 레버는 "scaleset `extra_specs`에 pre-install 스크립트 한 개 추가"다. 표면상 필드 하나이고 되돌릴 수 있지만, 이 변경은 **러너 프로비저닝 계약**을 바꾼다. 그래서 즉시 실행하지 않고 계획으로 분리한다.

계획이 필요한 이유(각각이 실행 전에 확정되어야 한다):

1. **실패 의미론이 바뀐다.** 지금 실패는 "캐시 MISS → 다운로드 실패"처럼 **조용히 잡을 죽인다**. 스크립트를 넣으면 실패 지점이 하나 늘고, 스크립트 오류는 부팅 단계에서 잡을 통째로 막을 수 있다. 실패 시 fail-closed인지, 스크립트를 건너뛰고 계속인지(fail-open)를 먼저 정해야 한다.
2. **부작용의 소유자가 새로 생긴다.** `unattended-upgrades`를 정지·비활성화하면 OS 보안 패치가 적용되지 않는다. §7의 유지 조건 3(패치 책임자·이미지 갱신 상한)이 이 레버로 **이전**되므로, 그 결정 없이 켜면 무기한 패치 정지가 된다.
3. **적용 순서가 계약과 어긋난다.** pre-install 스크립트는 `runcmd` 단계다. cloud-init `packages:`(현재 14종)는 그 **이전**에 실행되므로, 락 경합은 스크립트로 막을 수 없는 구간이 남는다. 그 구간까지 다루려면 `extra_packages`를 비우고 패키지 설치를 스크립트로 옮겨야 하는데, 그것은 두 필드를 동시에 바꾸는 **다른 변경**이다. 어느 범위까지 갈지가 결정 사항이다.
4. **검증자와 관측 계약이 필요하다.** 효과는 "exit 100 소멸"과 "`gap` 구간 감소" 두 축으로 판정해야 하고, 스크립트가 실제로 실행됐다는 증거(게스트 로그는 GARM에 남지 않는다 — §6)를 어디서 얻을지 정해야 한다.

즉 이 레버는 **가장 작은 표면**을 가졌지만, 바꾸는 것은 설정값이 아니라 **부팅 시 패치 동작의 소유권**이다. 표면이 작다고 계약이 작은 것은 아니다.

## 9. 컴퓨트 공급자 단가 비교 — 실측 VM-초 기준 (2026-10-27)

§1–§8은 부트스트랩 시간을 다룬다. 이 절은 **같은 실측 사용량에 공식 단가를 곱한** 별도 질문("공급자를 바꾸면 실제로 싸지는가")만 다루며, §4의 결론을 바꾸지 않는다.

### 9.1 과금 단위 — 공식 문서로 확정한 사실

| 공급자 | 과금 단위 | 최소 과금 | 계량 시작 | IPv4·스토리지 포함 여부 |
|---|---|---|---|---|
| OVH Public Cloud | **초 단위** (표시가만 시간당) | **1분** | 인스턴스가 `ACTIVE` 도달 시점 (BUILD 구간 무과금) | **UNRESOLVED** — 아래 §9.1a |
| AWS EC2 Spot (Linux) | **초 단위** | 사용자가 종료 시 초 단위 과금 | 인스턴스 사용 시작 | 공인 IPv4 **별도 $0.005/h**, EBS 별도 |
| Ubicloud runner | **분 단위** | 페이지 미기재 | — | 전용 CPU·메모리·로컬 스토리지·공인 IPv4 **포함** |

근거(공식):
- OVH — "billing is calculated per second, with a minimum billing period of 1 minute", "the billing meter starts when an instance reaches the `ACTIVE` status" (`docs.ovhcloud.com/en/guides/public-cloud/cross-functional/analyze-billing.md`, `.../compute-essential-information.md`).
- OVH — "Each Public Cloud instance is delivered with an IPv4 address and an IPv6 address" (`.../network-services/ipv6-configuration.md`). 이 문장은 **"IPv4가 할당된다"**는 사실만 확정하며, **"과금되지 않는다"**는 것을 확정하지 않는다. §9.1a 참조.
- OVH — **이전 판본의 오류 정정.** 이전 판본은 위 문장과 2026-10-27T08:11Z 라이브 관측(8대 전부 공인 IPv4+IPv6 보유, 예: `192.0.2.12` + `2001:db8::d03`)만으로 "IPv4가 인스턴스 가격에 포함되므로 별도 요금 가산은 **이중계상**"이라고 단정했다. 그 추론은 **성립하지 않는다.** "할당된다"는 사실은 과금 대상 여부와 독립이다. 해당 단정을 철회하고 §9.1a에 UNRESOLVED로 남긴다.

### 9.1a OVH 공인 IPv4 과금 여부 — **UNRESOLVED** (철회된 단정)

상충하는 두 근거가 있고, 어느 쪽도 상대를 반증하지 못한다.

| 근거 | 주장 | 출처 |
|---|---|---|
| A | 인스턴스에 IPv4가 **기본 제공**되므로 컴퓨트 가에 포함 | `docs.ovhcloud.com/.../network-services/ipv6-configuration.md` |
| B | 공인 IPv4는 2026-10-01부터 **별도 과금**(Basic IP $0.00319/h, 초 단위, 인스턴스와 별개 청구) | OVH 가격표(공식 도메인) |

**라이브 관측이 실제로 말하는 것** — `ovhcloud cloud ip list --cloud-project <proj>` (2026-10-27):

```
192.0.2.10                 EXT_NET_IP
192.0.2.11                 EXT_NET_IP
2001:db8::82               EXT_NET_IP
2001:db8::dd4              EXT_NET_IP
```

- 4개 IP가 **전부 `EXT_NET_IP`**이고 `FLOATING_IP`(별도 주문 IP)는 **0건**이다. 즉 추가 IP를 주문한 적이 없다.
- 이는 "우리가 IPv4를 받고 있다"만 확정한다. **`EXT_NET_IP`가 과금 대상인지**는 확정하지 못한다.

**확정 실패의 이유** — `ovhcloud` CLI에 청구서·사용량 서브커맨드가 없다(`bill`/`consumption` 부재 확인). 이 항목을 닫으려면 OVH Manager 청구서 또는 `/cloud/project/{id}/consumption` 원시 API 접근이 필요하며, 이는 이 저장소의 범위 밖이다.

**비교에 미치는 영향** — `d2-4` 비교는 두 변형으로 병기한다.
- **변형 1 (IPv4 무과금)**: `d2-4` $0.0244/h
- **변형 2 (IPv4 과금)**: `d2-4` $0.0244 + $0.00319 = **$0.02759/h** (+13.1%)

두 변형 모두 §9.4의 **순위를 바꾸지 않는다**(AWS Spot `c5d.large` $0.0399/h + IPv4 $0.0050/h > 두 변형 전부). 그리고 현금 지출은 어느 변형에서도 **$0**이다(§9.3, GHEC 포함 시간 + 크레딧).
- AWS — Spot은 Linux에서 "charged for the seconds used" (`docs.aws.amazon.com/AWSEC2/latest/UserGuide/billing-for-interrupted-spot-instances.html`).
- AWS — 공인 IPv4 "calculated in one-second increments, with a minimum of 60 seconds" (`aws.amazon.com/vpc/pricing/`). AWS는 "**all** public IPv4 addresses"에 과금하며, Free Tier 계정만 750시간이 면제된다(`AWSEC2/latest/UserGuide/using-instance-addressing.md`, `what-is-amazon-vpc.md`).
- AWS — **과금 종료 경계가 OVH와 다르다.** 인스턴스가 `shutting-down`/`terminated`가 되면 "you stop incurring charges for that instance"이고, 루트 EBS는 `DeleteOnTermination` 기본값이 **true**(=삭제)다(`AWSEC2/latest/UserGuide/ec2-instance-lifecycle.md`, `preserving-volumes-on-termination.html`). 따라서 ephemeral 러너 구성에서는 컴퓨트와 루트 디스크가 **같은 시점에** 멈춘다. 반대로 `DeleteOnTermination=false` 구성은 러너가 사라진 뒤에도 계속 과금되므로, 비교 대상 단가가 아니다.
- Ubicloud — `ubicloud-standard-2` $0.00125/min, IPv4·스토리지 포함, 계정당 $2.5/월 크레딧(=1,250분) (`ubicloud.com/docs/about/pricing`).

### 9.2 단가 (2026-10-27 조회)

| 항목 | 단가 |
|---|---|
| OVH `d2-4` (2 vCore/4 GB, 50 GB SSD) | $0.0244/h |
| OVH `c3-4` (2 vCore/4 GB) — **현행** | $0.0540/h |
| AWS Spot `c5d.large` ap-southeast-1 (SGP1과 동일 권역) | $0.0399/h |
| AWS Spot `c5d.large` us-east-1 (참고) | $0.0344/h |
| AWS 공인 IPv4 | $0.0050/h |
| Ubicloud `ubicloud-standard-2` | $0.00125/min = $0.0750/h |

> AWS 쪽 `c5d.large` **온디맨드** 가격과 **EBS gp3** $/GB-month는 이번 조회에서 공식 정적 소스를 얻지 못했다(페이지가 브라우저 전용 위젯). §9.3의 AWS 총액은 gp3를 **제외한** 하한이다.

### 9.3 실측 사용량에 적용

측정 대상 = 관측 창 s1+s2의 GARM 인스턴스 전부. 인스턴스 수명은 `created_at → 마지막 관측 시각`(하한; 삭제 관측 지연으로 실제보다 짧다).

```bash
# 재현: s1/s2 는 poll.sh 가 남긴 스냅샷 (GARM 인스턴스·OVH VM·러너 상태)
#   수명 = max(ts) - created_at, 이름별
#   비용 = sum(max(수명, 60s)) * rate / 3600
```

| 측정 | 값 |
|---|---|
| 인스턴스 수 | 58 |
| 수명 p50 / 최소 / 최대 | 192초 / 129초 / 790초 |
| 총 VM-초 | 13,539초 (3.761 VM-시간) |

| 공급자·구성 | 이 사용량의 총액 | 인스턴스 1건당 |
|---|---|---|
| **OVH `d2-4`** | **$0.0918** | **$0.00158** |
| AWS Spot `c5d.large` ap-se-1 + IPv4 (**gp3 제외**) | $0.1689 | $0.00291 |
| OVH `c3-4` (현행) | $0.2031 | $0.00350 |
| Ubicloud `ubicloud-standard-2` | $0.2821 | $0.00486 |

### 9.4 판정

1. **AWS Spot으로 옮겨서 절약할 수 없다.** 세 가지를 분리해서 본다.
   - Spot(ap-southeast-1, IPv4 포함)은 현행 `c3-4`보다 인스턴스당 **17% 저렴**하다($0.00291 vs $0.00350).
   - 여기에 16 GB gp3를 더하면 인스턴스당 **+$0.000095**다. 계산: `R × 16 GB × (192 s ÷ 2,592,000 s)` = `R × 0.0011852`이고 `R = $0.08/GB-월`. 즉 Spot 인스턴스 단가의 **3.3%**다.
   - 따라서 gp3는 **양쪽 비교 모두에서 방향을 바꾸지 못한다.**
     - AWS vs `d2-4`: gp3를 더할수록 AWS는 더 비싸진다. **IPv4 과금 여부(§9.1a UNRESOLVED)는 이 결론을 바꾸지 않는다** — 두 변형 모두에서 `d2-4`의 컴퓨트 단가($0.0244 또는 $0.02759)가 AWS Spot 컴퓨트 단가($0.0399)보다 **낮기** 때문이다. 컴퓨트에서 이미 진 쪽에 gp3를 더하면 격차는 더 벌어진다. 즉 AWS가 `d2-4`보다 싸지려면 gp3 비용이 **음수**여야 하므로, 이 비교는 gp3 가정과 IPv4 변형 양쪽에 무관하게 성립한다.
       - 변형 1(IPv4 무과금): `d2-4` $0.0244/h vs AWS Spot+IPv4 $0.0449/h → **45.7% 저렴**
       - 변형 2(IPv4 과금): `d2-4` $0.02759/h vs AWS Spot+IPv4 $0.0449/h → **38.6% 저렴**
     - AWS vs `c3-4`(현행): 차액은 인스턴스당 $0.00059다. 이를 뒤집으려면 `R > $0.498/GB-월`, 즉 가정값의 **6.2배**여야 한다.
   > 위 gp3 단가는 $0.08/GB-월을 **가정**한 값이며, 공식 정적 출처는 이번 조회에서도 얻지 못했다(§9.5). 위 두 문장은 "가정이 6배 틀리지 않는 한 결론이 유지된다"는 형태로만 유효하다.
2. **가장 큰 절감은 공급자 교체가 아니라 flavor 교체다.** `c3-4` → `d2-4`는 이 사용량에서 $0.2031 → $0.0918 (**-55%**)이며, 공급자·이미지·스케일셋 구조를 바꾸지 않는다. 단 §9.5의 미검증 조건이 붙는다.
3. **Ubicloud는 이 사용 패턴에서 가장 비싸다.** 수명 p50 192초(3.2분)인 짧은 러너는 분당 과금에서 불리하다. $2.5 크레딧(1,250분)은 이 관측 사용량(226 VM-분)의 약 5.5배이므로 **크레딧 소진 전까지는 현금 지출 0**이다. 즉 Ubicloud 비교는 "단가"가 아니라 "크레딧 잔량"의 문제다.
4. **GitHub 호스팅 러너 분(minute)은 현금 절감 대상이 아니다.** `gh api /orgs/Archright/settings/billing/usage?year=<Y>&month=<M>` 실측:

   | 월 | Actions 분 | gross | net |
   |---|---|---|---|
   | 2025-11 … 2026-08 | 0 (청구 데이터 없음) | $0 | $0 |
   | 2026-09 | 13,753.0 | — | $0 |
   | 2026-10 | **52,115.33** (Actions Linux 49,506.33 + Actions Linux Slim 2,609) | $302.26 | **$0.00** |

   누적 = **65,868.33분**. 2026-10은 50,000분 포함 한도를 2,115.33분 초과하지만 `netAmount`가 0이므로 **현금 지출은 0**이다. 따라서 "무료 분을 얼마나 아껴 쓰는가"는 이번 비교에서 **비용 항목이 아니다**.
   주의(범위): 이 수치는 GitHub가 청구 대상으로 집계한 분이며, 러너 종류별 분해는 `sku`(Actions Linux / Actions Linux Slim)까지만 제공된다. OVH·Ubicloud 같은 self-hosted 실행분이 이 집계에 포함되는지는 이 API로 판정할 수 없다 → **UNKNOWN**.

### 9.5 이 비교가 확정하지 못한 것 (UNKNOWN)

- AWS `c5d.large` **온디맨드** 가격 — 공식 정적 소스 미확보. 다만 이 비교는 Spot만 쓰므로 온디맨드는 판정에 쓰이지 않는다.
- EBS gp3 $/GB-month — 공식 정적 소스 미확보($0.08 가정). 이 가정은 §9.4의 방향을 바꾸지 못한다: `d2-4` 우위는 gp3와 무관하고, `c3-4` 대비 우위를 뒤집으려면 가정의 6.2배가 필요하다. 남는 위험은 **단가가 아니라 디스크 크기**다(224 GB 이상이면 재계산 필요).
- OVH **SGP1 지역별** 가격 — 조회한 값은 글로벌 USD 공시가다.
- AWS 인터넷 송신 트래픽 요금 — CI는 아티팩트 업로드가 있어 무과금이 아니다.
- AWS Spot 회수(interruption) 리스크의 비용 환산 — 재시도 1회당 인스턴스 1건이 추가되므로, 회수율이 인스턴스당 단가 차이(≤$0.002)를 상회하면 Spot이 더 비싸진다.
- `d2-4`가 이 워크로드를 실제로 감당하는가 — §9.4의 55% 절감은 **자원 교체가 성능을 악화시키지 않는다는 조건**에서만 유효하다. 이 조건은 단가표로 판정할 수 없고 실행으로만 판정된다.

## 10. 랜딩 증거 — PR #1110 실제 착지 (2026-10-27)

§8은 "다음 판정 (미완)"이었다. 이 절은 그 판정을 **실제 운영 응답**으로 닫는다. 수집 시각 2026-10-27T08:44Z~09:05Z.

### 10.1 착지 사실

| 항목 | 값 | 명령 |
|---|---|---|
| PR | `#1110` **MERGED** | `gh pr view 1110 --json state,mergedAt,mergeCommit` |
| 머지 시각 | `2026-10-27T08:42:21Z` | 〃 |
| 머지 커밋 | `8f445d25d25b435588e5f9e284dd8377fd12474f` | 〃 |
| 부모 | `b19e052e…`(main) + `1600cc9f2…`(PR head) → **진짜 merge commit** | `gh api repos/.../commits/8f445d2` |
| `origin/main` 조상 | **예** (`git merge-base --is-ancestor` exit 0) | §10.2 |
| merge_group 큐 | `MQE_lQDORnV8bc8AAAABK8kcvs4ABM2VzgOEG8w` position 1 → 자동 병합 | `mergeQueue` GraphQL |

### 10.2 판정 (C-1 ~ C-7)

| # | 판정 | 근거 |
|---|---|---|
| C-1 | **PASS** | 필수 5컨텍스트가 모두 `mergedAt` **이전**에 `success`. `filter=latest` + `group_by(.name)`+`max_by(.started_at)`로 수집(과거 `unique_by` 오판 경로 차단) |
| C-2 | **PASS** | 머지 커밋이 `origin/main`의 조상이며 부모 2개 |
| C-3 | **PASS** | `push` 이벤트 워크플로 **3건 전부 success**: `axiom-operational-slice`·`ci-provider-router`·`trusted-writer-set` |
| C-4 | **PASS (분해 완료)** | §10.3 |
| C-5 | **PASS** | §2.3a — 8단계 정상 순서, 러너 v2.338.0 고정 |
| C-6 | **PASS** | §10.4 — 3자 0대, 실측 300초 이상 |
| C-7 | **PASS** | `extra_specs`(disable_updates 제외) 동일 / `disable_updates==true` / `extra_packages` 14종 동일 / 보호 필드 7개 불변 |

### 10.3 C-4 — merge_group 시간 분해 (실측)

`admission-gate`를 포함한 merge_group 런 8개 = **잡 32개: success 20 / skipped 12 / 실패 0**.

| 지표 | 정의 | n | min | p50 | p90 | max |
|---|---|---|---|---|---|---|
| **M1** | `job.started − job.created` (사용자 체감 대기) | 20 | 133.0 | **156.5** | 314.9 | 325.0 |
| **M2** | `VM READY − instance.created` (프로비저닝) | 16 | 41.6 | **53.3** | 130.8 | 323.4 |
| **M3** | `instance.created − job.created` (디스패치) | 20 | 4.9 | **15.3** | 186.1 | 195.6 |
| **M4** | `job.started − VM READY` (게스트 준비) | 16 | — | **82.0** | 93.5 | 106.0 |
| WORK | 잡 실행 시간 | 20 | 8.0 | 72.5 | 261.4 | 454.0 |

**연결식 검증** — `M1 ≈ M3 + M2 + M4`가 조인된 16건 전부에서 **오차 0.0초**로 성립했다. 예: `trusted-writer-set-pairing` `5.4+65.6+76.0=147.0` vs `M1=147.0`.

**UNKNOWN으로 남긴 것 (임의 배분 금지)**

| 사유 | 건수 | 처리 |
|---|---|---|
| VM이 첫 관측 시점에 이미 READY (좌측 절단) | 2 | M2/M4 산출 불가 → 제외 |
| GARM 인스턴스 ↔ job 매칭 실패 | 2 | 제외 |
| M4가 **음수**(`attest / build-base-artifacts`, −196.0초) | 1 | 앵커 불일치 → 해당 행 UNKNOWN |

음수 M4는 `updatedAt`이 상태 전이 시각이 아니라 "마지막 수정 시각"이라는 §2.2의 경고가 실제로 발현된 사례다. **값을 0으로 클램프하지 않았다.**

**해석 한계**

- M4 p50 82.0초는 `disable_updates=true` 적용 **후** 값이다. §8이 이미 확정한 대로 **B1 이전 대조군이 없으므로** 이 값을 "감소"로 읽을 수 없다. 이 표는 **현재 상태의 측정**이며 인과 증거가 아니다.
- M1 max 325초는 `max_runners=8` 상한과 겹치는 구간이다. `p50 156.5`와 `p90 314.9`의 2배 차이는 부트스트랩이 아니라 **동시성 대기**가 만든다. 따라서 "부트스트랩을 줄이면 M1이 줄어든다"는 추론은 상한 대기 구간에서 성립하지 않는다.

### 10.4 C-6 — 자원 회수 (3자 0대, 실측 창)

요구: 세 authority가 **동시에** 0대이고, 첫 0 관측부터 마지막 관측까지 **실측 ≥300초**, 최소 6샘플, 60초 간격. 타이머는 **마지막 잡 완료 후** 시작.

| authority | 조회 |
|---|---|
| org 러너 (`garm-*` 접두) | `gh api orgs/Archright/actions/runners` |
| GARM 인스턴스 | `garm-cli scaleset runner list 2 --format json` |
| OVH VM | `ovhcloud cloud instance list --cloud-project <proj> -o json` |

**fail-closed 규칙** (이번 창에서 3회 보강):

1. `gh api` 실패·비파싱 → **빈 출력**(=UNKNOWN). 0으로 읽지 않는다. `axiom-control-*` 접두 러너는 GARM 소유가 아니므로 제외한다.
2. `ovhcloud`는 인스턴스 0대일 때 `[]`가 아니라 리터럴 **`null`**을 출력한다. 기존 스크립트는 `type=="array"`만 0으로 인정해 **실제로 0대인데도 UNKNOWN**이 되어 창이 시작되지 않았다(6샘플 연속 UNKNOWN으로 발현). 수정: **종료 코드 0 + `null` = 0대**, 종료 코드 ≠0은 여전히 UNKNOWN.
3. UNKNOWN 1회는 창을 **리셋**한다. "조회 N회가 0"과 "N초 연속 0"은 다르다.

**실측 결과 — PASS**

```
샘플  ts                     org  garm  ovh
1     2026-10-27T08:58:56Z   0    0     0
2     2026-10-27T09:00:00Z   0    0     0
3     2026-10-27T09:01:03Z   0    0     0
4     2026-10-27T09:02:06Z   0    0     0
5     2026-10-27T09:03:09Z   0    0     0
6     2026-10-27T09:04:12Z   0    0     0

PASS samples=6 elapsed=316s first=08:58:56Z last=09:04:12Z unknown_reads=0
```

- 경과 **316초 ≥ 300초**, 샘플 **6 ≥ 6**, UNKNOWN 읽기 **0회** → 창이 한 번도 리셋되지 않았다.
- 창 시작(08:58:56Z)은 `axiom-operational-slice` push 런 완료(08:51:36Z)와 `ci-cache-publisher`/`ci-provider-router` 캐스케이드가 모두 종료된 **뒤**다. 즉 "마지막 잡 완료 후 타이머 시작" 조건을 만족한다.
- 이 PASS는 "6회 조회가 0이었다"가 아니라 **"316초 동안 연속으로 0이었다"**는 뜻이다.

### 10.5 이 머지가 실제로 배달한 것 — **인과의 정직한 한계**

PR #1110이 바꾼 파일은 **1개**다.

```
372+/0-  docs/evidence/ci_runner_bootstrap_disable_updates_2026-10-27.md
```

즉 이 머지가 배달한 것은 **증거 문서**이며, 운영 설정 변경(`extra_specs.disable_updates=true`, 2026-10-27T06:19:07Z)은 `garm-cli scaleset update 2`로 **라이브에 직접 적용된, 저장소에 선언되지 않은 변경**이다.

- `config/`·`tools/` 전체에 `garm` 참조 **0건** — scaleset 상태의 선언적 정본이 저장소에 없다.
- 따라서 **"머지 = 운영 변경"이라는 인과가 성립하지 않는다.** 재현·감사·롤백이 CLI 이력과 이 문서에만 의존한다.
- C-7은 "변경 후 상태가 의도대로다"를 증명하지만, "그 상태가 버전 관리된다"를 증명하지 않는다.

이 간극은 §8.3의 B2 계획과 **별개**이며, 이번 슬라이스에서 닫지 않았다. 후속 과제로 명시한다(§10.6).

### 10.6 남은 것 (이 슬라이스에서 닫지 않음)

| 항목 | 왜 닫지 않았는가 |
|---|---|
| GARM scaleset 선언적 정본 | 운영 계약 추가(어떤 필드가 정본이고 누가 승격하는가)가 선행 필요 — §0.12·§2.6 |
| B1 **효과** 판정 | 대조군 소실. §8.1의 두 축 중 "실험 효과"는 **UNVERIFIED**로 남는다 |
| OVH IPv4 과금 | §9.1a — CLI에 청구 API 없음 |
| `ci-cache-publisher` 시딩 | 이 머지에서 `skipped` 2회 / `cancelled` 3회(단일-flight 대체). 시딩 부재는 **성능 저하(fail-open), red 아님**(워크플로 헤더 J3) |
| GARM admin JWT 회수 | 서버 설정 파일 접근 권한 밖 — 호스트 운영자 작업 |
