# Phase 1 Week 1 — 조합 논리와 VHDL 기본 문법 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VHDL 문법 기초(entity/architecture, process, std_logic_vector)를 익히고, 4-bit ALU·4-to-1 mux·8-to-3 priority encoder를 self-checking testbench와 함께 구현한다.

**Architecture:** 각 모듈은 `rtl/`에 설계, `tb/`에 testbench로 분리한다. 모든 검증은 `ghdl`로 자동 실행되며 `assert`로 PASS/FAIL을 판정한다. 주차 루트에 `Makefile`을 두어 `make test` 한 줄로 전 testbench를 실행한다.

**Tech Stack:** VHDL-2008, GHDL (mcode backend), Surfer (GTKWave 후속), GNU Make, macOS Homebrew.

---

## File Structure

생성할 파일:

```
fpga/
├── Makefile                                   # 루트: make test 전파
├── README.md                                  # 레포 개요
├── .gitignore                                 # *.o, work-*, *.cf, *.vcd
├── common/
│   └── Makefile.common                        # 주차 Makefile 공통 규칙 (include용)
└── 01_combinational/
    ├── Makefile                               # week별 빌드 (common include)
    ├── README.md                              # week 개요·검증 결과
    ├── rtl/
    │   ├── alu.vhd                            # 4-bit ALU
    │   ├── mux4.vhd                           # 4-to-1 mux
    │   └── priority_encoder.vhd               # 8-to-3 priority encoder
    └── tb/
        ├── tb_alu.vhd
        ├── tb_mux4.vhd
        └── tb_priority_encoder.vhd
```

각 파일의 책임:
- `rtl/*.vhd` — 합성 가능한 조합 회로 설계. 상태·클럭 없음.
- `tb/tb_*.vhd` — 해당 모듈을 인스턴스화하고 `assert`로 모든 케이스 검증. 마지막에 "PASS" 또는 fatal 레벨 assert로 종료.
- `01_combinational/Makefile` — `common/Makefile.common`을 include하고 모듈 목록만 나열.
- `common/Makefile.common` — ghdl 명령과 공통 테스트 실행 타깃 정의.
- 루트 `Makefile` — 하위 주차 폴더들을 순회하며 `make test`를 전파.

---

## Task 0: 툴체인과 레포 스켈레톤

**Files:**
- Create: `/Users/chan-uhyeon/Programming/fpga/README.md`
- Create: `/Users/chan-uhyeon/Programming/fpga/.gitignore`
- Create: `/Users/chan-uhyeon/Programming/fpga/Makefile`
- Create: `/Users/chan-uhyeon/Programming/fpga/common/Makefile.common`

- [ ] **Step 1: GHDL과 Surfer 설치**

Run:
```bash
brew install ghdl
brew install --cask surfer
```
Expected: 설치 완료. `ghdl --version`이 버전(예: `GHDL 4.x.x`)을 출력.

GHDL이 이미 있다면 넘어간다. 버전이 3.x 이하라도 VHDL-2008 지원되면 충분. (GTKWave는 2025-10-29부 Homebrew disabled — Surfer로 대체.)

- [ ] **Step 2: 설치 검증**

Run:
```bash
ghdl --version && surfer --version
```
Expected: 두 툴 모두 버전 출력.

- [ ] **Step 3: `.gitignore` 작성**

Create `/Users/chan-uhyeon/Programming/fpga/.gitignore`:
```
# GHDL artifacts
*.o
*.cf
work-obj*.cf
*-obj*.cf
e~*.o

# Waveforms
*.vcd
*.ghw

# OS
.DS_Store
```

- [ ] **Step 4: `common/Makefile.common` 작성**

Create `/Users/chan-uhyeon/Programming/fpga/common/Makefile.common`:
```make
# 모든 주차 Makefile이 include하는 공통 규칙.
# 주차 Makefile은 MODULES 변수를 정의해야 한다. 예: MODULES := alu mux4 priority_encoder

GHDL      ?= ghdl
GHDL_FLAGS ?= --std=08 --workdir=work
WORK      := work

RTL_DIR := rtl
TB_DIR  := tb

RTL_SRCS := $(wildcard $(RTL_DIR)/*.vhd)
TB_SRCS  := $(foreach m,$(MODULES),$(TB_DIR)/tb_$(m).vhd)

.PHONY: all test clean wave

all: test

$(WORK):
	mkdir -p $(WORK)

# 모든 소스를 분석
analyze: | $(WORK)
	$(GHDL) -a $(GHDL_FLAGS) $(RTL_SRCS) $(TB_SRCS)

# 각 모듈에 대해 elaborate + run.
# testbench 엔티티 이름은 tb_<module> 가정.
test: analyze
	@set -e; \
	failed=0; \
	for m in $(MODULES); do \
		echo "=== Running tb_$$m ==="; \
		$(GHDL) -e $(GHDL_FLAGS) tb_$$m; \
		if $(GHDL) -r $(GHDL_FLAGS) tb_$$m --assert-level=error; then \
			echo "  PASS: tb_$$m"; \
		else \
			echo "  FAIL: tb_$$m"; \
			failed=1; \
		fi; \
	done; \
	if [ $$failed -ne 0 ]; then echo "*** SOME TESTS FAILED ***"; exit 1; fi; \
	echo "*** ALL TESTS PASSED ***"

# 특정 모듈 파형 저장: make wave MODULE=alu
wave: analyze
	@if [ -z "$(MODULE)" ]; then echo "Usage: make wave MODULE=<name>"; exit 1; fi
	$(GHDL) -e $(GHDL_FLAGS) tb_$(MODULE)
	$(GHDL) -r $(GHDL_FLAGS) tb_$(MODULE) --vcd=tb_$(MODULE).vcd || true
	surfer tb_$(MODULE).vcd &

clean:
	rm -rf $(WORK) *.cf *.vcd *.ghw e~*.o
```

- [ ] **Step 5: 루트 `Makefile` 작성**

Create `/Users/chan-uhyeon/Programming/fpga/Makefile`:
```make
# 모든 주차 폴더에 make test 전파

WEEKS := $(sort $(wildcard [0-9][0-9]_*))

.PHONY: all test clean

all: test

test:
	@set -e; \
	for w in $(WEEKS); do \
		echo ">>> Week: $$w"; \
		$(MAKE) -C $$w test; \
	done; \
	echo "=== ALL WEEKS PASSED ==="

clean:
	@for w in $(WEEKS); do \
		$(MAKE) -C $$w clean; \
	done
```

- [ ] **Step 6: 루트 `README.md` 작성**

Create `/Users/chan-uhyeon/Programming/fpga/README.md`:
```markdown
# FPGA VHDL DSP 학습 레포

8주 커리큘럼. 설계 문서: [docs/superpowers/specs/2026-04-18-fpga-vhdl-dsp-learning-plan-design.md](docs/superpowers/specs/2026-04-18-fpga-vhdl-dsp-learning-plan-design.md).

## 요구 사항

- GHDL (VHDL-2008 지원 버전)
- Surfer (파형 뷰어)
- GNU Make

macOS:
```
brew install ghdl
brew install --cask surfer
```

## 실행

전체 테스트:
```
make test
```

특정 주차 테스트:
```
make -C 01_combinational test
```

파형 보기:
```
make -C 01_combinational wave MODULE=alu
```

## 디렉토리

- `01_combinational/` — Week 1: ALU, mux, encoder
- `common/` — 주차 간 공용 Makefile·VHDL 패키지
- `docs/` — 설계 문서, 구현 계획
```

- [ ] **Step 7: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add README.md .gitignore Makefile common/Makefile.common
git commit -m "chore: add repo skeleton and common Makefile"
```

---

## Task 1: 4-bit ALU entity + 첫 testbench (ADD만)

ALU는 점진적으로 만든다. 먼저 ADD만 구현해 toolchain과 testbench 패턴을 확인한 뒤 다른 op를 추가한다.

**Files:**
- Create: `/Users/chan-uhyeon/Programming/fpga/01_combinational/Makefile`
- Create: `/Users/chan-uhyeon/Programming/fpga/01_combinational/rtl/alu.vhd`
- Create: `/Users/chan-uhyeon/Programming/fpga/01_combinational/tb/tb_alu.vhd`

- [ ] **Step 1: 주차 Makefile 작성**

Create `/Users/chan-uhyeon/Programming/fpga/01_combinational/Makefile`:
```make
MODULES := alu

include ../common/Makefile.common
```

- [ ] **Step 2: 실패하는 testbench 작성 (ADD만)**

Create `/Users/chan-uhyeon/Programming/fpga/01_combinational/tb/tb_alu.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_alu is
end entity;

architecture sim of tb_alu is
    -- ALU operation codes
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";

    signal a, b  : std_logic_vector(3 downto 0) := (others => '0');
    signal op    : std_logic_vector(2 downto 0) := (others => '0');
    signal y     : std_logic_vector(3 downto 0);

    -- 기대값 계산 함수
    function expected(a_in, b_in : std_logic_vector(3 downto 0);
                      op_in : std_logic_vector(2 downto 0))
        return std_logic_vector is
        variable au, bu : unsigned(3 downto 0);
    begin
        au := unsigned(a_in);
        bu := unsigned(b_in);
        case op_in is
            when OP_ADD => return std_logic_vector(au + bu);
            when others => return (others => 'X');
        end case;
    end function;
begin
    dut : entity work.alu
        port map (a => a, b => b, op => op, y => y);

    stimulus : process
    begin
        -- ADD: 전 조합(16 x 16 = 256)을 순회
        op <= OP_ADD;
        for i in 0 to 15 loop
            for j in 0 to 15 loop
                a <= std_logic_vector(to_unsigned(i, 4));
                b <= std_logic_vector(to_unsigned(j, 4));
                wait for 1 ns;
                assert y = expected(a, b, op)
                    report "ADD fail: a=" & integer'image(i) &
                           " b=" & integer'image(j) &
                           " got=" & integer'image(to_integer(unsigned(y))) &
                           " expected=" & integer'image(to_integer(unsigned(expected(a,b,op))))
                    severity error;
            end loop;
        end loop;

        report "tb_alu: PASS";
        wait;
    end process;
end architecture;
```

- [ ] **Step 3: 빈 ALU entity 작성 (컴파일만 되는 수준)**

Create `/Users/chan-uhyeon/Programming/fpga/01_combinational/rtl/alu.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;

entity alu is
    port (
        a  : in  std_logic_vector(3 downto 0);
        b  : in  std_logic_vector(3 downto 0);
        op : in  std_logic_vector(2 downto 0);
        y  : out std_logic_vector(3 downto 0)
    );
end entity;

architecture rtl of alu is
begin
    y <= (others => '0');  -- stub: 항상 0 출력
end architecture;
```

- [ ] **Step 4: Test 실행해서 실패 확인**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga/01_combinational
make test
```
Expected: FAIL. `ADD fail: a=0 b=1 got=0 expected=1` 같은 에러 메시지가 먼저 나오고 `*** SOME TESTS FAILED ***`로 종료.

- [ ] **Step 5: ALU에 ADD 구현**

Edit `/Users/chan-uhyeon/Programming/fpga/01_combinational/rtl/alu.vhd`, 내용 전체 교체:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu is
    port (
        a  : in  std_logic_vector(3 downto 0);
        b  : in  std_logic_vector(3 downto 0);
        op : in  std_logic_vector(2 downto 0);
        y  : out std_logic_vector(3 downto 0)
    );
end entity;

architecture rtl of alu is
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
begin
    process(a, b, op)
        variable au, bu : unsigned(3 downto 0);
    begin
        au := unsigned(a);
        bu := unsigned(b);
        case op is
            when OP_ADD => y <= std_logic_vector(au + bu);
            when others => y <= (others => '0');
        end case;
    end process;
end architecture;
```

- [ ] **Step 6: Test 실행해서 통과 확인**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga/01_combinational
make test
```
Expected: `tb_alu: PASS`, `*** ALL TESTS PASSED ***`.

- [ ] **Step 7: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 01_combinational/
git commit -m "feat(01): add ALU skeleton with ADD op and exhaustive testbench"
```

---

## Task 2: ALU에 SUB / AND / OR / XOR / SHL / SHR 추가

한 번에 한 op씩, TDD 사이클을 반복한다.

**Files:**
- Modify: `01_combinational/tb/tb_alu.vhd`
- Modify: `01_combinational/rtl/alu.vhd`

- [ ] **Step 1: testbench에 op code 상수와 SUB 검증 추가**

Edit `/Users/chan-uhyeon/Programming/fpga/01_combinational/tb/tb_alu.vhd`:

`constant OP_ADD` 아래에 추가:
```vhdl
    constant OP_SUB : std_logic_vector(2 downto 0) := "001";
    constant OP_AND : std_logic_vector(2 downto 0) := "010";
    constant OP_OR  : std_logic_vector(2 downto 0) := "011";
    constant OP_XOR : std_logic_vector(2 downto 0) := "100";
    constant OP_SHL : std_logic_vector(2 downto 0) := "101";  -- a << b[1:0]
    constant OP_SHR : std_logic_vector(2 downto 0) := "110";  -- a >> b[1:0]
```

`expected` 함수의 `case op_in`을 교체:
```vhdl
        case op_in is
            when OP_ADD => return std_logic_vector(au + bu);
            when OP_SUB => return std_logic_vector(au - bu);
            when OP_AND => return a_in and b_in;
            when OP_OR  => return a_in or  b_in;
            when OP_XOR => return a_in xor b_in;
            when OP_SHL => return std_logic_vector(shift_left (au, to_integer(bu(1 downto 0))));
            when OP_SHR => return std_logic_vector(shift_right(au, to_integer(bu(1 downto 0))));
            when others => return (others => 'X');
        end case;
```

`stimulus` process 내부의 `for i/j` 루프를 전체 op code 순회로 감싼다. 기존 `op <= OP_ADD;` 한 줄을 삭제하고 그 위치부터 `report "tb_alu: PASS";` 직전까지를 다음으로 교체:
```vhdl
        for op_i in 0 to 6 loop
            op <= std_logic_vector(to_unsigned(op_i, 3));
            for i in 0 to 15 loop
                for j in 0 to 15 loop
                    a <= std_logic_vector(to_unsigned(i, 4));
                    b <= std_logic_vector(to_unsigned(j, 4));
                    wait for 1 ns;
                    assert y = expected(a, b, op)
                        report "op=" & integer'image(op_i) &
                               " a=" & integer'image(i) &
                               " b=" & integer'image(j) &
                               " got=" & integer'image(to_integer(unsigned(y))) &
                               " expected=" & integer'image(to_integer(unsigned(expected(a,b,op))))
                        severity error;
                end loop;
            end loop;
        end loop;
```

- [ ] **Step 2: Test 실행해서 실패 확인**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga/01_combinational
make test
```
Expected: FAIL. `op=1 ...` (SUB)에서 mismatch.

- [ ] **Step 3: ALU에 나머지 op 추가**

Edit `/Users/chan-uhyeon/Programming/fpga/01_combinational/rtl/alu.vhd` — `architecture rtl` 전체 교체:
```vhdl
architecture rtl of alu is
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_SUB : std_logic_vector(2 downto 0) := "001";
    constant OP_AND : std_logic_vector(2 downto 0) := "010";
    constant OP_OR  : std_logic_vector(2 downto 0) := "011";
    constant OP_XOR : std_logic_vector(2 downto 0) := "100";
    constant OP_SHL : std_logic_vector(2 downto 0) := "101";
    constant OP_SHR : std_logic_vector(2 downto 0) := "110";
begin
    process(a, b, op)
        variable au, bu : unsigned(3 downto 0);
    begin
        au := unsigned(a);
        bu := unsigned(b);
        case op is
            when OP_ADD => y <= std_logic_vector(au + bu);
            when OP_SUB => y <= std_logic_vector(au - bu);
            when OP_AND => y <= a and b;
            when OP_OR  => y <= a or  b;
            when OP_XOR => y <= a xor b;
            when OP_SHL => y <= std_logic_vector(shift_left (au, to_integer(bu(1 downto 0))));
            when OP_SHR => y <= std_logic_vector(shift_right(au, to_integer(bu(1 downto 0))));
            when others => y <= (others => '0');
        end case;
    end process;
end architecture;
```

- [ ] **Step 4: Test 실행해서 통과 확인**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga/01_combinational
make test
```
Expected: `tb_alu: PASS`.

- [ ] **Step 5: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 01_combinational/rtl/alu.vhd 01_combinational/tb/tb_alu.vhd
git commit -m "feat(01): extend ALU with SUB/AND/OR/XOR/SHL/SHR"
```

---

## Task 3: 4-to-1 MUX

**Files:**
- Modify: `01_combinational/Makefile`
- Create: `01_combinational/rtl/mux4.vhd`
- Create: `01_combinational/tb/tb_mux4.vhd`

- [ ] **Step 1: Makefile의 MODULES에 `mux4` 추가**

Edit `/Users/chan-uhyeon/Programming/fpga/01_combinational/Makefile`:
```make
MODULES := alu mux4

include ../common/Makefile.common
```

- [ ] **Step 2: testbench 먼저 작성**

Create `/Users/chan-uhyeon/Programming/fpga/01_combinational/tb/tb_mux4.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_mux4 is
end entity;

architecture sim of tb_mux4 is
    signal d0, d1, d2, d3 : std_logic_vector(7 downto 0) := (others => '0');
    signal sel            : std_logic_vector(1 downto 0) := "00";
    signal y              : std_logic_vector(7 downto 0);
begin
    dut : entity work.mux4
        generic map (WIDTH => 8)
        port map (d0 => d0, d1 => d1, d2 => d2, d3 => d3, sel => sel, y => y);

    stimulus : process
        variable exp : std_logic_vector(7 downto 0);
    begin
        -- 고정 값으로 4개 채널 구분
        d0 <= x"A0";
        d1 <= x"B1";
        d2 <= x"C2";
        d3 <= x"D3";

        for s in 0 to 3 loop
            sel <= std_logic_vector(to_unsigned(s, 2));
            wait for 1 ns;
            case s is
                when 0 => exp := x"A0";
                when 1 => exp := x"B1";
                when 2 => exp := x"C2";
                when 3 => exp := x"D3";
                when others => exp := (others => 'X');
            end case;
            assert y = exp
                report "mux4 fail: sel=" & integer'image(s) &
                       " got=" & integer'image(to_integer(unsigned(y)))
                severity error;
        end loop;

        report "tb_mux4: PASS";
        wait;
    end process;
end architecture;
```

- [ ] **Step 3: stub entity 작성**

Create `/Users/chan-uhyeon/Programming/fpga/01_combinational/rtl/mux4.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;

entity mux4 is
    generic (
        WIDTH : positive := 8
    );
    port (
        d0, d1, d2, d3 : in  std_logic_vector(WIDTH-1 downto 0);
        sel            : in  std_logic_vector(1 downto 0);
        y              : out std_logic_vector(WIDTH-1 downto 0)
    );
end entity;

architecture rtl of mux4 is
begin
    y <= (others => '0');  -- stub
end architecture;
```

- [ ] **Step 4: Test 실행해서 실패 확인**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga/01_combinational
make test
```
Expected: `tb_alu: PASS`, 이어서 `mux4 fail: sel=0 got=0`으로 FAIL 종료.

- [ ] **Step 5: mux4 구현**

Edit `/Users/chan-uhyeon/Programming/fpga/01_combinational/rtl/mux4.vhd` — architecture 전체 교체:
```vhdl
architecture rtl of mux4 is
begin
    with sel select
        y <= d0 when "00",
             d1 when "01",
             d2 when "10",
             d3 when others;
end architecture;
```

- [ ] **Step 6: Test 통과 확인**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga/01_combinational
make test
```
Expected: 두 testbench 모두 PASS.

- [ ] **Step 7: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 01_combinational/Makefile 01_combinational/rtl/mux4.vhd 01_combinational/tb/tb_mux4.vhd
git commit -m "feat(01): add parameterized 4-to-1 mux with testbench"
```

---

## Task 4: 8-to-3 Priority Encoder

입력 비트 중 가장 높은 번호의 `'1'` 위치를 출력하고, 모두 0이면 `valid` 플래그를 0으로.

**Files:**
- Modify: `01_combinational/Makefile`
- Create: `01_combinational/rtl/priority_encoder.vhd`
- Create: `01_combinational/tb/tb_priority_encoder.vhd`

- [ ] **Step 1: Makefile의 MODULES에 `priority_encoder` 추가**

Edit `/Users/chan-uhyeon/Programming/fpga/01_combinational/Makefile`:
```make
MODULES := alu mux4 priority_encoder

include ../common/Makefile.common
```

- [ ] **Step 2: testbench 먼저 작성**

Create `/Users/chan-uhyeon/Programming/fpga/01_combinational/tb/tb_priority_encoder.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_priority_encoder is
end entity;

architecture sim of tb_priority_encoder is
    signal d     : std_logic_vector(7 downto 0) := (others => '0');
    signal y     : std_logic_vector(2 downto 0);
    signal valid : std_logic;

    -- 기대값: 가장 높은 '1' 비트의 인덱스. 모두 0이면 valid=0.
    procedure expected_of(d_in : in std_logic_vector(7 downto 0);
                          exp_y : out std_logic_vector(2 downto 0);
                          exp_valid : out std_logic) is
    begin
        exp_valid := '0';
        exp_y := (others => '0');
        for i in 7 downto 0 loop
            if d_in(i) = '1' then
                exp_y := std_logic_vector(to_unsigned(i, 3));
                exp_valid := '1';
                exit;
            end if;
        end loop;
    end procedure;
begin
    dut : entity work.priority_encoder
        port map (d => d, y => y, valid => valid);

    stimulus : process
        variable exp_y : std_logic_vector(2 downto 0);
        variable exp_valid : std_logic;
    begin
        -- 전 256 조합 순회
        for i in 0 to 255 loop
            d <= std_logic_vector(to_unsigned(i, 8));
            wait for 1 ns;
            expected_of(std_logic_vector(to_unsigned(i, 8)), exp_y, exp_valid);
            assert y = exp_y and valid = exp_valid
                report "priority_encoder fail: d=" & integer'image(i) &
                       " got_y=" & integer'image(to_integer(unsigned(y))) &
                       " got_valid=" & std_logic'image(valid) &
                       " exp_y=" & integer'image(to_integer(unsigned(exp_y))) &
                       " exp_valid=" & std_logic'image(exp_valid)
                severity error;
        end loop;

        report "tb_priority_encoder: PASS";
        wait;
    end process;
end architecture;
```

- [ ] **Step 3: stub entity 작성**

Create `/Users/chan-uhyeon/Programming/fpga/01_combinational/rtl/priority_encoder.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;

entity priority_encoder is
    port (
        d     : in  std_logic_vector(7 downto 0);
        y     : out std_logic_vector(2 downto 0);
        valid : out std_logic
    );
end entity;

architecture rtl of priority_encoder is
begin
    y     <= (others => '0');
    valid <= '0';
end architecture;
```

- [ ] **Step 4: Test 실행해서 실패 확인**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga/01_combinational
make test
```
Expected: 앞 두 testbench 통과, `priority_encoder fail: d=1 ...`로 FAIL.

- [ ] **Step 5: priority_encoder 구현**

Edit `/Users/chan-uhyeon/Programming/fpga/01_combinational/rtl/priority_encoder.vhd` — architecture 전체 교체:
```vhdl
architecture rtl of priority_encoder is
begin
    process(d)
        variable y_v     : std_logic_vector(2 downto 0);
        variable valid_v : std_logic;
    begin
        y_v     := (others => '0');
        valid_v := '0';
        for i in 7 downto 0 loop
            if d(i) = '1' then
                y_v     := std_logic_vector(to_unsigned(i, 3));
                valid_v := '1';
                exit;
            end if;
        end loop;
        y     <= y_v;
        valid <= valid_v;
    end process;
end architecture;
```

numeric_std 사용을 위해 파일 상단 use clause 확인:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
```
(stub에서 numeric_std를 import하지 않았다면 이 줄을 추가한다.)

- [ ] **Step 6: Test 통과 확인**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga/01_combinational
make test
```
Expected: 3개 testbench 모두 PASS, `*** ALL TESTS PASSED ***`.

- [ ] **Step 7: 루트에서 전체 실행해서 파이프라인 확인**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga
make test
```
Expected: `>>> Week: 01_combinational`, 3개 PASS, `=== ALL WEEKS PASSED ===`.

- [ ] **Step 8: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 01_combinational/Makefile 01_combinational/rtl/priority_encoder.vhd 01_combinational/tb/tb_priority_encoder.vhd
git commit -m "feat(01): add 8-to-3 priority encoder with exhaustive testbench"
```

---

## Task 5: Week 1 README와 학습 일지

- [ ] **Step 1: 주차 README 작성**

Create `/Users/chan-uhyeon/Programming/fpga/01_combinational/README.md`:
```markdown
# Week 1 — 조합 논리와 VHDL 기본 문법

## 모듈

| 모듈 | 파일 | 설명 |
|---|---|---|
| `alu` | `rtl/alu.vhd` | 4-bit ALU (ADD/SUB/AND/OR/XOR/SHL/SHR) |
| `mux4` | `rtl/mux4.vhd` | 파라미터화된 4-to-1 mux |
| `priority_encoder` | `rtl/priority_encoder.vhd` | 8-to-3 priority encoder (valid 플래그 포함) |

## 검증

모든 모듈은 exhaustive testbench로 검증된다:
- ALU: 7 op × 16 × 16 = 1,792 케이스
- mux4: 4 케이스 (sel 값 전부)
- priority_encoder: 256 케이스 (8-bit 입력 전부)

실행:
```
make test
```

파형:
```
make wave MODULE=alu
```

## 배운 것

- `entity` / `architecture` / `generic` / `port`
- `std_logic_vector` ↔ `unsigned`/`signed` 변환 (numeric_std)
- 조합 회로 기술 2가지: selected signal assignment (`with-select`) vs process + case
- `assert ... severity error` + GHDL `--assert-level=error`로 testbench 실패를 exit code에 반영
```

- [ ] **Step 2: 학습 일지 초안 작성**

Create `/Users/chan-uhyeon/Programming/fpga/notes/week-01.md`:
```markdown
# Week 1 학습 일지

## 새로 알게 된 것

- VHDL은 `std_logic_vector` 자체로는 산술 연산이 안 되고 `numeric_std`의 `unsigned`/`signed`로 캐스팅해야 한다.
- process 안의 `variable`은 즉시 업데이트되지만 `signal`은 delta cycle 이후 반영된다. testbench의 `expected(a,b,op)` 호출이 signal 값을 읽을 때 왜 `wait for 1 ns` 뒤여야 하는지와 직결.
- GHDL은 기본적으로 assert가 실패해도 exit code 0을 반환한다. `--assert-level=error` 플래그로 exit code에 반영시킬 수 있다 (Makefile 참고).

## 막힌 지점 / 디버깅

- (실제 작업 중 기록)

## 다음 주 예열

- FSM/순차 회로 진입. clock·reset 처리 패턴 미리 한 번 읽어보기.
```

- [ ] **Step 3: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
mkdir -p notes
git add 01_combinational/README.md notes/week-01.md
git commit -m "docs(01): add week 1 README and learning log template"
```

---

## Task 6: 회고와 Week 2 진입 판단

- [ ] **Step 1: `make clean` 확인**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga
make clean && make test
```
Expected: clean 빌드로도 전 테스트 통과.

- [ ] **Step 2: 파형 확인 한 번**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga/01_combinational
make wave MODULE=alu
```
Expected: Surfer가 열리고 `a`, `b`, `op`, `y` 신호가 보인다. 창 닫고 돌아온다.

- [ ] **Step 3: 자가 체크리스트**

notes/week-01.md의 "막힌 지점" 섹션에 다음 질문에 대한 답을 기록:
- entity/architecture 분리를 왜 하는지 한 줄로 설명 가능한가?
- `std_logic_vector`와 `unsigned`의 차이를 한 줄로 설명 가능한가?
- testbench에서 `wait for 1 ns`를 넣는 이유를 설명할 수 있는가?
- `make test`가 실패 시 exit 1을 반환하는 이유(--assert-level=error)를 아는가?

4개 중 3개 이상 자신 있으면 Week 2 plan 작성을 요청한다. 2개 이하면 다음 질문과 함께 복기 요청:
> "Week 1에서 X, Y가 불확실합니다. 짧은 요약과 추가 예제 부탁드려요."

- [ ] **Step 4: 최종 commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add notes/week-01.md
git commit -m "docs(01): fill in week 1 retrospective" || true
```

(변경이 없으면 `|| true`로 넘어간다.)

---

## 완료 기준

- `make test` 루트에서 실행 시 3개 testbench 모두 PASS.
- ALU가 7개 op를 exhaustive하게 검증.
- priority_encoder가 256 케이스 전부 검증.
- `notes/week-01.md`에 회고 작성됨.
- 커밋 5~7개로 히스토리가 증분적.

## 범위 밖 (Week 2 이후)

- 클럭·순차 회로·FSM — Week 2
- UART 송신기 — Week 2
- 테스트 커버리지 측정 — 현재는 exhaustive 입력으로 대체
