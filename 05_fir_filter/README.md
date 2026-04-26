# Week 5 — 8-tap LP FIR 필터 (Phase 2 메인 산출물 1)

scipy.signal.firwin 으로 만든 이상 계수를 Q1.15 양자화한 ROM-기반 직접형(direct-form) 8-tap FIR. Python 동일 산술 reference 와 64 샘플 비트 정합 검증.

## 모듈
| 모듈 | 파일 | 설명 |
|---|---|---|
| `fir_coeffs_pkg` | `rtl/fir_coeffs_pkg.vhd` | `LP8_COEFS : coef_array_t(0 to 7)`. firwin(8, 0.25, 'hamming') Q1.15 양자화 |
| `fir` | `rtl/fir.vhd` | 직접형 8-tap. shift register + 8 mul + adder tree, 1-cycle latency |

## 검증
- `tb_fir` 검증 흐름:
  1. **계수 parity** — 골든 파일 첫 줄과 `LP8_COEFS` 패키지 상수 일치 확인 (drift 즉시 감지).
  2. **시퀀스 비교** — 64 샘플(impulse + step + sine + random) 입력에 대해 1-cycle 후 y_out 정수 비교.
- 골든 데이터 생성: `scripts/gen_fir_data.py` 가 firwin → Q1.15 양자화 → fixed-point convolution → `acc_q30_round_to_q15` 와 동일한 round-half-up + saturate 적용.

## 실행
```
make test
```

## 배운 것
- **계수 ROM**: `constant ARRAY := (...)` + index read 만 사용하면 합성 툴이 LUT-ROM/BRAM-init 로 추론. reg 가 아닌 lookup 비용.
- **직접형 vs 대칭형 FIR**: Linear-phase 계수는 `h[k] = h[N-1-k]` 대칭성을 가져 multiplier 수를 절반으로 줄일 수 있음 (대칭 FIR). 학습용으로 직접형 채택.
- **Q-format 라운딩 책임 분리**: 곱셈은 wrap (Q1.15 × Q1.15 → Q2.30, 손실 없음). 라운딩은 누산 끝 단계에서 한 번만 (Qm.30 → Q1.15). 매번 라운딩하면 누적 오차가 커진다.
- **Bit-exact 가능 조건**: 양쪽 라운딩 모드 일치(round-half-up: `(x + 2^14) >> 15`), 양쪽 saturate 모드 일치, 곱셈 폭 모두 일치. Python `>>` 도 음수에 대해 floor 라 VHDL `shift_right(signed)` 와 정합.
- **계수 drift 방지**: TB 가 Python 출력 첫 줄을 패키지 상수와 매번 단정 → scipy 버전 변경이나 손-편집 실수 즉시 노출.

## 디렉토리
```
05_fir_filter/
├── Makefile        # 데이터 자동 생성 + GHDL 실행
├── README.md
├── scripts/
│   └── gen_fir_data.py
├── rtl/
│   ├── fir_coeffs_pkg.vhd
│   └── fir.vhd
├── tb/
│   └── tb_fir.vhd
└── data/           # gitignored
    └── fir_vectors.txt
```
