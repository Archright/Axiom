#!/usr/bin/env python3
# E3 개정 A2 — 소규모 세대(G) 블록 부트스트랩 타당성 몬테카를로 (계약 §5.3 검증용)
#
# 질문: 세대-수준 블록 부트스트랩(계약 §5.3, 백분위 편측 95% 하한)은 G_B ∈ {2..6}에서
#       편측 95% 커버리지를 달성하는가? 아니면 보정(또는 비확증 종단)이 필요한가?
#
# DGP (E3 상황 재현): y_ig = mu_arm + Delta*1{arm=B} + c_g + e_ig
#   - c_g ~ N(0, rho*sigma^2)   세대(키 세대 = 시드 창) 공유 충격 — 계약 §5.3 "같은 세대 런은 독립이 아니다"의 근거
#   - e_ig ~ N(0, (1-rho)*sigma^2)  런 내성분
#   - 세대당 런 수: B arm m_B = 12/G_B (n_B=12, 계약 §5.6), C arm m_C = 5~8 (n_C=30 수집 중 불균형 재현)
#   - sigma = 100 s (런 수준 스케일 — 커버리지·기각률은 Δ/σ 비율에만 의존), Δ/σ ∈ {0, 0.98} (δ=98 s, 계약 §5.7)
#
# 방법 (편측 95% 하한 LB; "개선 선언" = LB > 0; WCB는 편측 p ≤ 0.05 거절):
#   cb_percentile   계약 §5.3 그대로 — arm 내 세대(평균) 재표집 백분위 (B=1,000)
#   wcb_rademacher  null 부과 wild cluster bootstrap (Cameron-Gelbach-Miller 2008)
#   wcb_webb        동일, Webb 6점 가중치 (Roodman-Nielsen-Webb 2019 — G≤12 권장)
#   t_gmin          세대 평균 2표본 t, df = min(G_B,G_C) − 1 (Ibragimov-Müller 2010 계열 집계 추론)
#   t_welch         세대 평균 2표본 t, Welch–Satterthwaite df
#   t_naive         런 수준 독립 t (계약 §5.3 금지 대상 — 대조군으로만 수록)
#
# 판독 지표:
#   Δ=0:    P(LB>0) = 거짓-확증률 (명목 5% — 실질 초과 시 그 방법의 편측 하한은 무효)
#   Δ=0.98σ: P(LB>0) = 검정력, P(LB ≤ Δ_true) = 진값 커버리지 (95% 미만이면 보수성 위반)
#
# 실행: python3 tools/ci/e3_small_g_bootstrap_sim.py  (numpy 필요, scipy 불요 — t 분위수 자체 구현)
# 읽기 전용 분석 도구 — GitHub API 접근 없음, 게이트·판정 권위 없음 (계약 §8·§9 준수).

import math
import numpy as np

SEED = 20261011
REPS = 1500       # 시나리오당 반복 수 (거짓-확증률 5%점의 MC 표준오차 ≈ ±0.6%p)
B_BOOT = 1000     # 부트스트랩 반복 수 (시뮬 축소값 — 계약 본문 B=10,000과 무관:
                  #   G=2 실패는 구조적 — 서로 다른 재표집 다중집합 수 C(2G-1,G) = 3개뿐)
SIGMA = 100.0     # 런 수준 총 sd


# ---------- t 분포 (scipy 불요 — 정규화 불완전베타 + bisection 자체 구현) ----------

def _betacf(a, b, x):
    MAXIT, EPS, FPMIN = 300, 3e-16, 1e-300
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c, d = 1.0, 1.0 - qab * x / qap
    if abs(d) < FPMIN:
        d = FPMIN
    d = 1.0 / d
    h = d
    for m in range(1, MAXIT + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < FPMIN:
            d = FPMIN
        c = 1.0 + aa / c
        if abs(c) < FPMIN:
            c = FPMIN
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < FPMIN:
            d = FPMIN
        c = 1.0 + aa / c
        if abs(c) < FPMIN:
            c = FPMIN
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < EPS:
            break
    return h


def betainc(a, b, x):
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    ln_front = (math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
                + a * math.log(x) + b * math.log1p(-x))
    front = math.exp(ln_front)
    if x < (a + 1.0) / (a + b + 2.0):
        return front * _betacf(a, b, x) / a
    return 1.0 - front * _betacf(b, a, 1.0 - x) / b


def t_sf(t, df):
    x = df / (df + t * t)
    p_two = betainc(df / 2.0, 0.5, x)
    return p_two / 2.0 if t >= 0 else 1.0 - p_two / 2.0


def t_ppf_95(df):
    if df <= 0:
        return float("inf")
    lo, hi = 0.0, 200.0
    for _ in range(200):
        mid = 0.5 * (lo + hi)
        if t_sf(mid, df) > 0.05:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


# ---------- 방법들 ----------

def cb_percentile_lb(cmB, cmC, rng, B=B_BOOT):
    """계약 §5.3: 세대 평균을 arm 내 재표집, Δ̂* 백분위 5%점 = 편측 95% 하한."""
    gB, gC = len(cmB), len(cmC)
    idxB = rng.integers(0, gB, (B, gB))
    idxC = rng.integers(0, gC, (B, gC))
    boot = cmB[idxB].mean(axis=1) - cmC[idxC].mean(axis=1)
    return float(np.percentile(boot, 5.0))


WEBB6 = np.array([-math.sqrt(1.5), -1.0, -math.sqrt(0.5), math.sqrt(0.5), 1.0, math.sqrt(1.5)])


def wcb_declare(cmB, cmC, kind, rng, B=B_BOOT):
    """null 부과 WCB (세대 평균 단위). 편측 p = #{t*_b >= t_obs}/B, 거절 = p <= 0.05."""
    gB, gC = len(cmB), len(cmC)
    mB, mC = cmB.mean(), cmC.mean()

    def cr1_var(m_g):
        g = len(m_g)
        if g < 2:
            return 0.0
        return float(((m_g - m_g.mean()) ** 2).sum()) / (g * (g - 1.0))

    se_obs = math.sqrt(cr1_var(cmB) + cr1_var(cmC))
    if se_obs == 0.0:
        return False
    t_obs = (mB - mC) / se_obs
    if kind == "rademacher":
        wB = rng.choice(np.array([-1.0, 1.0]), size=(B, gB))
        wC = rng.choice(np.array([-1.0, 1.0]), size=(B, gC))
    else:  # webb 6점
        wB = WEBB6[rng.integers(0, 6, (B, gB))]
        wC = WEBB6[rng.integers(0, 6, (B, gC))]
    sB = mB + wB * (cmB - mB)   # (B, gB)
    sC = mC + wC * (cmC - mC)   # (B, gC)
    vB = ((sB - sB.mean(axis=1, keepdims=True)) ** 2).sum(axis=1) / (gB * max(gB - 1, 1)) if gB > 1 else np.zeros(B)
    vC = ((sC - sC.mean(axis=1, keepdims=True)) ** 2).sum(axis=1) / (gC * max(gC - 1, 1)) if gC > 1 else np.zeros(B)
    se = np.sqrt(vB + vC)
    t_boot = np.where(se > 0, (sB.mean(axis=1) - sC.mean(axis=1)) / np.where(se > 0, se, 1.0), 0.0)
    p = float((t_boot >= t_obs).mean())
    return p <= 0.05


def t_lower_bound(cmB, cmC, df_mode):
    gB, gC = len(cmB), len(cmC)
    vB = cmB.var(ddof=1) / gB
    vC = cmC.var(ddof=1) / gC
    se = math.sqrt(vB + vC)
    d = cmB.mean() - cmC.mean()
    if df_mode == "gmin":
        df = min(gB, gC) - 1
    elif df_mode == "welch":
        df = (vB + vC) ** 2 / ((vB ** 2) / (gB - 1) + (vC ** 2) / (gC - 1))
    else:
        raise ValueError(df_mode)
    return d - t_ppf_95(df) * se


def naive_run_t_lb(flatB, flatC):
    vB, vC = flatB.var(ddof=1) / flatB.size, flatC.var(ddof=1) / flatC.size
    df = flatB.size + flatC.size - 2
    return (flatB.mean() - flatC.mean()) - t_ppf_95(df) * math.sqrt(vB + vC)


# ---------- 시나리오 ----------

def gen_arm(rng, g, sizes, mu, rho):
    """세대 효과 공유 충격 + 런 내 잡음. 반환: (세대 평균 배열, 런 평면 배열)."""
    c = rng.normal(0.0, math.sqrt(rho) * SIGMA, g)
    means, runs = [], []
    for i in range(g):
        y = mu + c[i] + rng.normal(0.0, math.sqrt(1.0 - rho) * SIGMA, sizes[i])
        means.append(y.mean())
        runs.append(y)
    return np.array(means), np.concatenate(runs)


def run_cell(gB, mB, gC, mC_sizes, rho, ds, reps=REPS):
    rng = np.random.default_rng(SEED + 7919 * gB + 104729 * int(mB) + 15485863 * sum(mC_sizes)
                                + 61 * int(rho * 10) + int(ds * 100))
    keys = ["cb_percentile", "wcb_rademacher", "wcb_webb", "t_gmin", "t_welch", "t_naive"]
    res = {k: {"declared": 0, "covered": 0} for k in keys}
    true_delta = ds * SIGMA
    for _ in range(reps):
        cmB, flatB = gen_arm(rng, gB, [mB] * gB, SIGMA + true_delta, rho)
        cmC, flatC = gen_arm(rng, gC, mC_sizes, SIGMA, rho)

        lb = cb_percentile_lb(cmB, cmC, rng)
        res["cb_percentile"]["declared"] += lb > 0
        res["cb_percentile"]["covered"] += lb <= true_delta

        for k, kind in [("wcb_rademacher", "rademacher"), ("wcb_webb", "webb")]:
            res[k]["declared"] += wcb_declare(cmB, cmC, kind, rng)
            res[k]["covered"] += True  # p-value 방식 — 커버리지 미정의(선언률만 판독)

        for k, mode in [("t_gmin", "gmin"), ("t_welch", "welch")]:
            lb = t_lower_bound(cmB, cmC, mode)
            res[k]["declared"] += lb > 0
            res[k]["covered"] += lb <= true_delta

        lb = naive_run_t_lb(flatB, flatC)
        res["t_naive"]["declared"] += lb > 0
        res["t_naive"]["covered"] += lb <= true_delta
    return res


def main():
    print(f"# E3 small-G block-bootstrap validity Monte Carlo")
    print(f"# seed={SEED} reps={REPS} B_boot={B_BOOT} sigma={SIGMA} mB=12/gB nC-sized C-arm")
    hdr = (f"{'gB':>2} {'mB':>2} {'gC':>2} {'mC':>4} {'rho':>4} {'d/sig':>5} | "
           f"{'cbPct%':>7} {'wcbR%':>7} {'wcbW%':>7} {'tGmin%':>7} {'tWelch%':>8} {'naive%':>7} | "
           f"{'cbPctCov':>8} {'tGminCov':>9} {'tWelchCov':>9}")
    print(hdr)

    def emit(gB, mB, gC, mC_sizes, rho, ds, r):
        p = lambda k: 100.0 * r[k]["declared"] / REPS
        c = lambda k: 100.0 * r[k]["covered"] / REPS
        print(f"{gB:>2} {mB:>2} {gC:>2} {str(mC_sizes[0])+'x'+str(len(mC_sizes)):>4} {rho:>4.1f} {ds:>5.2f} | "
              f"{p('cb_percentile'):>7.1f} {p('wcb_rademacher'):>7.1f} {p('wcb_webb'):>7.1f} "
              f"{p('t_gmin'):>7.1f} {p('t_welch'):>8.1f} {p('t_naive'):>7.1f} | "
              f"{c('cb_percentile'):>8.1f} {c('t_gmin'):>9.1f} {c('t_welch'):>9.1f}")

    mC4 = [7, 8, 7, 8]        # n_C=30 수집 중 불균형 (G_C=4)
    mC6 = [5, 5, 5, 5, 5, 5]  # G_C=6
    for gB in (2, 3, 4, 6):
        mB = 12 // gB
        for gC, mC_sizes in ((6, mC6), (4, mC4)):
            for rho in (0.3, 0.7):
                for ds in (0.0, 0.98):
                    emit(gB, mB, gC, mC_sizes, rho, ds, run_cell(gB, mB, gC, mC_sizes, rho, ds))
    print("# t 분위수 자체구현 검증 t_0.95,df=1..5 =",
          [round(t_ppf_95(d), 4) for d in (1, 2, 3, 4, 5)],
          "(참값: 6.3138 2.9200 2.3534 2.1318 2.0150)")
    print("# 구조적 사실: G=2에서 세대 재표집 다중집합 수 = C(2*2-1,2) = 3 → 백분위 하한은 9개 값 중 하나;")
    print("#   Rademacher WCB의 최소 도달 편측 p = 1/2^G (G=4 → 0.0625 > 0.05 → 5% 거절 원리적 불가).")


if __name__ == "__main__":
    main()
