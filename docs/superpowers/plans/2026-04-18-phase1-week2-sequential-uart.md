# Phase 1 Week 2 — 순차 회로, FSM, UART 송신기 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 동기 카운터로 순차 회로 기본을 체득하고, Moore FSM 기반 UART 송신기(8-N-1, 파라미터화된 보드레이트)를 self-checking testbench와 함께 구현한다.

**Architecture:** `02_sequential_fsm/` 폴더에 `counter`(워밍업)와 `uart_tx`(메인) 두 모듈. 둘 다 `rtl/`와 `tb/`로 분리. `common/Makefile.common` 재사용. UART는 `CLK_FREQ_HZ`·`BAUD_RATE` generic으로 파라미터화해 테스트 속도를 조절 가능하게 한다.

**Tech Stack:** VHDL-2008, GHDL 6.0 LLVM, GNU Make.

---

## File Structure

```
02_sequential_fsm/
├── Makefile                    # MODULES := counter uart_tx, include ../common/Makefile.common
├── README.md
├── rtl/
│   ├── counter.vhd             # WIDTH-파라미터화 saturating counter, sync reset
│   └── uart_tx.vhd             # UART TX: FSM + baud counter + shift register
└── tb/
    ├── tb_counter.vhd
    └── tb_uart_tx.vhd

notes/week-02.md                # 학습 일지
```

---

## Task 0: Week 2 폴더 skeleton

**Files:**
- Create: `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/Makefile`
- Create: `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/rtl/` (empty dir — created implicitly by Makefile include; just ensure path exists)
- Create: `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/tb/`

- [ ] **Step 1: 폴더 생성**

```bash
mkdir -p /Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/rtl
mkdir -p /Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/tb
```

- [ ] **Step 2: Week Makefile**

Create `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/Makefile`:
```make
MODULES := counter uart_tx

include ../common/Makefile.common
```

- [ ] **Step 3: 루트에서 확인**

Run:
```bash
cd /Users/chan-uhyeon/Programming/fpga
make test
```
Expected: `>>> Week: 01_combinational` (통과) → `>>> Week: 02_sequential_fsm` (no sources → ghdl -a 에러 가능성 OR WEEKS 순회 중 실패).

실제로 이 단계에선 `MODULES := counter uart_tx`가 선언됐지만 rtl/*.vhd와 tb/tb_*.vhd가 없어 `ghdl -a`가 no-op 또는 비어있는 args로 에러 낼 수 있다. 이 경우 Task 1에서 counter를 추가하면서 해결된다. Step 3은 **에러가 나도 OK** — Task 0의 스코프는 디렉토리·Makefile 생성까지.

Note: `ghdl -a`는 empty 인자 리스트를 받으면 에러 없이 종료한다. 만약 문제가 생기면 Task 1에서 해결된다.

- [ ] **Step 4: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 02_sequential_fsm/Makefile
git commit -m "chore(02): add week 2 folder skeleton"
```

빈 디렉토리는 git 트래킹되지 않으므로 Makefile만 add.

---

## Task 1: 동기 saturating counter + testbench

순차 회로 기본 — 동기 리셋, enable, 포화(wraparound 없음).

**Files:**
- Create: `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/rtl/counter.vhd`
- Create: `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/tb/tb_counter.vhd`

- [ ] **Step 1: Testbench 먼저 작성**

Create `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/tb/tb_counter.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_counter is
end entity;

architecture sim of tb_counter is
    constant WIDTH     : positive := 4;
    constant CLK_PER   : time := 10 ns;

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '1';
    signal en    : std_logic := '0';
    signal q     : std_logic_vector(WIDTH-1 downto 0);
    signal saturated : std_logic;

    signal sim_done : boolean := false;
begin
    dut : entity work.counter
        generic map (WIDTH => WIDTH)
        port map (clk => clk, rst => rst, en => en, q => q, saturated => saturated);

    -- 클럭 생성
    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PER/2;
            clk <= '1'; wait for CLK_PER/2;
        end loop;
        wait;
    end process;

    stimulus : process
    begin
        -- 리셋 유지
        rst <= '1'; en <= '0';
        wait for 3 * CLK_PER;
        assert q = (q'range => '0')
            report "after reset q should be 0"
            severity error;
        assert saturated = '0'
            report "after reset saturated should be 0"
            severity error;

        -- 리셋 해제 후 en=0 유지: q 불변
        rst <= '0';
        wait for 3 * CLK_PER;
        assert q = (q'range => '0')
            report "en=0: q should not advance"
            severity error;

        -- en=1, 16번 카운트 (WIDTH=4, max=15)
        en <= '1';
        for i in 1 to 15 loop
            wait until rising_edge(clk);
            wait for 1 ns;  -- delta cycle 처리 여유
            assert unsigned(q) = to_unsigned(i, WIDTH)
                report "count fail at step " & integer'image(i) &
                       ": got=" & integer'image(to_integer(unsigned(q)))
                severity error;
        end loop;

        -- q=15 상태에서 saturated='1' 확인
        assert saturated = '1'
            report "saturated should assert when q=max"
            severity error;

        -- 추가 clock에도 q는 15에 고정 (포화)
        for i in 1 to 5 loop
            wait until rising_edge(clk);
            wait for 1 ns;
            assert unsigned(q) = to_unsigned(15, WIDTH)
                report "saturation fail: q should stay at 15"
                severity error;
        end loop;

        -- 재-리셋
        rst <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        assert q = (q'range => '0')
            report "re-reset fail"
            severity error;
        assert saturated = '0'
            report "re-reset saturated fail"
            severity error;

        report "tb_counter: PASS";
        sim_done <= true;
        wait;
    end process;
end architecture;
```

- [ ] **Step 2: Stub RTL**

Create `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/rtl/counter.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;

entity counter is
    generic (
        WIDTH : positive := 4
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;  -- active-high 동기 reset
        en        : in  std_logic;
        q         : out std_logic_vector(WIDTH-1 downto 0);
        saturated : out std_logic
    );
end entity;

architecture rtl of counter is
begin
    q <= (others => '0');
    saturated <= '0';
end architecture;
```

- [ ] **Step 3: Run test, verify FAIL**

```bash
cd /Users/chan-uhyeon/Programming/fpga/02_sequential_fsm
make test
```
Expected: FAIL — 첫 실패는 `count fail at step 1` 또는 리셋 해제 후 동작 불일치. 출력 첫 3~5줄 보고에 포함.

- [ ] **Step 4: 구현**

Overwrite `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/rtl/counter.vhd` entirely with:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
    generic (
        WIDTH : positive := 4
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;  -- active-high 동기 reset
        en        : in  std_logic;
        q         : out std_logic_vector(WIDTH-1 downto 0);
        saturated : out std_logic
    );
end entity;

architecture rtl of counter is
    constant MAX_VAL : unsigned(WIDTH-1 downto 0) := (others => '1');
    signal cnt : unsigned(WIDTH-1 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt <= (others => '0');
            elsif en = '1' and cnt /= MAX_VAL then
                cnt <= cnt + 1;
            end if;
        end if;
    end process;

    q <= std_logic_vector(cnt);
    saturated <= '1' when cnt = MAX_VAL else '0';
end architecture;
```

- [ ] **Step 5: Run test, verify PASS**

```bash
cd /Users/chan-uhyeon/Programming/fpga/02_sequential_fsm
make test
```
Expected: `tb_counter: PASS`, `*** ALL TESTS PASSED ***`.

- [ ] **Step 6: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 02_sequential_fsm/rtl/counter.vhd 02_sequential_fsm/tb/tb_counter.vhd
git commit -m "feat(02): add saturating sync counter with testbench"
```

---

## Task 2: UART TX entity skeleton + 실패하는 testbench

UART는 복잡하므로 entity + testbench 먼저, RTL은 Task 3에서.

**Files:**
- Create: `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/rtl/uart_tx.vhd`
- Create: `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/tb/tb_uart_tx.vhd`

**UART TX 프로토콜:** 8-N-1 (8 data bits, no parity, 1 stop bit). Idle=1, start bit=0, LSB-first data, stop bit=1.

- [ ] **Step 1: Stub uart_tx entity**

Create `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/rtl/uart_tx.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;

entity uart_tx is
    generic (
        CLK_FREQ_HZ : positive := 100_000_000;  -- 100 MHz
        BAUD_RATE   : positive := 115_200
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;              -- active-high 동기 reset
        tx_data : in  std_logic_vector(7 downto 0);
        tx_send : in  std_logic;              -- 1-cycle pulse to start send
        tx_busy : out std_logic;
        tx_line : out std_logic               -- serial out, idle='1'
    );
end entity;

architecture rtl of uart_tx is
begin
    -- stub: idle high, never busy, ignore input
    tx_busy <= '0';
    tx_line <= '1';
end architecture;
```

- [ ] **Step 2: Testbench 작성 — 시뮬 속도 위해 작은 generics**

시뮬 빠르게 하려고 CLK_FREQ_HZ=1_000_000, BAUD_RATE=100_000 → BIT_CLKS = 10 cycles/bit. 한 바이트 = 10 bits × 10 cycles = 100 cycles = 1 μs (10 ns 클럭 기준).

Create `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/tb/tb_uart_tx.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart_tx is
end entity;

architecture sim of tb_uart_tx is
    constant CLK_FREQ_HZ : positive := 1_000_000;
    constant BAUD_RATE   : positive := 100_000;
    constant BIT_CLKS    : positive := CLK_FREQ_HZ / BAUD_RATE;  -- 10
    constant CLK_PER     : time     := 10 ns;
    constant BIT_TIME    : time     := BIT_CLKS * CLK_PER;        -- 100 ns

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal tx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_send : std_logic := '0';
    signal tx_busy : std_logic;
    signal tx_line : std_logic;

    signal sim_done : boolean := false;

    -- 한 바이트 UART 수신 (비트 중앙 샘플링). 성공 시 data_out에 결과.
    procedure rx_byte(signal serial : in std_logic;
                      variable data_out : out std_logic_vector(7 downto 0)) is
        variable tmp : std_logic_vector(7 downto 0) := (others => '0');
    begin
        -- 현재 라인이 idle='1'이어야 함 (start bit=0 감지 대기는 호출자 책임)
        -- start bit의 중앙으로 이동: start bit 시작 후 BIT_TIME/2
        wait for BIT_TIME / 2;
        assert serial = '0'
            report "rx_byte: expected start bit=0 at mid"
            severity error;

        -- 데이터 8비트 LSB-first
        for i in 0 to 7 loop
            wait for BIT_TIME;
            tmp(i) := serial;
        end loop;

        -- stop bit
        wait for BIT_TIME;
        assert serial = '1'
            report "rx_byte: expected stop bit=1"
            severity error;

        data_out := tmp;
    end procedure;

begin
    dut : entity work.uart_tx
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            BAUD_RATE   => BAUD_RATE
        )
        port map (
            clk => clk, rst => rst,
            tx_data => tx_data, tx_send => tx_send,
            tx_busy => tx_busy, tx_line => tx_line
        );

    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PER/2;
            clk <= '1'; wait for CLK_PER/2;
        end loop;
        wait;
    end process;

    stimulus : process
        variable rx    : std_logic_vector(7 downto 0);
        variable bytes : std_logic_vector(7 downto 0);
    begin
        -- reset
        rst <= '1';
        wait for 3 * CLK_PER;
        rst <= '0';
        wait for 2 * CLK_PER;

        -- idle 확인
        assert tx_line = '1' and tx_busy = '0'
            report "initial: line should be idle(1), not busy"
            severity error;

        -- 한 바이트 0x55 송신
        tx_data <= x"55";
        tx_send <= '1';
        wait until rising_edge(clk);
        tx_send <= '0';

        -- tx_busy가 다음 클럭 내 올라와야 함
        wait for CLK_PER;
        assert tx_busy = '1'
            report "tx_busy should assert after tx_send"
            severity error;

        -- start bit가 곧 내려가야 함 (tx_line='0'). 기다려서 감지.
        wait until tx_line = '0';
        -- 이제 start bit 시작 지점. rx_byte 호출로 한 바이트 수신.
        rx_byte(tx_line, rx);
        assert rx = x"55"
            report "rx mismatch for 0x55: got=" & integer'image(to_integer(unsigned(rx)))
            severity error;

        -- stop bit 끝난 후 busy는 내려가야
        -- rx_byte가 stop bit 중앙에서 반환하므로 남은 BIT_TIME/2 + 여유 CLK_PER 대기
        wait for BIT_TIME / 2 + CLK_PER;
        assert tx_busy = '0'
            report "tx_busy should deassert after stop bit"
            severity error;
        assert tx_line = '1'
            report "tx_line should be idle after send"
            severity error;

        report "tb_uart_tx: PASS (0x55)";
        sim_done <= true;
        wait;
    end process;
end architecture;
```

- [ ] **Step 3: Run test, verify FAIL**

```bash
cd /Users/chan-uhyeon/Programming/fpga/02_sequential_fsm
make test
```
Expected: tb_counter PASS, tb_uart_tx FAIL. Stub은 tx_busy를 절대 올리지 않으므로 `tx_busy should assert after tx_send` assert가 먼저 발화하고, `--assert-level=error`로 시뮬이 즉시 정지 → 나머지 `wait until tx_line='0';` 등 행 이르지 않음. 그래도 안전을 위해 일반 `make test` 대신 타임아웃을 걸어 실행:

```bash
cd /Users/chan-uhyeon/Programming/fpga/02_sequential_fsm
timeout 30 make test; echo "exit=$?"
```

- [ ] **Step 4: Commit (stub + tb)**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 02_sequential_fsm/rtl/uart_tx.vhd 02_sequential_fsm/tb/tb_uart_tx.vhd
git commit -m "feat(02): add uart_tx stub and minimal testbench (failing)"
```

---

## Task 3: UART TX FSM 구현

**Files:**
- Modify: `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/rtl/uart_tx.vhd`

- [ ] **Step 1: RTL 전체 교체**

Overwrite `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/rtl/uart_tx.vhd` entirely with:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        CLK_FREQ_HZ : positive := 100_000_000;
        BAUD_RATE   : positive := 115_200
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        tx_data : in  std_logic_vector(7 downto 0);
        tx_send : in  std_logic;
        tx_busy : out std_logic;
        tx_line : out std_logic
    );
end entity;

architecture rtl of uart_tx is
    constant BIT_CLKS : positive := CLK_FREQ_HZ / BAUD_RATE;

    type state_t is (IDLE, START, DATA, STOP);
    signal state    : state_t := IDLE;

    signal baud_cnt : integer range 0 to BIT_CLKS-1 := 0;  -- cycles within current bit
    signal bit_idx  : integer range 0 to 7 := 0;           -- current data bit index (LSB-first)
    signal shreg    : std_logic_vector(7 downto 0) := (others => '0');
    signal line_r   : std_logic := '1';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state    <= IDLE;
                baud_cnt <= 0;
                bit_idx  <= 0;
                shreg    <= (others => '0');
                line_r   <= '1';
            else
                case state is
                    when IDLE =>
                        line_r   <= '1';
                        baud_cnt <= 0;
                        bit_idx  <= 0;
                        if tx_send = '1' then
                            shreg  <= tx_data;
                            state  <= START;
                            line_r <= '0';  -- start bit 즉시 발생
                        end if;

                    when START =>
                        line_r <= '0';
                        if baud_cnt = BIT_CLKS-1 then
                            baud_cnt <= 0;
                            state    <= DATA;
                            line_r   <= shreg(0);
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    when DATA =>
                        line_r <= shreg(bit_idx);
                        if baud_cnt = BIT_CLKS-1 then
                            baud_cnt <= 0;
                            if bit_idx = 7 then
                                bit_idx <= 0;
                                state   <= STOP;
                                line_r  <= '1';
                            else
                                bit_idx <= bit_idx + 1;
                                line_r  <= shreg(bit_idx + 1);
                            end if;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    when STOP =>
                        line_r <= '1';
                        if baud_cnt = BIT_CLKS-1 then
                            baud_cnt <= 0;
                            state    <= IDLE;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    tx_line <= line_r;
    tx_busy <= '0' when state = IDLE else '1';
end architecture;
```

- [ ] **Step 2: Run test, verify PASS**

```bash
cd /Users/chan-uhyeon/Programming/fpga/02_sequential_fsm
make test
```
Expected: 두 testbench 모두 PASS. 시뮬 종료 시간 ~1.2 μs.

- [ ] **Step 3: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 02_sequential_fsm/rtl/uart_tx.vhd
git commit -m "feat(02): implement uart_tx FSM with parameterized baud rate"
```

---

## Task 4: UART TX 확장 testbench — 다중 바이트·랜덤 입력

기존 tb를 확장해 back-to-back, 전 256개 바이트 값 커버.

**Files:**
- Modify: `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/tb/tb_uart_tx.vhd`

- [ ] **Step 1: Testbench 확장**

`stimulus : process` 블록을 찾아 기존 `report "tb_uart_tx: PASS (0x55)";` 이후에 (하지만 `sim_done <= true; wait;` 이전에) 다음 코드를 **추가**한다. 0x55 테스트는 그대로 두고 추가 테스트를 뒤에 붙인다:

먼저 stimulus process 내부에서 변경할 것:
- 기존 `report "tb_uart_tx: PASS (0x55)";` 줄을 삭제
- 기존 `sim_done <= true;` 와 `wait;` 직전에 다음 블록을 삽입

삽입할 블록:
```vhdl
        -- === 다중 바이트 테스트: 0x00 ~ 0xFF 전부 ===
        for v in 0 to 255 loop
            -- 이전 송신 완료까지 대기
            if tx_busy = '1' then
                wait until tx_busy = '0';
                wait for 2 * CLK_PER;
            end if;

            tx_data <= std_logic_vector(to_unsigned(v, 8));
            tx_send <= '1';
            wait until rising_edge(clk);
            tx_send <= '0';

            -- busy 확인
            wait for CLK_PER;
            assert tx_busy = '1'
                report "multi v=" & integer'image(v) & ": tx_busy not asserted"
                severity error;

            -- start bit 감지 후 한 바이트 수신
            wait until tx_line = '0';
            rx_byte(tx_line, rx);
            assert rx = std_logic_vector(to_unsigned(v, 8))
                report "multi v=" & integer'image(v) &
                       ": rx mismatch, got=" & integer'image(to_integer(unsigned(rx)))
                severity error;
        end loop;

        -- 송신 완료까지 정리
        if tx_busy = '1' then
            wait until tx_busy = '0';
        end if;

        report "tb_uart_tx: PASS (256 bytes)";
```

최종 stimulus process 끝부분은 다음 순서가 되어야 한다:
1. 기존 0x55 테스트 블록 (report 제거)
2. 위의 256-byte 루프 블록
3. `sim_done <= true;`
4. `wait;`

- [ ] **Step 2: Run test, verify PASS**

```bash
cd /Users/chan-uhyeon/Programming/fpga/02_sequential_fsm
make test
```
Expected: `tb_uart_tx: PASS (256 bytes)`. 시뮬 시간 약 256 × ~120 CLK_PER = ~307 μs.

- [ ] **Step 3: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 02_sequential_fsm/tb/tb_uart_tx.vhd
git commit -m "test(02): exhaustive 256-byte coverage for uart_tx"
```

---

## Task 5: Week 2 README와 학습 일지

**Files:**
- Create: `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/README.md`
- Create: `/Users/chan-uhyeon/Programming/fpga/notes/week-02.md`

- [ ] **Step 1: Week 2 README**

Create `/Users/chan-uhyeon/Programming/fpga/02_sequential_fsm/README.md`:
```markdown
# Week 2 — 순차 회로, FSM, UART 송신기

## 모듈

| 모듈 | 파일 | 설명 |
|---|---|---|
| `counter` | `rtl/counter.vhd` | WIDTH-파라미터화 saturating up-counter (동기 reset, en) |
| `uart_tx` | `rtl/uart_tx.vhd` | 8-N-1 UART 송신기 (Moore FSM: IDLE→START→DATA→STOP) |

## 검증

- `tb_counter`: 리셋·en=0 유지·카운트 0→15·포화·재-리셋 시나리오
- `tb_uart_tx`: CLK=1 MHz, BAUD=100 kHz (시뮬 가속) 설정으로 0x00~0xFF 256 바이트 back-to-back 송신, 시뮬 내 UART 수신 procedure로 검증

실행:
```
make test
```

## 배운 것

- `rising_edge(clk)` + 동기 reset 패턴 (비동기 reset 아님)
- `signal` vs `variable`: 클럭드 프로세스 내 `<=`는 이벤트 큐에 등록, 실제 반영은 다음 delta
- FSM 기술 스타일: 단일 `process(clk)` + `case state`
- Generic을 활용한 clock frequency·baud rate 파라미터화 → 시뮬 속도 자유 조절
```

- [ ] **Step 2: Week 2 학습 일지**

Create `/Users/chan-uhyeon/Programming/fpga/notes/week-02.md`:
```markdown
# Week 2 학습 일지

## 새로 알게 된 것

- **동기 reset** (클럭 에지에서만 reset 인식) vs **비동기 reset** (reset 변화 즉시 인식). 이번 주는 동기로 통일. 타이밍 분석이 단순해지고 FPGA 합성에도 호의적.
- FSM은 보통 **단일 clocked process** + `case state is ...`로 쓴다. 2-process 스타일(next-state 계산 vs register 분리)도 있으나 단순하면 1-process가 읽기 편함.
- Testbench에서 **generic으로 BIT_CLKS를 줄이면** 시뮬 속도를 수십 배 빠르게 할 수 있다. 실제 합성 시엔 기본값(100 MHz / 115.2 kHz)을 쓰면 됨.
- `wait until rising_edge(clk); wait for 1 ns;` 패턴: rising_edge 직후 delta cycle을 모두 처리하고 안정화된 출력값을 읽기 위함.

## 막힌 지점 / 디버깅

- (실제 작업 중 기록)

## 다음 주 예열

- 메모리·FIFO. dual-port RAM 추론 패턴과 synchronous FIFO의 full/empty 플래그 정의 미리 훑기.
```

- [ ] **Step 3: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 02_sequential_fsm/README.md notes/week-02.md
git commit -m "docs(02): add week 2 README and learning log"
```

---

## Task 6: Week 2 회고와 Week 3 진입 판단

- [ ] **Step 1: Clean build 확인**

```bash
cd /Users/chan-uhyeon/Programming/fpga
make clean && make test
```
Expected: 2주차 모든 testbench(5개)가 전부 PASS.
- Week 1: tb_alu, tb_mux4, tb_priority_encoder
- Week 2: tb_counter, tb_uart_tx

- [ ] **Step 2: UART 파형 스모크**

```bash
cd /Users/chan-uhyeon/Programming/fpga/02_sequential_fsm
rm -f tb_uart_tx.vcd
make analyze
ghdl -e --std=08 --workdir=work tb_uart_tx
ghdl -r --std=08 --workdir=work tb_uart_tx --vcd=tb_uart_tx.vcd --stop-time=500us
ls -la tb_uart_tx.vcd
rm tb_uart_tx.vcd
```
Expected: `tb_uart_tx.vcd` 생성 후 삭제.

- [ ] **Step 3: 자가 체크리스트 기록**

`/Users/chan-uhyeon/Programming/fpga/notes/week-02.md`의 `## 막힌 지점 / 디버깅` 섹션에 다음 4문항 답변 추가 (Q1~Q4 형식, Week 1 패턴과 동일):

1. 동기 reset과 비동기 reset의 차이를 한두 문장으로 설명할 수 있는가?
2. Moore FSM과 Mealy FSM의 차이를 설명할 수 있는가? (UART_TX는 어느 쪽?)
3. 왜 generic으로 CLK_FREQ_HZ·BAUD_RATE를 분리했는가? 상수로 하드코딩하면 어떤 점이 불편해지는가?
4. `wait until tx_line = '0';`과 `wait until rising_edge(clk);`의 차이는?

각 질문에 2~3문장으로 답변. 실제 작업 중 부딪친 이슈도 위 섹션에 함께 기록.

- [ ] **Step 4: 최종 commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add notes/week-02.md
git commit -m "docs(02): fill in week 2 retrospective" || true
```

---

## 완료 기준

- `make test` 루트 실행 시 Week 1+Week 2 총 5개 testbench PASS.
- `uart_tx`가 0x00~0xFF 256 바이트 전부 송신 검증.
- `counter`가 reset·en·포화·재-reset 시나리오 검증.
- `notes/week-02.md` 회고 완료.

## 범위 밖 (Week 3 이후)

- UART RX (Week 3)
- FIFO (Week 3)
- 비동기 reset, 메타스터빌러티 (별도 학습 필요)
- Mealy FSM 예시 (원하면 Week 2 말미 추가 실습)
