#!/usr/bin/env python3
"""IIR biquad + CIC decimator 골든 데이터 생성기 (Phase 2 Week 6).

Sub-command:
    iir <out>   : 2nd-order LP biquad (butter(2, 0.3)) Q1.15. 64 sample.
    cic <out>   : R=8, M=1, N=3 CIC decimator. 80 입력 → 10 출력.

양쪽 모두 VHDL RTL 과 비트 단위로 일치하는 정수 산술. 모든 wrap/round
모드는 plan 문서에 명시된 대로 round-half-up + saturate (출력) /
modular (내부) 방식.
"""
import sys

import numpy as np
from scipy.signal import butter


# ─── 공통 헬퍼 ──────────────────────────────────────────────────────────
def to_q15(x):
    n = np.round(x * (1 << 15)).astype(np.int64)
    return np.clip(n, -(1 << 15), (1 << 15) - 1)


def wrap_signed(v, width):
    """v 를 width-bit signed (modular wrap) 로 변환."""
    mask = (1 << width) - 1
    sign_bit = 1 << (width - 1)
    v = int(v) & mask
    if v & sign_bit:
        v -= 1 << width
    return v


def round_q15(acc, frac_bits):
    """signed acc(Q?.frac_bits) → Q1.15 round-half-up + saturate."""
    shift = frac_bits - 15
    if shift < 0:
        # 본 스크립트에서 발생하지 않는 경로
        rounded = int(acc) << (-shift)
    else:
        rounded = (int(acc) + (1 << (shift - 1))) >> shift
    return max(-(1 << 15), min((1 << 15) - 1, rounded))


# ─── IIR biquad ─────────────────────────────────────────────────────────
def gen_iir(out_path):
    rng = np.random.default_rng(seed=20260428)
    n_samples = 64

    b, a = butter(2, 0.3)
    # b = [b0, b1, b2], a = [1, a1, a2]. 모두 |coef| < 1 → Q1.15 직접.
    b_q = to_q15(b)
    a_q = to_q15(a[1:])  # a1, a2 (a[0]=1 은 사용 안 함)

    b0, b1, b2 = (int(c) for c in b_q)
    a1, a2 = (int(c) for c in a_q)

    # 입력 시퀀스: impulse + step + sine + random
    x = np.zeros(n_samples)
    x[0] = 0.5
    x[8:24] = 0.5
    t = np.arange(n_samples)
    x[24:48] += 0.3 * np.sin(2.0 * np.pi * 0.05 * t[24:48])
    x[48:64] = rng.uniform(-0.5, 0.5, n_samples - 48)
    x_q = to_q15(x)

    # DF2T 정수 산술. 상태 s1, s2 는 40-bit signed.
    s1 = 0
    s2 = 0
    y_q = np.zeros(n_samples, dtype=np.int64)

    for n in range(n_samples):
        xn = int(x_q[n])
        # v = b0*x + s1 (Q?.30, 40-bit acc)
        v = b0 * xn + s1
        # round v(Q?.30) → Q1.15
        y = round_q15(v, frac_bits=30)
        y_q[n] = y

        # state update — 40-bit modular wrap.
        s1_next = b1 * xn + s2 - a1 * y
        s2_next = b2 * xn - a2 * y
        s1 = wrap_signed(s1_next, 40)
        s2 = wrap_signed(s2_next, 40)

    with open(out_path, "w") as f:
        f.write("{} {} {} {} {}\n".format(b0, b1, b2, a1, a2))
        f.write("{}\n".format(n_samples))
        for i in range(n_samples):
            f.write("{} {}\n".format(int(x_q[i]), int(y_q[i])))

    print("Wrote IIR biquad: 5 coefs + {} samples to {}".format(n_samples, out_path))


# ─── CIC decimator ──────────────────────────────────────────────────────
def gen_cic(out_path):
    R = 8
    M = 1
    N = 3
    n_in = 80
    rng = np.random.default_rng(seed=20260429)

    # 입력: 단계 응답 위주 (CIC sinc impulse 응답을 또렷이 보기 위해)
    #  - 0~9 : 0
    #  - 10~39 : +0.5 step
    #  - 40~59 : -0.3 step
    #  - 60~79 : 작은 random
    x = np.zeros(n_in)
    x[10:40] = 0.5
    x[40:60] = -0.3
    x[60:80] = rng.uniform(-0.2, 0.2, 20)
    x_q = to_q15(x)

    # 32-bit modular 정수 산술
    i1 = 0
    i2 = 0
    i3 = 0
    d_prev = [0, 0, 0]  # 3 differentiator 단의 prev 레지스터
    sample_cnt = 0

    y_list = []

    for n in range(n_in):
        xn = int(x_q[n])
        # 3 integrator: 매 입력 cycle 마다 차례로
        i1 = wrap_signed(i1 + xn, 32)
        i2 = wrap_signed(i2 + i1, 32)
        i3 = wrap_signed(i3 + i2, 32)

        sample_cnt += 1
        if sample_cnt == R:
            sample_cnt = 0
            # 3 differentiator (cascade), decimated rate
            d_in = i3
            d_in = wrap_signed(d_in - d_prev[0], 32)
            d0_curr = i3
            d1_in_for_next = d_in  # = stage1 output
            d_in_2 = wrap_signed(d_in - d_prev[1], 32)
            d2_in_for_next = d_in_2
            d_in_3 = wrap_signed(d_in_2 - d_prev[2], 32)
            y_raw = d_in_3

            d_prev[0] = d0_curr
            d_prev[1] = d1_in_for_next
            d_prev[2] = d2_in_for_next

            # gain = R^N = 8^3 = 512 = 2^9. 출력 = round((y_raw + 256) >> 9).
            y_q = round_q15(y_raw, frac_bits=15 + 9)
            y_list.append(y_q)

    with open(out_path, "w") as f:
        f.write("{} {} {}\n".format(R, M, N))
        f.write("{}\n".format(n_in))
        for v in x_q:
            f.write("{}\n".format(int(v)))
        f.write("{}\n".format(len(y_list)))
        for v in y_list:
            f.write("{}\n".format(int(v)))

    print("Wrote CIC: R={} M={} N={}, {} in → {} out to {}".format(
        R, M, N, n_in, len(y_list), out_path))


# ─── entry ──────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("iir", "cic"):
        sys.stderr.write("Usage: gen_iir_cic_data.py {iir|cic} <output_path>\n")
        sys.exit(1)
    if sys.argv[1] == "iir":
        gen_iir(sys.argv[2])
    else:
        gen_cic(sys.argv[2])


if __name__ == "__main__":
    main()
