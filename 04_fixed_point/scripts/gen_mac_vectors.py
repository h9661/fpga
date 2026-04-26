#!/usr/bin/env python3
"""MAC 골든 벡터 생성기 (Phase 2 Week 4).

Q1.15 입력 a, b 를 N 개 만들어, Q1.15 × Q1.15 = Q2.30 곱을 누적해
40-bit signed 범위의 누산값 acc[i] 를 매 샘플마다 계산해 dump.

GHDL 의 integer 가 32-bit 이라 textio 로 읽을 누산값이 |acc| < 2^31 안에
있어야 한다. 입력 폭 [-0.3, 0.3] · 16 샘플이면 |acc_max| ≈ 1.4e9 < 2^31.

출력 포맷 (decimal, space-separated):
    line 0:        N
    lines 1..N:    a_q b_q acc_after_this_sample
"""
import sys

import numpy as np


def to_q15(x):
    # numpy.round 는 banker's rounding (ties-to-even). VHDL integer(real) 와 일치.
    n = np.round(x * (1 << 15)).astype(np.int64)
    return np.clip(n, -(1 << 15), (1 << 15) - 1)


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("Usage: gen_mac_vectors.py <output_path>\n")
        sys.exit(1)

    rng = np.random.default_rng(seed=20260426)
    n_samples = 16

    a = rng.uniform(-0.3, 0.3, n_samples)
    b = rng.uniform(-0.3, 0.3, n_samples)

    a_q = to_q15(a)
    b_q = to_q15(b)

    products = a_q * b_q  # int64 multiply, exact
    acc = np.cumsum(products)

    if np.any(np.abs(acc) >= (1 << 31)):
        sys.stderr.write(
            "ERROR: acc overflows int32 (max abs = {})\n".format(int(np.abs(acc).max()))
        )
        sys.exit(2)

    with open(sys.argv[1], "w") as f:
        f.write("{}\n".format(n_samples))
        for i in range(n_samples):
            f.write("{} {} {}\n".format(int(a_q[i]), int(b_q[i]), int(acc[i])))

    print("Wrote {} vectors to {}".format(n_samples, sys.argv[1]))


if __name__ == "__main__":
    main()
