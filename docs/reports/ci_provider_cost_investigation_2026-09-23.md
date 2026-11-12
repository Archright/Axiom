# CI Compute Provider Cost/Time Investigation — 2026-09-23

> **Type**: point-in-time research report (SSOT: `docs/reports/` = generated projections)
> **Method**: Context7 official docs + 6 background parallel subagents + live price-list queries
> **Scope**: "Is Hetzner the best provider for our ephemeral CI runners, once integrity MUSTs,
> billing quantization, and cost/time are all considered?"
> **Baseline**: Axiom CI on Hetzner <instance-type>, `--ephemeral` 1VM=1job, N legs/full run.
> **Workload used throughout**: <r> full runs/month × <j> jobs = **<m> VM-lifecycles/month**;
> VM lifetime (create→terminate) = boot 30–180 s + job 6–9 min + drain ≈ 30 s = **8–13 min band**.
> **Status**: complete except one pending item (§10 UNKNOWN — hyperscaler fixed-CPU pricing sweep).

---

## 1. Question and ultimate purpose

**Ultimate purpose**: minimize total CI cost (GitHub paid minutes + provider VM charges + wall-clock)
subject to the product contract's integrity MUSTs — without re-implementing anything a platform
already guarantees (Authority-first / TCB delegation).

**Sub-question this report answers**: does any provider beat Hetzner simultaneously on

1. **Integrity** (MUSTs — see §3),
2. **Billing quantization** (sub-hour granularity; Hetzner has a 1-hour round-up floor), and
3. **C/T** (cost and time)?

**Answer: no. 0 of ~20 candidates satisfy all three.** The reason is structural (§7), not
circumstantial. Consequences for levers: §8.

---

## 2. Billing quantization — verified official facts

### 2.1 Hetzner 1-hour floor — **OFFICIAL-DOCUMENTED** (confidence: high)

> *"**We always round up the hourly usage of a server. If you create a server just for a few
> minutes, we will still bill you for one whole hour.**"* — Cloud Billing FAQ,
> `docs.hetzner.com/cloud/billing/faq/`

> *"**We round up partial hours.** The total cost is never more than the monthly price."* —
> "Billing system at Hetzner", `docs.hetzner.com/general/billing-and-account-management/
> billing-at-hetzner/billing-system-hetzner/` (2026-08-28)

> *"…we will bill you for them, **regardless of their state**."* / *"If you want to stop paying
> for something, you need to actively delete or cancel it."*

| Property | Value | Source |
|---|---|---|
| <instance-type> unit price | **€0.0088/h** + Primary IPv4 €0.0008/h ≈ **€0.0096/h** | live `hcloud server-type describe <instance-type>`; ADR-0023:330 |
| Round-up | partial hour → **1 full hour** | FAQ quotes above |
| Monthly cap | **per server**, min(monthly, hourly×hours) | API `price_monthly` + FAQ |
| Deletion | stops accrual **at delete**, but the used partial hour still bills 1 h | FAQ |
| Primary IPv4 | separate hourly (round-up implied, not explicitly stated — immaterial, ≤ €0.0008) | `primary-ips` docs; §10 U-4 |

This confirms the repo's prior claim (ADR-0023:327 "existence under 1 h still bills 1 h") against
current official text, not just measurement.

### 2.2 Competitor quantization — official quotes

| Provider | Billing unit (official quote) | Min charge | Stopped-VM billing |
|---|---|---|---|
| **Hetzner** | hour, **always round up** | 1 full hour | billed until delete |
| **AWS EC2 On-Demand** | *"pay … by the second … subject to a **60-second minimum charge**"* | 60 s | billed while running only |
| **GCP Compute** | *"minimum of 1 minute … After 1 minute … **per-second**"* | 60 s | stopped = stop compute billing |
| **DigitalOcean** | *"CPU Droplets are billed **per second** … minimum … 60 seconds or **$0.01**"* (since 2026-01-01) | **$0.01** (binds for jobs < ~17 min) | still billed while powered off → must destroy |
| **Fly.io Machines** | *"Started Machines are **billed per second**"* | none found | rootfs only ($0.15/GB/mo) when stopped; destroy = 0 |
| **Kamatera** | *"**Hourly servers are billed by the minute**"*; *"pay-as-you-go … no further charges once terminated"* | none found | power-off: storage+IP only; terminate = 0 |
| **Scaleway** | hour; *"**minimum billing duration of 60 minutes** per resource"* | **60 min** | compute pauses on power-off (unique) |
| **Vultr** | *"**minimum billing unit is one hour**"* | 1 hour | billed while stopped → destroy to stop |
| **Akamai/Linode** | *"Usage is **always rounded up to the nearest hour**"* | 1 hour | billed while off |
| **OVH Public Cloud** | *"Every second … beyond an initial **1-minute minimum** … **never rounded up to the next hour**"* | 1 min | billed while stopped |
| **GitHub larger runners** | *"billed at a **per-minute rate** for the duration of workflow execution"*, no idle cost | 1 min | n/a |
| **AWS/GCP/Azure Spot** | per-second/per-minute | 60 s | n/a — **platform may preempt (M2 kill, §4)** |

Hetzner's hourly rate is among the **lowest** (<instance-type> €0.0096/h); its disadvantage is purely the
**round-up floor**, not the unit price.

---

## 3. Integrity MUST classification (what actually constrains a provider)

Only these were treated as requirements; everything else was demoted to verifiable assumptions:

| ID | MUST | Constraint on provider |
|---|---|---|
| **M1** | `--ephemeral`, registration lifetime ≡ job; 1 VM = 1 job as currently deployed | create → run one job → destroy, no runner reuse |
| **M2** | busy/in-flight job must **never** be killed by the platform | **no spot/preemption**; also: platform must not stop running VMs for maintenance/migration (see caveat §4) |
| **M8** | single mutation authority = project's own `axfleet` (its tick journal = VM-creation evidence) | **compute substrate only** — no managed-runner control plane |
| **§0.3** | boot OUR image with OUR pinned toolchain (Nim 2.2.10 / Lean 4.33.0 / Z3 4.13.3 / actions-runner 2.336.0) | custom image / user-data / snapshot support |
| **§0.2** | determinism: build timing must be repeatable | **fixed/guaranteed CPU** — burstable, shared-throttled, or credit-limited CPU is a **disqualifier** (Fly.io shared-CPU lesson) |

**Not** a provider constraint: K=<n>, <instance-type> specifically (`bootstrap_runner.sh:5-6` — "resource-class
candidate, not an architecture invariant"), snapshot ID, location fallback — implementation choices.

---

## 4. Disqualified candidates (integrity MUST violations)

Disqualification ≠ low score; these are **excluded from ranking**:

| Candidate | Violated MUST | Evidence |
|---|---|---|
| **GCP Spot / AWS Spot** (any preemptible) | **M2** | platform preemption kills in-flight verification jobs → same input can pass/fail (§0.2 break); Spot interruption is normal operation, not ToS exception |
| **Ubicloud, BuildJet-class managed GitHub runners** | **M8 + §0.3** | third-party control plane replaces axfleet; `axfleet` tick journal (VM-creation evidence) has no equivalent → evidence chain broken; GitHub TCB outside §0.3 |
| **GitHub larger runners** | **M8** | bypasses axfleet realization layer entirely; also **$13/mo > $2 hard-stop budget** |
| **Fly.io shared-cpu** (`5ms/80ms` = **6.25% sustained** quota) | **§0.2** | non-repeatable build timing; cheap tier exists only by giving up determinism |
| **AWS t3/t3a (burstable), Azure B-series (burstable), GCP e2-medium (shared core)** | **§0.2** | CPU credits / burstable / shared cores = same class of trap as Fly shared-CPU |
| **Kamatera Type A / Type T** | **§0.2** | Type A: *"non-dedicated … **no resources guaranteed**"*; Type T: average-CPU >10 % metered overage → non-deterministic cost **and** burst-shaped behavior. **Type B/D remain eligible** |

Conditional caveat (applies to **every** candidate, Hetzner included): M2's "never stopped" is
only as strong as the provider's undisclosed maintenance behavior. Fly.io explicitly documents
host-migration stops (*"a Machine will be stopped prior to migration"*, no opt-out). Kamatera's
SLA only guarantees compensation, not continuity. **Hetzner is treated as the reference because
no equivalent public stop-on-migration clause was found** — this remains a §10 UNKNOWN (U-3).

---

## 5. Eligible candidates — cost & time

Eligible = passes §3 (M1/M2/M8/§0.3/§0.2). Costs are for the baseline workload (<m>
lifecycles/mo); Hetzner is flat at €2.59 (~$2.80) for any lifetime < 60 min because of the floor.

| Candidate (spec) | Rate | Billable amount | 9-min lifetime | 12-min lifetime | Boot | Integrity |
|---|---|---|---|---|---|---|
| **Hetzner <instance-type>** (2vCPU/4GB, snapshot) | €0.0096/h | <m> h (**floor**) | **$2.80** | **$2.80** | 60–180 s | PASS |
| **Kamatera Type B** (2vCPU/4GB, `$39/mo ⇒ $0.0534/h`) | $0.0534/h | 40.5–54 h (per-minute) | **$2.16** | **$2.88** | official *"deploy … in less than a minute"* (unmeasured) | PASS (Type B only) |
| **Fly.io shared-cpu-2x/4GB** | $0.0309/h | ~40 h | $1.25–1.50 | ~$1.70 | cold ~2 s | **FAIL §0.2** |
| **Fly.io performance-2x/4GB** | $0.0894/h | ~40 h | $3.62–4.00 | ~$4.80 | ~2 s | PASS |
| **DigitalOcean s-2vcpu-4gb** | $0.0357/h | <m> × **$0.01 floor** | **$2.70** | **$2.70** | typical VPS | PASS |
| **OVH b2-7** | $0.0837/h | per-second | $3.39 | $4.52 | typical | PASS |
| **AWS/GCP/Azure fixed-CPU on-demand** (c5a.large / n2-highcpu-2 / F2s_v2 class) | ~$0.077–0.085/h | per-second/minute | ~$3.10–3.44 | ~$4.1–4.6 | AMI/snapshot | PASS (see U-1: live rates pending agent sweep) |
| Scaleway / Vultr / Linode | hourly ≥60-min | floor | $7–10 | $7–10 | typical | PASS quantization? **NO** (≥1 h floor — same class as Hetzner) |

### 5.1 Kamatera break-even (the only eligible near-contender)

`life* = $2.80 / (<m> × $0.00089/min) = **11.65 min**`

| VM lifetime | Kamatera Type B | Hetzner | Winner |
|---|---|---|---|
| 8 min | $1.92 | $2.80 | Kamatera |
| 9 min | $2.16 | $2.80 | Kamatera |
| 11 min | $2.64 | $2.80 | Kamatera |
| **11.65 min** | **$2.80** | $2.80 | **break-even** |
| 12 min | $2.88 | $2.80 | **Hetzner** |
| 13 min | $3.13 | $2.80 | Hetzner |

Reality check: boot 30–180 s + job 6–9 min + drain sits in the **8–13 min band that straddles the
break-even**. Kamatera's win is real but a **coin flip**, plus:

- `$0.02–0.03/h` marketing prices are **Type A/T only** — disqualified under §0.2;
  determinism-preserving price is `$0.0534/h` (Type B).
- **no user-data/cloud-init field** in create API → runner bootstrap must be baked into the
  golden image (부트스트랩 프로비저닝 흐름 이식);
- API requires an active server (image-builder host is de-facto mandatory);
- hourly traffic `$0.01/GB` extra;
- **zero published GitHub-Actions-runner precedents** → `--ephemeral` pattern needs its own PoC;
- boot time `<1 min` is marketing text, not measured.

---

## 6. Fly.io — why C×T looked superior and where it actually lands

**Merits (official)**:
- *"Started Machines are billed per second"* → kills the 1-hour floor (<m> h → ~<p> h);
- *"Cold start: ~2+ seconds"*, resume-from-suspend *"a few hundred ms"* (Firecracker) → 5–10× faster
  boot than Hetzner's 60–180 s snapshot path;
- first-class `POST/DELETE /v1/apps/{app}/machines` + `auto_destroy` → axfleet-shaped control (M8 OK);
- *"lightweight, secure virtual machines based on strong hardware virtualization"* → isolation OK;
- OCI image = §0.3 toolchain pinning is straightforward.

**Where the cheap tier falls**: shared-CPU `5ms/80ms` = 6.25 % sustained → **§0.2 disqualification**.
The deterministic tier (performance-*) costs **$3.7–4.5/mo > Hetzner $2.80** → C-score inversion.
Net: Fly.io wins **time** at any tier; wins **cost** only by abandoning determinism.

---

## 7. The structural result: the "impossible triangle"

After ~20 candidates (VPS, hyperscalers, PaaS/serverless, managed-runner services):

```
              CHEAP
             /      \
            /        \
   FINE-GRAINED     DETERMINISTIC (§0.2)
  BILLING                |
                    (all such instances)
```

- **cheap + fine-grained billing** → CPU is shared/burstable/credit-limited → §0.2 fail
  (Fly shared, AWS t3, Azure B, GCP e2, Kamatera A/T).
- **deterministic + fine-grained billing** → unit rate is 5–10× Hetzner → costs more at any realistic
  lifetime (Fly performance, AWS c5a/c6a, GCP n2, Azure F, OVH).
- **deterministic + cheap** → provider charges with ≥1 h floors (Hetzner, Scaleway 60 min,
  Vultr, Linode) — or a $0.01 job-floor that neutralizes fine granularity (DigitalOcean).

**No corner contains a candidate.** Trading is internal to the price list:

```
unit price ↓  ⇔  CPU guarantee ↓   (Type A is 2.4× cheaper than Type B = price of dropping the guarantee)
unit price ↑  ⇔  billing precision ↑ (per-second = precision premium)
cheap + precise = does not exist
```

**Consequence**: the 1-hour floor is not a Hetzner wart you can vendor-switch away while keeping
integrity. It is the price of determinism at this budget level.

---

## 8. Corrected cost model and the real levers

### 8.1 The correction (this investigation's key fix)

For lifetime < 60 min on Hetzner:

```
Hetzner cost = (number of lifecycles) × 1 h × €0.0096
```

**VM lifetime drops out of the cost function entirely.** "Shorten VM lifetime to save Hetzner
money" is **false** — lifetime is a **time-axis** lever only. (On per-minute providers like
Kamatera lifetime *is* cost; that is exactly why the break-even in §5.1 exists.)

### 8.2 Lever table (money vs time, corrected)

| Lever | Hetzner $ | Wall-clock | GitHub paid $ | Class |
|---|---|---|---|---|
| **select Nim cache** (+ shallow fetch, merge thin ubuntu jobs) | unchanged | −3…−6 min (critical path) | **−$2.5…−4/mo (largest cash line)** | **strict Pareto improvement** |
| **gateway test-binary cache** (`build/gateway-tests` in `actions/cache`) | unchanged | −1…−3 min/shard | unchanged | time-only |
| **K↓ / W8 shard partial subset** (selector emits subset, dynamic matrix) | **−$0.4…−1.4/run × runs** | unchanged (full) / ↓ (partial) | unchanged | **only Hetzner-money lever** |
| ~~VM lifetime reduction~~ | **no effect** | −1…−3 min | — | time-only; was incorrectly listed as money |
| <instance-type> → 2 vCPU/4GB 인스턴스 (unit price) | ~−18 % of floor | risk to latency budget | — | DEFERRED (impl choice) |

### 8.3 The open structural question: amortization vs minimization

Against a 1-hour floor, economics admits only two responses:

1. **minimize** billed units → fewer lifecycles (K↓, shard subset) — currently the sanctioned path;
2. **amortize** → pack more jobs into one billed hour:

```
today:      N VMs × 1 job × 1 h = N billing hours = €0.077 / full run
packed:     1 VM  × N jobs × 1 h = 1 billing hour = €0.0096   (≈N×)
half-pack:  N/2 VMs × 2 jobs × 1 h = N/2 billing hours = €0.038   (≈2×)
```

Amortization is blocked by **1 VM = 1 job**. Classification nuance, recorded honestly:

- `--ephemeral` (**one runner serves one job, no reuse**) = genuine **MUST** (trust boundary,
  ADR-0021/0023);
- **one VM hosts one runner** = current **deployment shape**. A VM could host N sequential
  ephemeral runners (register → job → deregister → next) while preserving the runner-level MUST;
  CPU contention §0.2 would then trade time for money.

**This report does NOT adopt amortization.** It is logged as the single remaining structural
attack on the floor (design decision deferred; see §9 V-6).

---

## 9. Ranking (eligible candidates only) and verdicts

Geometric mean over 4 axes (C cost, T time, E effort-to-adopt, R risk; 1–10 higher = better;
`GM = (C·T·E·R)^0.25`; disqualified candidates excluded entirely):

| Rank | Candidate | C | T | E | R | GM | Note |
|---|---|---|---|---|---|---|---|
| 1 | **Hetzner <instance-type> (status quo)** | 4 | 7 | **10** | **10** | **7.27** | zero migration, audited, tick journal intact |
| 2 | Kamatera Type B | 6 | 7 | 4 | 7 | 5.86 | break-even ± lifetime (§5.1); image-bake port |
| 3 | DigitalOcean | 4 | 7 | 4 | 7 | 5.29 | $0.01 floor ≈ Hetzner floor |
| 3 | OVH Public Cloud | 4 | 7 | 4 | 7 | 5.29 | per-second but ~10× unit rate |
| 5 | Fly.io performance-2x | 3 | 8 | 4 | 7 | ~5.09 | deterministic but pricier |
| — | Scaleway / Vultr / Linode | — | — | — | — | — | ≥1 h floor = same quantization defect, higher rate |

### Verdicts

| ID | Verdict |
|---|---|
| **V-1** | **No candidate wins integrity + quantization + C/T simultaneously (0/~20).** |
| **V-2** | The impossible triangle is structural (§7); provider switch cannot remove the floor without either §0.2 violation or a cost increase. |
| **V-3** | Stay on **Hetzner <instance-type>**. GM4 rank 1 by widest margin on E/R; monetary delta to the best eligible alternative is at most ~$0.6/mo and is a break-even coin flip. |
| **V-4** | The only **strict Pareto improvement** available is **select Nim cache** (유료 분이 지배: 55–65 % of run cost), then **gateway test-binary cache** (time), then **K↓/shard subset** (the sole Hetzner-money lever). |
| **V-5** | "Reduce VM lifetime to save Hetzner money" is **false** under the 1 h floor (§8.1) — rejected; lifetime is time-only. |
| **V-6** | **Amortization** (N ephemeral runners per billed hour) is the only remaining structural attack on the floor; it conflicts with the *deployment shape* 1 VM=1 job, not with runner-level `--ephemeral` MUST. Decision deferred — do not implement under this report. |
| **V-7** | Kamatera Type B may be revisited **only if** measured VM lifetime is proven < 11.65 min *and* a PoC passes (boot distribution, 100 %-CPU stability vs <instance-type>, invoice confirms per-minute, M2 maintenance behavior). |

---

## 10. UNKNOWNs (official docs silent — do not guess)

| ID | Item | Resolution |
|---|---|---|
| **U-1** | Live AWS/GCP/Azure **fixed-CPU** rates (c5a/c6a, n2-highcpu-2, F2s_v2) — background sweep pending at time of writing; table §5 uses ~$0.077–0.085/h estimates | re-query official pricing pages before any decision |
| **U-2** | Kamatera create→ready boot-time distribution (only marketing *"<1 min"*) and multi-GB image pull behavior | PoC required |
| **U-3** | **Any** provider's maintenance-stop behavior inside an 8–13 min window (Fly documents migration-stop; Kamatera SLA is compensation-only; Hetzner silent) | treat all as equal residual risk; do not claim Hetzner is stronger without evidence |
| **U-4** | Hetzner Primary IPv4 round-up wording (server rule is explicit; IP rule is implied) | immaterial (≤ €0.0008/lifecycle) |
| **U-5** | Per-job egress bytes on eligible CI providers (cache restore/upload) | measure once before pricing-dependent decisions |
| **U-6** | Amortization (V-6): CPU-contention impact on §0.2 timing if N>1 ephemeral runners share a VM | separate design task; out of scope here |

---

## 11. Sources (official)

- Hetzner: `docs.hetzner.com/cloud/billing/faq/` · `docs.hetzner.com/general/billing-and-account-management/billing-at-hetzner/billing-system-hetzner/` · `docs.hetzner.cloud` (API pricing) · live `hcloud server-type describe <instance-type>`
- AWS: `docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-on-demand-instances.md` (per-second, 60-s min)
- GCP: `cloud.google.com/compute/vm-instance-pricing` (1-min min, then per-second)
- DigitalOcean: `docs.digitalocean.com/products/droplets/details/pricing/` + release notes 2026-01-01
- Fly.io: `fly.io/docs/about/billing` · `fly.io/docs/about/pricing` · `fly.io/docs/machines/cpu-performance` (shared quota) · `fly.io/docs/reference/architecture` · `fly.io/docs/reference/machine-migration`
- Kamatera: `kamatera.com/pricing/` ("billed by the minute", calculator `$39/mo` 2B/4GB) · `kamatera.com/faq/answer/which-cpu-types-are-offered-by-kamatera/` (Type A/B/T/D) · `kamatera.com/knowledgebase/api-documentation/` · `kamatera.com/service-level-agreement/`
- Scaleway: `docs.scaleway.com` (60-min minimum) · Vultr: `docs.vultr.com` (1-hour minimum) · Linode: `www.linode.com/docs/platform/billing` (round up to nearest hour) · OVH: `docs.ovhcloud.com` (per-second, 1-min min)
- GitHub: `docs.github.com/en/billing/reference/actions-runner-pricing` · `docs.github.com/en/actions/concepts/runners/larger-runners`

Repo-internal: `docs/adr/0021-execution-authority.md`, `docs/adr/0023-scale-set-authority-supersession.md`,
`src/infrastructure/ci_fleet/{decide,reconcile,hcloud_ops,userdata}.nim`,
`.github/workflows/runner-pool-acceptance.yml`, `src/gate/proof_unit_catalog.nim`,
`tools/ci/impact_closure_selector.nim`.

---

*Generated 2026-09-23 from static-first investigation (no paid CI runs used for these findings;
all CI-derived baselines cited from already-recorded runs). Prices are official list prices on
the date above and can change — re-verify before any provider decision.*
