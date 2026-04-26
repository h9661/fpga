# Phase 2 Week 5 — 8-tap FIR 필터 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** scipy 로 만든 이상 계수를 Q1.15 양자화한 ROM-기반 8-tap low-pass FIR. Python(`scipy.signal.lfilter` 가 아닌, 동일한 Q-format 산술의 fixed-point reference) 와 **비트 정합** 검증.

**Architecture:** 직접형(direct form) FIR.
- `rtl/fir_coeffs_pkg.vhd` — 합성-친화적 ROM 으로 추론될 `LP8_COEFS : coef_array_t(0 to 7)` 상수.
- `rtl/fir.vhd` — 7-element shift register(지연선) + 8 multiplier + 8-input adder tree → 1-cycle 지연 후 registered 출력.
- `scripts/gen_fir_data.py` — `firwin(8, 0.25, 'hamming')` 로 계수 생성, Q1.15 양자화. 임펄스 + 스텝 + 사인파 + 랜덤 입력에 대해 동일 Q-format 정수 산술로 골든 출력 계산.
- `tb/tb_fir.vhd` — 첫 줄에서 N_TAPS+coefs 읽어 `LP8_COEFS` 와 일치 확인 → 이후 (x_in, y_exp) 한 cycle 씩 비교.

**Tech Stack:** VHDL-2008, GHDL, GNU Make, Python 3 + numpy + scipy.

---

## File Structure

```
fpga/
├── common/
│   └── fixed_point_pkg.vhd                # 수정: q230_round_to_q15 round-half-up 으로 fix + acc_q30_round_to_q15 추가
└── 05_fir_filter/
    ├── Makefile
    ├── README.md
    ├── scripts/
    │   └── gen_fir_data.py
    ├── rtl/
    │   ├── fir_coeffs_pkg.vhd
    │   └── fir.vhd
    └── tb/
        └── tb_fir.vhd
```

---

## Task 0: `fixed_point_pkg` 라운딩 함수 정정 + 일반화

기존 `q230_round_to_q15` 가 음수 입력에서 round-AWAY-from-zero 로 1 ulp 편향을 만든다 (예: -2^15 입력은 -1 이 정답인데 -2 가 됨). Week 4 MAC 는 이 함수를 사용하지 않아 회귀가 없었지만, Week 5 FIR 에서 누산기 → Q1.15 변환에 쓰이므로 즉시 수정한다.

수정 방침: **round-half-up (toward +∞)** 으로 통일. Python 도 동일 공식을 사용하므로 sign-independent 단일 식 `(x + 2^14) >> 15` 만으로 양쪽 정합.

40-bit (또는 임의 폭) 누산기를 받아 Q1.15 로 라운딩하는 일반 헬퍼 `acc_q30_round_to_q15(x : signed) return q15_t` 도 함께 추가.

- [ ] **Step 1: 함수 정정 + 추가**

`/Users/chan-uhyeon/Programming/fpga/common/fixed_point_pkg.vhd` 의 패키지/바디에 다음 변경:
1. `q230_round_to_q15` 본체를 `(x + 2^14) >> 15` 기반 round-half-up + saturate 로 교체.
2. 패키지 선언에 `function acc_q30_round_to_q15(x : signed) return q15_t;` 추가, 본체에 임의 폭 신호를 1-bit 확장 후 동일 라운딩.

- [ ] **Step 2: Phase 1+4 회귀 확인**

```bash
cd /Users/chan-uhyeon/Programming/fpga
make clean && make test
```
Expected: Week 1~4 모두 PASS (라운딩 정정은 사용처 없으므로 영향 없음).

---

## Task 1: 5주차 폴더 + Python 골든 스크립트

- [ ] **Step 1: 폴더**

```bash
mkdir -p /Users/chan-uhyeon/Programming/fpga/05_fir_filter/{rtl,tb,scripts}
```

- [ ] **Step 2: `gen_fir_data.py`**

`scripts/gen_fir_data.py`:
1. `firwin(8, 0.25, 'hamming')` → 8 coef, sum ≈ 1.0 (DC gain 1)
2. Q1.15 양자화 (numpy.round = ties-to-even = VHDL `integer(real)`)
3. 입력 시퀀스 (총 64 샘플): impulse + step + low-freq sine + uniform random
4. Fixed-point convolution: `acc = Σ x_q15[n-k] * h_q15[k]`, 그 후 `(acc + 2^14) >> 15` round-half-up + saturate → y_q15
5. dump:
```
N_TAPS c0 c1 ... c7
N_SAMPLES
x_q15[0] y_q15[0]
x_q15[1] y_q15[1]
...
```

- [ ] **Step 3: `Makefile`**

`05_fir_filter/Makefile`:
- `MODULES := fir`
- `data/fir_vectors.txt` 타깃이 Python 스크립트에 의존
- `analyze: data/fir_vectors.txt`
- include common Makefile
- clean-data 추가

- [ ] **Step 4: 스크립트 단독 동작 확인**

```bash
cd /Users/chan-uhyeon/Programming/fpga/05_fir_filter
make data/fir_vectors.txt
head -3 data/fir_vectors.txt
```

---

## Task 2: 계수 패키지 + FIR 모듈 — Stub → FAIL → 구현 → PASS

- [ ] **Step 1: 계수 패키지**

`rtl/fir_coeffs_pkg.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.fixed_point_pkg.all;

package fir_coeffs_pkg is
    type coef_array_t is array (natural range <>) of q15_t;

    -- 8-tap LP, normalized cutoff 0.25, Hamming window.
    -- scipy.signal.firwin(8, 0.25, window='hamming') → Q1.15 round-to-even.
    -- 동기: scripts/gen_fir_data.py 가 같은 호출로 만든 값과 정확히 일치해야 함.
    constant LP8_COEFS : coef_array_t(0 to 7) := (
        to_signed(  117, 16),
        to_signed( 1248, 16),
        to_signed( 5277, 16),
        to_signed( 9743, 16),
        to_signed( 9743, 16),
        to_signed( 5277, 16),
        to_signed( 1248, 16),
        to_signed(  117, 16)
    );
end package;
```

- [ ] **Step 2: Testbench 먼저**

`tb/tb_fir.vhd`:
- Read header: `N_TAPS c0 c1 ... c{N_TAPS-1}`. Assert `N_TAPS = LP8_COEFS'length` and each `LP8_COEFS(i) = file_coef(i)`.
- Read `N_SAMPLES`.
- For each sample: drive `x_in <= x_q15[i]; valid_in <= '1'; wait until rising_edge(clk); wait 1 ns; assert y_out = y_q15[i]`.
- 끝나면 `valid_in <= '0'`, `report "tb_fir: PASS (... samples, bit-exact)"`.

- [ ] **Step 3: Stub RTL — 항상 0 출력**

`rtl/fir.vhd` minimal:
```vhdl
architecture rtl of fir is begin
    y_out <= (others => '0');
    y_valid <= '0';
end architecture;
```

- [ ] **Step 4: Run, FAIL 확인**

```bash
cd /Users/chan-uhyeon/Programming/fpga/05_fir_filter
make test
```
Expected: 첫 비-zero impulse 샘플에서 mismatch.

- [ ] **Step 5: 본 구현**

직접형 8-tap FIR.
- Shift register `x_dly : array(0 to N_TAPS-2) of q15_t` (7 elements: x[n-1]..x[n-7])
- 결합 누산:
  ```
  acc := resize(q15_mul(x_in, LP8_COEFS(0)), 40);
  for k in 1 to N_TAPS-1 loop
      acc := acc + resize(q15_mul(x_dly(k-1), LP8_COEFS(k)), 40);
  end loop;
  ```
- `y_r <= acc_q30_round_to_q15(acc); v_r <= '1';`
- Shift: `x_dly(0) <= x_in; x_dly(i) <= x_dly(i-1) for i = 1..N_TAPS-2`.

- [ ] **Step 6: Run, PASS 확인**

`make clean && make test` → `tb_fir: PASS (64 samples, bit-exact)`.

- [ ] **Step 7: Root sweep**

`cd /Users/chan-uhyeon/Programming/fpga && make clean && make test` → 9개 testbench 모두 PASS.

- [ ] **Step 8: Commit**

```
feat(05): add 8-tap LP FIR with bit-exact scipy/firwin golden tb
```

---

## Task 3: README

`05_fir_filter/README.md` 에:
- 모듈 표 (fir_coeffs_pkg, fir)
- 검증 — file 첫 줄 coef parity + 64-sample bit-exact
- 배운 것: 계수 ROM, 직접형 vs 대칭형, Q-format 라운딩 mode 의 책임 분리, scipy lfilter 와 정수 산술 정합
- 디렉토리 트리

---

## 완료 기준
- 루트 `make test` 한 번에 Week 1~5 합 9개 testbench PASS.
- `tb_fir` 가 64 샘플(impulse/step/sine/random) 대해 비트 정합.
- 계수 ROM 이 Python firwin 출력과 자동 동기 (TB 가 매번 검증).

## 범위 밖 (Week 6+)
- Symmetric FIR (대칭 계수 활용한 절반 multiplier 최적화) — coefficient ROM 의 다른 구조에 해당, 향후 별도 모듈로 가능.
- Streaming reset 시퀀스 — 본 모듈은 한 번 reset 후 연속 입력 가정.
- Saturation 누적 (현재는 wrap, 8-tap 입력 범위에서는 안전).
