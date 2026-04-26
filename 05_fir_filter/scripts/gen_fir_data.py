#!/usr/bin/env python3
"""8-tap FIR 골든 데이터 생성기 (Phase 2 Week 5).

scipy.signal.firwin 으로 이상 LP 계수를 만들어 Q1.15 양자화한 뒤,
같은 Q-format 정수 산술로 64 샘플(impulse + step + sine + random)을
컨볼루션해 비트 정합 골든 출력을 만든다.

VHDL 측은 동일 계수 배열을 `LP8_COEFS` 상수로 가지며, testbench 가 본
파일의 첫 줄을 읽어 패키지 값과의 일치를 단정한다 (drift 감지).

출력 포맷 (decimal int, space-separated):
    line 0:        N_TAPS  c0 c1 ... c{N_TAPS-1}
    line 1:        N_SAMPLES
    lines 2..N+1:  x_q15  y_q15
"""
import sys

import numpy as np
from scipy.signal import firwin


def to_q15(x):
    n = np.round(x * (1 << 15)).astype(np.int64)
    return np.clip(n, -(1 << 15), (1 << 15) - 1)


def round_q30_to_q15(acc):
    """누산기(임의 폭, Q?.30) → Q1.15 round-half-up + saturate.

    VHDL `acc_q30_round_to_q15` 와 비트 정합. 부호 무관 단일 식
    `(acc + 2^14) >> 15`. Python `>>` 는 음수에 대해서도 floor (toward -∞)
    이므로 VHDL `shift_right(signed)` 와 동일.
    """
    rounded = acc + (1 << 14)
    shifted = rounded >> 15  # arithmetic, floor
    return max(-(1 << 15), min((1 << 15) - 1, int(shifted)))


def fir_filter_q15(x_q15, h_q15):
    """Direct-form FIR. y[n] = Σ h[k] · x[n-k]. 모든 산술 정수."""
    n_taps = len(h_q15)
    n_samples = len(x_q15)
    y = np.zeros(n_samples, dtype=np.int64)
    for n in range(n_samples):
        acc = 0
        for k in range(n_taps):
            if n - k >= 0:
                acc += int(x_q15[n - k]) * int(h_q15[k])
        y[n] = round_q30_to_q15(acc)
    return y


def build_test_signal(n_samples, rng):
    x = np.zeros(n_samples)
    # 임펄스 — impulse response 확인
    x[0] = 0.5

    # 단계 응답 — group delay 확인
    x[8:24] = 0.5

    # 저주파 사인 (LP 통과 대역)
    t = np.arange(n_samples)
    x[24:48] += 0.3 * np.sin(2.0 * np.pi * 0.05 * t[24:48])

    # 균등 분포 랜덤
    x[48:64] = rng.uniform(-0.5, 0.5, n_samples - 48)
    return x


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("Usage: gen_fir_data.py <output_path>\n")
        sys.exit(1)

    rng = np.random.default_rng(seed=20260427)
    n_taps = 8
    n_samples = 64

    h_real = firwin(n_taps, 0.25, window="hamming")
    # DC gain ≈ 1 sanity
    if not (0.95 < h_real.sum() < 1.05):
        sys.stderr.write("ERROR: firwin DC gain off: {}\n".format(h_real.sum()))
        sys.exit(2)

    h_q15 = to_q15(h_real)

    x = build_test_signal(n_samples, rng)
    x_q15 = to_q15(x)

    y_q15 = fir_filter_q15(x_q15, h_q15)

    with open(sys.argv[1], "w") as f:
        coef_str = " ".join(str(int(c)) for c in h_q15)
        f.write("{} {}\n".format(n_taps, coef_str))
        f.write("{}\n".format(n_samples))
        for i in range(n_samples):
            f.write("{} {}\n".format(int(x_q15[i]), int(y_q15[i])))

    print("Wrote {} taps + {} samples to {}".format(n_taps, n_samples, sys.argv[1]))


if __name__ == "__main__":
    main()
