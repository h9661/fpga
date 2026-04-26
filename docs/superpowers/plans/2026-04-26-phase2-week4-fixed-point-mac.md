# Phase 2 Week 4 — 고정소수점과 3-스테이지 파이프라인 MAC 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Q1.15 고정소수점 표현을 다루는 공용 패키지(`common/fixed_point_pkg`)와, 3-스테이지 파이프라인 Multiply-Accumulate(MAC) 유닛을 구현. Python(NumPy)로 만든 골든 벡터와 **비트 정합** 검증.

**Architecture:**
- `common/fixed_point_pkg.vhd` — Q1.15 ↔ real 변환, Q2.30 곱셈, Q2.30 → Q1.15 라운딩.
- `04_fixed_point/rtl/mac.vhd` — 입력 레지스터(stage 1) → 곱셈 레지스터(stage 2) → 누산 레지스터(stage 3). 3-cycle latency.
- `04_fixed_point/scripts/gen_mac_vectors.py` — NumPy로 random 입력과 누산 결과를 미리 계산해 `data/mac_vectors.txt`로 dump.
- `04_fixed_point/tb/tb_mac.vhd` — `std.textio`로 벡터 파일을 읽어 한 줄씩 입력, 3-cycle 후 acc_out을 정수 비교.

**Tech Stack:** VHDL-2008, GHDL 6.0 LLVM, GNU Make, Python 3 + NumPy (venv `/Users/chan-uhyeon/Programming/fpga/.venv`).

**Why bit-exact (not tolerance):** 정수 산술만 사용하므로 부동소수 오차가 없다. Python `np.round` (banker's rounding)와 VHDL `integer(real)` 모두 ties-to-even이므로 양쪽 양자화가 정확히 일치한다. 한 번이라도 LSB 차이가 나면 Q-format 변환 함수에 버그가 있다는 신호.

---

## File Structure

생성할 파일:

```
fpga/
├── common/
│   └── fixed_point_pkg.vhd                # 신규: Q1.15 패키지
└── 04_fixed_point/
    ├── Makefile                           # 신규: data 자동 생성 + analyze 의존
    ├── README.md
    ├── scripts/
    │   └── gen_mac_vectors.py             # 신규
    ├── rtl/
    │   └── mac.vhd                        # 신규
    └── tb/
        └── tb_mac.vhd                     # 신규
notes/week-04.md                           # 신규: 학습 일지
```

생성되는(.gitignore된) 파일:
```
04_fixed_point/data/mac_vectors.txt
```

---

## Task 0: 공용 패키지 `fixed_point_pkg`

`common/fixed_point_pkg.vhd`에 Q1.15 도구를 모은다. Week 1~3에서 쓰지 않는 코드지만 `Makefile.common`이 모든 주차에서 자동 분석하므로 컴파일은 통과해야 한다.

- [ ] **Step 1: 패키지 작성**

Create `/Users/chan-uhyeon/Programming/fpga/common/fixed_point_pkg.vhd`:

```vhdl
-- 본 패키지는 Q1.15 (1 sign + 15 frac) 고정소수점을 다룬다.
-- Q1.15 값의 실수 의미: N / 2^15, 범위 [-1.0, 1.0).
-- Q2.30 (Q1.15 × Q1.15 결과)의 실수 의미: N / 2^30.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package fixed_point_pkg is
    constant Q15_FRAC_BITS  : natural := 15;
    constant Q230_FRAC_BITS : natural := 30;

    subtype q15_t  is signed(15 downto 0);
    subtype q230_t is signed(31 downto 0);  -- Q1.15 × Q1.15 곱셈 결과

    function to_q15(x : real) return q15_t;
    function q15_to_real(x : q15_t) return real;
    function q230_to_real(x : q230_t) return real;

    function q15_mul(a, b : q15_t) return q230_t;
    function q230_round_to_q15(x : q230_t) return q15_t;
end package;

package body fixed_point_pkg is
    function to_q15(x : real) return q15_t is
        constant SCALE : real := 2.0 ** Q15_FRAC_BITS;
        variable n     : integer;
    begin
        -- VHDL 표준: integer(real)는 round-half-to-even. numpy.round의 기본과 일치.
        n := integer(x * SCALE);
        if n >= 2**15 then
            return to_signed(2**15 - 1, 16);  -- saturate +
        elsif n < -(2**15) then
            return to_signed(-(2**15), 16);   -- saturate -
        else
            return to_signed(n, 16);
        end if;
    end function;

    function q15_to_real(x : q15_t) return real is
    begin
        return real(to_integer(x)) / (2.0 ** Q15_FRAC_BITS);
    end function;

    function q230_to_real(x : q230_t) return real is
    begin
        return real(to_integer(x)) / (2.0 ** Q230_FRAC_BITS);
    end function;

    function q15_mul(a, b : q15_t) return q230_t is
    begin
        return a * b;  -- numeric_std signed * signed → signed(31 downto 0)
    end function;

    -- Q2.30 → Q1.15: shift_right by 15 (=Q230 - Q15 frac bits) + saturation.
    -- 라운딩은 round-half-up: 0.5 ulp(=2^14) 더한 뒤 truncate.
    function q230_round_to_q15(x : q230_t) return q15_t is
        variable rounded : signed(31 downto 0);
        variable shifted : integer;
    begin
        if x >= 0 then
            rounded := x + to_signed(2**14, 32);
        else
            rounded := x - to_signed(2**14, 32);
        end if;
        shifted := to_integer(shift_right(rounded, 15));
        if shifted >= 2**15 then
            return to_signed(2**15 - 1, 16);
        elsif shifted < -(2**15) then
            return to_signed(-(2**15), 16);
        else
            return to_signed(shifted, 16);
        end if;
    end function;
end package body;
```

- [ ] **Step 2: Phase 1 회귀 확인**

```bash
cd /Users/chan-uhyeon/Programming/fpga
make clean && make test
```
Expected: Week 1~3 7개 testbench PASS (패키지가 컴파일 오류 없이 추가됨).

---

## Task 1: 4주차 폴더 + Python 골든 스크립트

- [ ] **Step 1: 폴더 생성**

```bash
mkdir -p /Users/chan-uhyeon/Programming/fpga/04_fixed_point/{rtl,tb,scripts,data}
```

(`data/`는 .gitignore되어 있다. 실제 파일은 `make`가 생성.)

- [ ] **Step 2: 골든 스크립트**

Create `/Users/chan-uhyeon/Programming/fpga/04_fixed_point/scripts/gen_mac_vectors.py`:

```python
#!/usr/bin/env python3
"""MAC 골든 벡터 생성기.

Q1.15 입력 a, b를 N개 만들어 Q2.30 곱셈을 누적한 누산값(40-bit signed)을
한 줄씩 dump한다. 누산값은 GHDL의 32-bit integer 한도 안에 들도록 입력
범위를 [-0.3, 0.3]로 제한한다 (16개 누적 시 |acc| < 1.5e9 < 2^31).

출력 포맷 (decimal integers, space-separated):
    line 0:        N
    lines 1..N:    a_q b_q acc_after_this_sample
"""
import sys
import numpy as np


def to_q15(x):
    # numpy.round는 ties-to-even. VHDL의 integer(real)와 일치하도록.
    n = np.round(x * (1 << 15)).astype(np.int64)
    return np.clip(n, -(1 << 15), (1 << 15) - 1)


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("Usage: gen_mac_vectors.py <output_path>\n")
        sys.exit(1)

    rng = np.random.default_rng(seed=20260426)
    N = 16
    a = rng.uniform(-0.3, 0.3, N)
    b = rng.uniform(-0.3, 0.3, N)

    a_q = to_q15(a)
    b_q = to_q15(b)

    products = a_q * b_q  # int64
    acc = np.cumsum(products)

    if np.any(np.abs(acc) >= (1 << 31)):
        sys.stderr.write(
            "ERROR: acc overflows int32 (max abs = {})\n".format(np.abs(acc).max())
        )
        sys.exit(2)

    with open(sys.argv[1], "w") as f:
        f.write("{}\n".format(N))
        for i in range(N):
            f.write("{} {} {}\n".format(int(a_q[i]), int(b_q[i]), int(acc[i])))

    print("Wrote {} vectors to {}".format(N, sys.argv[1]))


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: 4주차 Makefile**

Create `/Users/chan-uhyeon/Programming/fpga/04_fixed_point/Makefile`:

```make
MODULES := mac

# Phase 2 부터 Python 골든 모델 의존. 레포 루트의 venv 사용.
PYTHON := ../.venv/bin/python

# 골든 벡터: Python 스크립트가 변하면 재생성.
DATA_FILES := data/mac_vectors.txt

data:
	mkdir -p data

data/mac_vectors.txt: scripts/gen_mac_vectors.py | data
	$(PYTHON) $< $@

# common Makefile 의 analyze 보다 먼저 데이터 생성.
analyze: $(DATA_FILES)

include ../common/Makefile.common

# common/clean 외 추가 정리.
clean::
	rm -rf data
```

> Note: `clean::` 더블콜론은 `Makefile.common`의 `clean:` (single colon) 과 충돌하므로 single colon `clean:` 으로 작성하면 GNU make 가 "redefining"을 경고하면서도 두 규칙을 모두 실행한다. 단순 일관성을 위해 single colon 사용 후 `rm -rf data` 한 줄을 추가한다 — 만약 경고가 거슬리면 `Makefile.common` 의 clean을 `.PHONY`로만 두고 데이터 정리는 별도 타깃으로 분리한다.

→ 위 주석을 따라 실제 Makefile은 다음으로 단순화:

```make
MODULES := mac

PYTHON := ../.venv/bin/python

DATA_FILES := data/mac_vectors.txt

data:
	mkdir -p data

data/mac_vectors.txt: scripts/gen_mac_vectors.py | data
	$(PYTHON) $< $@

analyze: $(DATA_FILES)

include ../common/Makefile.common

# data 디렉토리도 함께 정리. clean 은 common 에서 정의됐고 같은 target 에
# command 가 두 번 정의되면 경고가 뜨므로 별도 .PHONY 타깃으로 둔다.
.PHONY: clean-data
clean: clean-data
clean-data:
	rm -rf data
```

> GNU make 4 부터 동일 target 의 commands 중복은 warning + 후자 무시. 위 패턴은
> command 없는 의존성만 추가하므로 안전.

- [ ] **Step 4: 스크립트 단독 동작 확인**

```bash
cd /Users/chan-uhyeon/Programming/fpga/04_fixed_point
make data/mac_vectors.txt
head -3 data/mac_vectors.txt
```
Expected: `16` followed by a few lines of `a_q b_q acc` integers.

---

## Task 2: MAC 모듈 — Stub → FAIL → 구현 → PASS

3-stage 파이프라인 MAC. stage 1: 입력 레지스터, stage 2: 곱셈 레지스터, stage 3: 누산 레지스터. 매 cycle `in_valid='1'` 이면 그 cycle의 (a, b)가 3 cycle 뒤 acc 에 더해진다.

- [ ] **Step 1: Testbench 먼저**

Create `/Users/chan-uhyeon/Programming/fpga/04_fixed_point/tb/tb_mac.vhd`:

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.fixed_point_pkg.all;

entity tb_mac is
end entity;

architecture sim of tb_mac is
    constant CLK_PER : time := 10 ns;

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal clr       : std_logic := '0';
    signal in_valid  : std_logic := '0';
    signal a_in      : q15_t := (others => '0');
    signal b_in      : q15_t := (others => '0');
    signal acc_out   : signed(39 downto 0);
    signal out_valid : std_logic;

    signal sim_done : boolean := false;
begin
    dut : entity work.mac
        port map (
            clk       => clk,
            rst       => rst,
            clr       => clr,
            in_valid  => in_valid,
            a_in      => a_in,
            b_in      => b_in,
            acc_out   => acc_out,
            out_valid => out_valid
        );

    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PER/2;
            clk <= '1'; wait for CLK_PER/2;
        end loop;
        wait;
    end process;

    stim : process
        file vec_file : text open read_mode is "data/mac_vectors.txt";
        variable L         : line;
        variable n_samples : integer;
        variable a_int, b_int, acc_exp : integer;
        type int_arr_t is array (natural range <>) of integer;
        variable a_arr   : int_arr_t(0 to 1023);
        variable b_arr   : int_arr_t(0 to 1023);
        variable acc_arr : int_arr_t(0 to 1023);
        variable got     : integer;
    begin
        readline(vec_file, L);
        read(L, n_samples);
        assert n_samples > 0 and n_samples <= 1024
            report "tb_mac: bad N=" & integer'image(n_samples) severity failure;

        for i in 0 to n_samples-1 loop
            readline(vec_file, L);
            read(L, a_int);
            read(L, b_int);
            read(L, acc_exp);
            a_arr(i)   := a_int;
            b_arr(i)   := b_int;
            acc_arr(i) := acc_exp;
        end loop;

        -- 리셋과 clr
        rst <= '1';
        clr <= '0';
        in_valid <= '0';
        for i in 1 to 4 loop
            wait until rising_edge(clk); wait for 1 ns;
        end loop;

        rst <= '0';
        clr <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        clr <= '0';

        -- 파이프라인이 비어 있을 때 acc_out=0
        wait until rising_edge(clk); wait for 1 ns;
        assert acc_out = to_signed(0, 40)
            report "after clr: acc_out should be 0"
            severity error;

        -- 한 cycle 에 한 샘플씩 push.
        for i in 0 to n_samples-1 loop
            a_in     <= to_signed(a_arr(i), 16);
            b_in     <= to_signed(b_arr(i), 16);
            in_valid <= '1';
            wait until rising_edge(clk); wait for 1 ns;
        end loop;
        in_valid <= '0';

        -- 마지막 입력에서 누산 완료까지 3-cycle 지연.
        for i in 1 to 3 loop
            wait until rising_edge(clk); wait for 1 ns;
        end loop;

        got := to_integer(acc_out);
        assert got = acc_arr(n_samples-1)
            report "tb_mac: final acc mismatch: got=" & integer'image(got) &
                   " expected=" & integer'image(acc_arr(n_samples-1))
            severity error;

        -- 부분 누산도 검증: 매 입력 후 3 cycle 지점의 acc_out 가 acc_arr(i) 와 동일해야 한다.
        -- 위 시퀀스는 한꺼번에 push 했으므로 이미 끝났다. 별도 시나리오로 다시.
        rst <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        rst <= '0';
        clr <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        clr <= '0';
        wait until rising_edge(clk); wait for 1 ns;

        for i in 0 to n_samples-1 loop
            a_in     <= to_signed(a_arr(i), 16);
            b_in     <= to_signed(b_arr(i), 16);
            in_valid <= '1';
            wait until rising_edge(clk); wait for 1 ns;
            -- 이 시점에 i 번째 입력이 stage 1 레지스터에 막 들어갔다.
            -- in_valid 를 0 으로 떨어뜨려도 in-flight 데이터는 진행한다.
            in_valid <= '0';

            -- 3 cycle 후 누산이 완료된다.
            for k in 1 to 3 loop
                wait until rising_edge(clk); wait for 1 ns;
            end loop;

            got := to_integer(acc_out);
            assert got = acc_arr(i)
                report "tb_mac: partial acc mismatch at i=" & integer'image(i) &
                       " got=" & integer'image(got) &
                       " expected=" & integer'image(acc_arr(i))
                severity error;
        end loop;

        report "tb_mac: PASS (" & integer'image(n_samples) & " samples, bit-exact)";
        sim_done <= true;
        wait;
    end process;
end architecture;
```

- [ ] **Step 2: Stub RTL — 항상 0 반환**

Create `/Users/chan-uhyeon/Programming/fpga/04_fixed_point/rtl/mac.vhd`:

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.fixed_point_pkg.all;

entity mac is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        clr       : in  std_logic;
        in_valid  : in  std_logic;
        a_in      : in  q15_t;
        b_in      : in  q15_t;
        acc_out   : out signed(39 downto 0);
        out_valid : out std_logic
    );
end entity;

architecture rtl of mac is
begin
    acc_out   <= (others => '0');
    out_valid <= '0';
end architecture;
```

- [ ] **Step 3: Run, verify FAIL**

```bash
cd /Users/chan-uhyeon/Programming/fpga/04_fixed_point
make test
```
Expected: 첫 비-zero 누산값 검증에서 mismatch FAIL.

- [ ] **Step 4: 구현**

Overwrite `/Users/chan-uhyeon/Programming/fpga/04_fixed_point/rtl/mac.vhd`:

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.fixed_point_pkg.all;

entity mac is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        clr       : in  std_logic;       -- 1 cycle assert 시 acc 를 0으로
        in_valid  : in  std_logic;
        a_in      : in  q15_t;
        b_in      : in  q15_t;
        acc_out   : out signed(39 downto 0);
        out_valid : out std_logic        -- 입력 후 3 cycle 지점에 1-cycle pulse
    );
end entity;

architecture rtl of mac is
    -- Stage 1: 입력 레지스터
    signal a_s1, b_s1 : q15_t := (others => '0');
    signal v_s1       : std_logic := '0';
    -- Stage 2: 곱셈 레지스터 (Q2.30, 32-bit)
    signal p_s2       : q230_t := (others => '0');
    signal v_s2       : std_logic := '0';
    -- Stage 3: 누산 레지스터 (40-bit, 약 8 guard bits 확보)
    signal acc_r      : signed(39 downto 0) := (others => '0');
    signal v_s3       : std_logic := '0';
begin
    pipeline : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                a_s1 <= (others => '0');
                b_s1 <= (others => '0');
                v_s1 <= '0';
                p_s2 <= (others => '0');
                v_s2 <= '0';
                acc_r <= (others => '0');
                v_s3 <= '0';
            else
                -- Stage 1
                a_s1 <= a_in;
                b_s1 <= b_in;
                v_s1 <= in_valid;

                -- Stage 2 (곱셈은 조합, 결과만 register)
                p_s2 <= q15_mul(a_s1, b_s1);
                v_s2 <= v_s1;

                -- Stage 3 (누산 + 동기 clear)
                if clr = '1' then
                    acc_r <= (others => '0');
                elsif v_s2 = '1' then
                    acc_r <= acc_r + resize(p_s2, 40);
                end if;
                v_s3 <= v_s2;
            end if;
        end if;
    end process;

    acc_out   <= acc_r;
    out_valid <= v_s3;
end architecture;
```

- [ ] **Step 5: Run, verify PASS**

```bash
cd /Users/chan-uhyeon/Programming/fpga/04_fixed_point
make clean && make test
```
Expected: `tb_mac: PASS (16 samples, bit-exact)`.

- [ ] **Step 6: Root sweep**

```bash
cd /Users/chan-uhyeon/Programming/fpga
make clean && make test
```
Expected: 모든 주차(1+2+3+4) testbench PASS.

- [ ] **Step 7: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add common/fixed_point_pkg.vhd \
        04_fixed_point/Makefile \
        04_fixed_point/rtl/mac.vhd \
        04_fixed_point/tb/tb_mac.vhd \
        04_fixed_point/scripts/gen_mac_vectors.py \
        common/Makefile.common .gitignore
git commit -m "feat(04): add fixed_point_pkg and 3-stage pipelined MAC with bit-exact tb"
```

---

## Task 3: Week 4 README + 학습 일지

- [ ] **Step 1: README**

Create `/Users/chan-uhyeon/Programming/fpga/04_fixed_point/README.md`:

```markdown
# Week 4 — 고정소수점 + 3-스테이지 파이프라인 MAC

## 모듈
| 모듈 | 파일 | 설명 |
|---|---|---|
| `fixed_point_pkg` | `../common/fixed_point_pkg.vhd` | Q1.15 ↔ real, Q2.30 곱셈, 라운딩 saturate |
| `mac` | `rtl/mac.vhd` | 3-stage 파이프라인 (input reg → mul reg → acc reg). 3-cycle latency |

## 검증
- `tb_mac`: Python(NumPy)이 미리 만든 16-sample 벡터(`data/mac_vectors.txt`)를 한 줄씩 읽어, 마지막 누산과 매 샘플별 부분 누산 둘 다 비트 정합 비교.

## 실행
```
make test
```
`make` 가 자동으로 venv Python을 호출해 골든 벡터를 생성한 뒤 GHDL 시뮬을 돌린다.

## 배운 것
- Q-format: 정수 레지스터에 가상 소수점 위치를 약속해 두는 표현. Q1.15는 1-bit sign + 15-bit fraction, 범위 [-1, 1).
- 곱셈 후 비트 폭: Q1.15 × Q1.15 = Q2.30 (32-bit signed). 부호 비트 1개가 두 배로 늘어나는 것은 numeric_std signed 곱셈의 일반 규칙.
- 파이프라인: stage 1 (input flop) → stage 2 (mul flop) → stage 3 (acc flop). 동기 clr 은 stage 3 직접 reset.
- Bit-exact 비교: VHDL `integer(real)`(round-half-to-even) 과 numpy.round 가 동일한 양자화를 하므로 가능. 한 LSB만 차이 나도 round 모드 mismatch 의 신호.
```

- [ ] **Step 2: 학습 일지**

Create `/Users/chan-uhyeon/Programming/fpga/notes/week-04.md`:

```markdown
# Week 4 학습 일지

## 새로 알게 된 것
- **Q-format 핵심**: "정수 레지스터인데, 그 정수를 2^F 로 나눈 값으로 해석하기로 약속" 만으로 끝. 하드웨어는 그냥 정수 산술. 약속만 다르므로 비트 비용은 없다.
- **곱셈 후 폭 증가**: Q1.15 × Q1.15 → Q2.30 (32-bit). 부호 비트가 두 개로 보일 수 있어 위쪽 비트 1개는 redundant sign이며, 정상 범위 [-1, 1) × [-1, 1) ⊂ [-1, 1] 이라 bit 30 만 의미 있는 정수 비트. 실제 정수 비트 1개로 다시 돌리려면 shift_right(15) + saturate.
- **파이프라인 latency 와 throughput 분리**: stage 가 늘어도 throughput 은 cycle 당 1 sample 그대로. latency 만 늘어 fmax (clock 속도) 가 올라간다는 게 핵심 가치.
- **VHDL 의 integer(real) 라운딩 모드**: ties-to-even (banker's). numpy.round 와 일치하므로 골든값 비트 정합이 가능. C 의 (int)cast 는 truncate-toward-zero 이므로 다르다.
- **textio 의 file path**: GHDL 은 `ghdl -r tb_mac` 실행 시점의 cwd 기준으로 file 경로를 해석. Makefile 이 항상 04_fixed_point/ 에서 실행하므로 `data/mac_vectors.txt` 상대경로가 통한다.

## 막힌 지점 / 디버깅
- (실제 작업 중 기록)

## Phase 2 진입 자가체크
- Q1.15, Q2.30 의 비트 폭과 의미를 1줄로 답할 수 있는가?
- 3-stage 파이프라인에서 in_valid → out_valid 사이 클럭 수는?
- bit-exact 검증이 가능한 조건 (라운딩 모드 + 양자화 일치) 을 한 문장으로?
```

- [ ] **Step 3: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 04_fixed_point/README.md notes/week-04.md
git commit -m "docs(04): add week 4 README and learning log"
```

---

## 완료 기준
- 루트 `make test` 한 번에 Week 1~4 합 8개 testbench PASS.
- `tb_mac` 가 Python 골든 벡터와 비트 정합으로 16 샘플 검증.
- `common/fixed_point_pkg` 가 Week 5/6 에서도 재사용 가능한 형태.

## 범위 밖 (Week 5+)
- Q1.15 외 다른 Q-format 일반화 (variable F 인자) — Week 5에서 ROM 계수 폭 결정 시 도입 검토.
- saturate vs wrap 옵션 — 본 패키지는 saturate 만 제공.
- 별도 `tb_fixed_point_pkg` 단위 테스트 — MAC 비트 정합으로 간접 검증되므로 YAGNI.
