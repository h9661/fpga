# Phase 2 Week 6 — IIR Biquad + CIC 데시메이터 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 두 DSP 빌딩 블록을 추가:
1. **IIR biquad** — 2nd-order LP, Direct Form II Transposed (DF2T). 계수는 `scipy.signal.butter(2, 0.3)` 의 Q1.15 양자화 (모든 |coef| < 1 이라 Q1.15 그대로 사용).
2. **CIC decimator** — R=8, M=1, N=3. 32-bit modular 정수 산술. 출력은 마지막 단에서 `>> 9` 로 unit-gain Q1.15 복원.

**Bit-exact 검증** 둘 다.

**Architecture:**
- `06_iir_cic/rtl/iir_biquad.vhd` — DF2T, Q1.15 입출력. 상태 s1/s2 는 40-bit signed (Q10.30) 로 guard bits 확보.
- `06_iir_cic/rtl/cic_decim.vhd` — 3 integrator (32-bit modular) + 샘플 카운터 + 3 differentiator (32-bit modular) + 최종 round-half-up shift-by-9 → Q1.15.
- `06_iir_cic/scripts/gen_iir_cic_data.py` — Python 으로 동일 산술 수행, golden vector dump.
- 두 testbench, 각각 textio 로 입력/기대값 비교.

**범위 밖 (Phase 2 너머):** Compensation FIR (CIC sinc 응답 평탄화) 은 Week 5 의 generic FIR 모듈로 재사용 가능하지만, 본 주차에서는 노트로만 남기고 실제 구현은 Phase 3 polish 단계에서.

**Tech Stack:** VHDL-2008, GHDL, GNU Make, Python 3 + numpy + scipy.

---

## File Structure

```
06_iir_cic/
├── Makefile
├── README.md
├── scripts/
│   └── gen_iir_cic_data.py
├── rtl/
│   ├── iir_coeffs_pkg.vhd       # butter(2, 0.3) Q1.15 상수
│   ├── iir_biquad.vhd
│   └── cic_decim.vhd
└── tb/
    ├── tb_iir_biquad.vhd
    └── tb_cic_decim.vhd
```

---

## Task 1: 6주차 폴더 + 통합 골든 스크립트

- [ ] **Step 1: 폴더 생성**

```bash
mkdir -p /Users/chan-uhyeon/Programming/fpga/06_iir_cic/{rtl,tb,scripts}
```

- [ ] **Step 2: `gen_iir_cic_data.py`**

한 스크립트로 두 모듈의 골든을 생성. 사용법:
```
gen_iir_cic_data.py iir <output>
gen_iir_cic_data.py cic <output>
```

내용:
1. **공통**: Q1.15 양자화 헬퍼, 40-bit/32-bit modular wrap 헬퍼.
2. **IIR**: butter(2, 0.3) 계수를 Q1.15 양자화. 64 샘플 입력(impulse + step + 사인 + random) → DF2T 정수 산술 시뮬레이션. dump format:
```
b0 b1 b2 a1 a2
N
x_q15 y_q15
...
```
3. **CIC**: R=8, M=1, N=3 으로 80 샘플 입력(단계 입력 위주: CIC 의 sinc filter 응답을 명확히 보기 위함) → 32-bit modular 산술. 출력은 80/8=10 샘플. dump format:
```
R M N
N_IN
x_q15  (한 줄에 하나, 80 줄)
N_OUT
y_q15  (한 줄에 하나, 10 줄)
```

- [ ] **Step 3: Makefile**

```make
MODULES := iir_biquad cic_decim

PYTHON := ../.venv/bin/python

DATA_FILES := data/iir_vectors.txt data/cic_vectors.txt

data:
	mkdir -p data

data/iir_vectors.txt: scripts/gen_iir_cic_data.py | data
	$(PYTHON) $< iir $@
data/cic_vectors.txt: scripts/gen_iir_cic_data.py | data
	$(PYTHON) $< cic $@

analyze: $(DATA_FILES)

include ../common/Makefile.common

.PHONY: clean-data
clean: clean-data
clean-data:
	rm -rf data
```

---

## Task 2: IIR Biquad 모듈

DF2T:
```
v       = b0*x + s1               (Q?.30, 40-bit acc)
y       = round_to_q15(v)         (Q1.15)
s1_next = b1*x + s2 - a1*y        (Q?.30, 40-bit acc)
s2_next = b2*x      - a2*y        (Q?.30)
```

- [ ] **Step 1: 계수 패키지** `rtl/iir_coeffs_pkg.vhd`
  - `BIQUAD_LP_B0/B1/B2`, `BIQUAD_LP_A1/A2` Q1.15 상수.
  - butter(2, 0.3) 의 Q1.15 양자화 값.

- [ ] **Step 2: tb 먼저** `tb/tb_iir_biquad.vhd`
  - 헤더 라인의 5 계수가 패키지와 일치 확인.
  - 매 샘플 1-cycle latency 후 비교.

- [ ] **Step 3: stub RTL** — y_out=0 항상.

- [ ] **Step 4: FAIL 확인** (impulse 첫 샘플 mismatch).

- [ ] **Step 5: 본 구현** `rtl/iir_biquad.vhd`
  - signal s1, s2 : signed(39 downto 0)
  - process(clk):
    - 결합적으로 v 계산 → round_to_q15 → y_r
    - 결합적으로 s1_next, s2_next 계산
    - clk 엣지에서 s1, s2, y_r, v_r 업데이트

- [ ] **Step 6: PASS 확인**.

---

## Task 3: CIC 데시메이터 모듈

- [ ] **Step 1: tb** `tb/tb_cic_decim.vhd`
  - 헤더 R, M, N 확인 (8, 1, 3 만 지원하는 RTL).
  - N_IN x 샘플 입력 → R 샘플마다 1개 출력 → N_OUT 출력 비교.

- [ ] **Step 2: stub RTL** — y_out=0, y_valid='0'.

- [ ] **Step 3: FAIL 확인**.

- [ ] **Step 4: 본 구현** `rtl/cic_decim.vhd`
  - constant R, M, N 하드코드 (8, 1, 3). 또는 generic 으로 노출.
  - 3 integrator: signal i1, i2, i3 : signed(31 downto 0). 매 x_valid 마다 i1 <= i1 + resize(x_in, 32); i2 <= i2 + i1; i3 <= i3 + i2; (모두 32-bit modular).
  - sample_cnt mod R. cnt = R-1 (0-indexed) 시 differentiator 단으로 sample 전달.
  - 3 differentiator: 각 단마다 prev 레지스터 + 빼기. signal d1_in, d1_prev, d2_in, d2_prev, d3_in, d3_prev : signed(31 downto 0).
  - diff stage 들을 한 cycle 에 cascade (조합) — d1_out = d1_in - d1_prev; d2_in <= d1_out; ...
  - 최종 y_raw = d3_out (Q?.something; gain = R^N = 512 = 2^9).
  - y_out = round_to_q15(y_raw, frac_bits = 15 + 9 = 24). 즉 (y_raw + 2^8) >> 9 + saturate.
  - 단, `round_to_q15(x, frac_bits)` 헬퍼가 없으니 fixed_point_pkg 에 추가 (또는 inline).

- [ ] **Step 5: PASS 확인**.

---

## Task 4: 라운딩 헬퍼 일반화 (필요시)

CIC 의 frac=24 케이스를 위해 `acc_qf_round_to_q15(x : signed; frac_bits : natural) return q15_t` 추가. Week 5 의 `acc_q30_round_to_q15` 는 이 일반 함수의 frac=30 특수 경우로 둘 수 있다.

또는 단순히 CIC 코드 내에 inline 으로 처리 (학습 단순화).

선택: **inline** 으로. 각 모듈이 자기 라운딩 식을 명확히 가지는 게 가독성 ↑.

---

## Task 5: 루트 sweep + README + commit

- [ ] **Step 1**: `make clean && make test` → 1~6주차 합 11개 testbench (Week 1=3, Week 2=2, Week 3=2, Week 4=1, Week 5=1, Week 6=2) PASS.

- [ ] **Step 2**: `06_iir_cic/README.md` — 모듈/검증/배운 것/디렉토리.

- [ ] **Step 3**: Phase 2 retrospective (`README.md` 루트의 Phase 2 섹션 또는 별도 파일).

- [ ] **Step 4**: commit
```
feat(06): add IIR biquad (DF2T, butter(2,0.3)) and CIC decimator (R=8,M=1,N=3)
```

---

## 완료 기준
- 11개 testbench PASS.
- IIR biquad 가 64 샘플 비트 정합.
- CIC 가 80 입력 → 10 출력 비트 정합.
- 양 모듈 README 의 "배운 것" 가 DF2T 의미 / CIC bit-growth 를 1~2 문장으로 정리.

## 범위 밖
- Compensation FIR (Week 5 fir 재사용 + 다른 계수 set)
- IIR cascaded biquads (4th-order 등)
- CIC 의 differentiator 가 integrator 와 같은 폭 외 — 정밀도 최적화는 다음 단계.
