# Phase 1 Week 3 — 메모리, Sync FIFO, UART 수신기 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 메모리 추론 패턴(array-of-std_logic_vector)으로 파라미터화된 synchronous FIFO를 구현하고, Week 2 UART TX와 쌍이 되는 UART RX(midpoint 샘플링)를 추가. 전 three 모듈 self-checking testbench로 검증.

**Architecture:** `03_memory_fifo/` 폴더. FIFO는 내부에 `type ram_t is array ... of std_logic_vector(WIDTH-1 downto 0)` 배열을 signal로 선언하여 합성 툴이 BRAM/LUT-RAM으로 추론. UART RX는 Week 2 UART TX를 거꾸로 뒤집은 FSM. Testbench는 UART TX를 stimulus로, UART RX를 DUT로 인스턴스화해 loopback 검증.

**Tech Stack:** VHDL-2008, GHDL 6.0 LLVM, GNU Make.

---

## File Structure

```
03_memory_fifo/
├── Makefile                    # MODULES := fifo uart_rx
├── README.md
├── rtl/
│   ├── fifo.vhd                # sync FIFO with almost-full/empty flags
│   └── uart_rx.vhd             # UART RX FSM with midpoint sampling
└── tb/
    ├── tb_fifo.vhd
    └── tb_uart_rx.vhd

notes/week-03.md                # 학습 일지
```

---

## Task 0: Week 3 폴더 skeleton

- [ ] **Step 1: 폴더 생성 + Makefile**

```bash
mkdir -p /Users/chan-uhyeon/Programming/fpga/03_memory_fifo/rtl
mkdir -p /Users/chan-uhyeon/Programming/fpga/03_memory_fifo/tb
```

Create `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/Makefile`:
```make
MODULES := fifo uart_rx

include ../common/Makefile.common
```

- [ ] **Step 2: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 03_memory_fifo/Makefile
git commit -m "chore(03): add week 3 folder skeleton"
```

---

## Task 1: Sync FIFO 구현 + 기본 testbench

파라미터화된 synchronous FIFO. DEPTH와 WIDTH 모두 generic. `full`·`empty` 외에 `almost_full`·`almost_empty` 플래그도 제공.

**Files:**
- Create: `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/rtl/fifo.vhd`
- Create: `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/tb/tb_fifo.vhd`

- [ ] **Step 1: Testbench 먼저 (기본 시나리오)**

Create `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/tb/tb_fifo.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_fifo is
end entity;

architecture sim of tb_fifo is
    constant WIDTH   : positive := 8;
    constant DEPTH   : positive := 8;
    constant CLK_PER : time := 10 ns;

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal wr_en        : std_logic := '0';
    signal din          : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
    signal rd_en        : std_logic := '0';
    signal dout         : std_logic_vector(WIDTH-1 downto 0);
    signal full         : std_logic;
    signal empty        : std_logic;
    signal almost_full  : std_logic;
    signal almost_empty : std_logic;
    signal count        : std_logic_vector(31 downto 0);

    signal sim_done : boolean := false;

    procedure tick(n : in positive) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
    end procedure;

    procedure write_value(signal clk_s   : in    std_logic;
                          signal wr_en_s : out   std_logic;
                          signal din_s   : out   std_logic_vector(WIDTH-1 downto 0);
                          v : in natural) is
    begin
        din_s <= std_logic_vector(to_unsigned(v, WIDTH));
        wr_en_s <= '1';
        wait until rising_edge(clk_s);
        wait for 1 ns;
        wr_en_s <= '0';
    end procedure;

    -- FWFT (First-Word-Fall-Through) 스타일: dout는 항상 head를 조합적으로 보여준다.
    -- rd_en 펄스는 head를 "이미 읽었으니 진행하라"는 신호.
    -- 따라서 dout을 edge 이전에 샘플하고, 그 다음 rd_en으로 진행시킨다.
    procedure read_value(signal clk_s   : in    std_logic;
                         signal rd_en_s : out   std_logic;
                         signal dout_s  : in    std_logic_vector(WIDTH-1 downto 0);
                         expected : in natural) is
        variable got : natural;
    begin
        got := to_integer(unsigned(dout_s));
        assert got = expected
            report "read mismatch: got=" & integer'image(got) &
                   " expected=" & integer'image(expected)
            severity error;
        rd_en_s <= '1';
        wait until rising_edge(clk_s);
        wait for 1 ns;
        rd_en_s <= '0';
    end procedure;

begin
    dut : entity work.fifo
        generic map (
            WIDTH => WIDTH,
            DEPTH => DEPTH,
            ALMOST_FULL_THRESHOLD  => DEPTH-1,
            ALMOST_EMPTY_THRESHOLD => 1
        )
        port map (
            clk => clk, rst => rst,
            wr_en => wr_en, din => din,
            rd_en => rd_en, dout => dout,
            full => full, empty => empty,
            almost_full => almost_full,
            almost_empty => almost_empty,
            count => count
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
    begin
        -- reset
        rst <= '1';
        tick(3);
        assert empty = '1' and full = '0'
            report "after reset: empty=1, full=0 expected"
            severity error;
        assert to_integer(unsigned(count)) = 0
            report "after reset: count=0 expected"
            severity error;

        rst <= '0';
        tick(1);

        -- === 시나리오 1: DEPTH개 채우기 ===
        for i in 0 to DEPTH-1 loop
            assert full = '0'
                report "should not be full at i=" & integer'image(i)
                severity error;
            write_value(clk, wr_en, din, i * 11);  -- 0, 11, 22, ...
        end loop;

        tick(1);
        assert full = '1'
            report "should be full after DEPTH writes"
            severity error;
        assert empty = '0'
            report "should not be empty after writes"
            severity error;
        assert to_integer(unsigned(count)) = DEPTH
            report "count should be DEPTH=" & integer'image(DEPTH) &
                   " got=" & integer'image(to_integer(unsigned(count)))
            severity error;

        -- === 시나리오 2: DEPTH개 읽기 (FIFO 순서) ===
        for i in 0 to DEPTH-1 loop
            assert empty = '0'
                report "should not be empty at i=" & integer'image(i)
                severity error;
            read_value(clk, rd_en, dout, i * 11);
        end loop;

        tick(1);
        assert empty = '1'
            report "should be empty after DEPTH reads"
            severity error;
        assert full = '0'
            report "should not be full after reads"
            severity error;

        report "tb_fifo: PASS (basic)";
        sim_done <= true;
        wait;
    end process;
end architecture;
```

- [ ] **Step 2: Stub RTL**

Create `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/rtl/fifo.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo is
    generic (
        WIDTH                  : positive := 8;
        DEPTH                  : positive := 16;
        ALMOST_FULL_THRESHOLD  : positive := 15;
        ALMOST_EMPTY_THRESHOLD : positive := 1
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        wr_en        : in  std_logic;
        din          : in  std_logic_vector(WIDTH-1 downto 0);
        rd_en        : in  std_logic;
        dout         : out std_logic_vector(WIDTH-1 downto 0);
        full         : out std_logic;
        empty        : out std_logic;
        almost_full  : out std_logic;
        almost_empty : out std_logic;
        count        : out std_logic_vector(31 downto 0)
    );
end entity;

architecture rtl of fifo is
begin
    dout         <= (others => '0');
    full         <= '0';
    empty        <= '1';
    almost_full  <= '0';
    almost_empty <= '1';
    count        <= (others => '0');
end architecture;
```

- [ ] **Step 3: Run, verify FAIL**

```bash
cd /Users/chan-uhyeon/Programming/fpga/03_memory_fifo
make MODULES=fifo test
```
Expected: FAIL — `should be full after DEPTH writes` or similar. Stub always says `empty=1, full=0`.

- [ ] **Step 4: 구현**

Overwrite `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/rtl/fifo.vhd` entirely with:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo is
    generic (
        WIDTH                  : positive := 8;
        DEPTH                  : positive := 16;
        ALMOST_FULL_THRESHOLD  : positive := 15;
        ALMOST_EMPTY_THRESHOLD : positive := 1
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        wr_en        : in  std_logic;
        din          : in  std_logic_vector(WIDTH-1 downto 0);
        rd_en        : in  std_logic;
        dout         : out std_logic_vector(WIDTH-1 downto 0);
        full         : out std_logic;
        empty        : out std_logic;
        almost_full  : out std_logic;
        almost_empty : out std_logic;
        count        : out std_logic_vector(31 downto 0)
    );
end entity;

architecture rtl of fifo is
    type ram_t is array (0 to DEPTH-1) of std_logic_vector(WIDTH-1 downto 0);
    signal ram : ram_t := (others => (others => '0'));

    signal wr_ptr : integer range 0 to DEPTH-1 := 0;
    signal rd_ptr : integer range 0 to DEPTH-1 := 0;
    signal cnt    : integer range 0 to DEPTH   := 0;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                wr_ptr <= 0;
                rd_ptr <= 0;
                cnt    <= 0;
            else
                -- write (block if full)
                if wr_en = '1' and cnt /= DEPTH then
                    ram(wr_ptr) <= din;
                    if wr_ptr = DEPTH-1 then
                        wr_ptr <= 0;
                    else
                        wr_ptr <= wr_ptr + 1;
                    end if;
                end if;

                -- read (block if empty)
                if rd_en = '1' and cnt /= 0 then
                    if rd_ptr = DEPTH-1 then
                        rd_ptr <= 0;
                    else
                        rd_ptr <= rd_ptr + 1;
                    end if;
                end if;

                -- count: concurrent wr+rd → no change; one-sided → ±1
                if    wr_en = '1' and cnt /= DEPTH and rd_en = '1' and cnt /= 0 then
                    cnt <= cnt;
                elsif wr_en = '1' and cnt /= DEPTH then
                    cnt <= cnt + 1;
                elsif rd_en = '1' and cnt /= 0 then
                    cnt <= cnt - 1;
                end if;
            end if;
        end if;
    end process;

    -- combinational read: 읽기 포인터 지시 셀을 즉시 출력
    dout <= ram(rd_ptr);

    full         <= '1' when cnt = DEPTH else '0';
    empty        <= '1' when cnt = 0 else '0';
    almost_full  <= '1' when cnt >= ALMOST_FULL_THRESHOLD  else '0';
    almost_empty <= '1' when cnt <= ALMOST_EMPTY_THRESHOLD else '0';
    count        <= std_logic_vector(to_unsigned(cnt, 32));
end architecture;
```

- [ ] **Step 5: Run, verify PASS**

```bash
cd /Users/chan-uhyeon/Programming/fpga/03_memory_fifo
make MODULES=fifo test
```
Expected: `tb_fifo: PASS (basic)`.

- [ ] **Step 6: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 03_memory_fifo/rtl/fifo.vhd 03_memory_fifo/tb/tb_fifo.vhd
git commit -m "feat(03): add parameterized sync FIFO with basic testbench"
```

---

## Task 2: FIFO 경계 테스트 확장 — overflow, underflow, almost-full/empty, 동시 wr/rd

기본 tb에 경계 케이스 추가.

**Files:**
- Modify: `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/tb/tb_fifo.vhd`

- [ ] **Step 1: 확장 블록 추가**

기존 `stimulus : process` 내부에서 `report "tb_fifo: PASS (basic)";` 라인을 삭제하고, 그 위치에 다음 시나리오들을 **추가**한 뒤 마지막에 `"tb_fifo: PASS (all)"` 리포트로 교체한다.

추가 시나리오:
```vhdl
        -- === 시나리오 3: Overflow 시도 — 가득 찬 상태에서 wr_en 시 무시되고 count 불변 ===
        for i in 0 to DEPTH-1 loop
            write_value(clk, wr_en, din, i + 100);
        end loop;
        tick(1);
        assert full = '1' report "pre-overflow: full=1 expected" severity error;

        -- 가득 찬 상태에서 추가 write 시도 → 무시되어야
        for i in 0 to 4 loop
            din <= std_logic_vector(to_unsigned(255, WIDTH));
            wr_en <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            assert to_integer(unsigned(count)) = DEPTH
                report "overflow: count should stay at DEPTH"
                severity error;
        end loop;
        wr_en <= '0';

        -- 비우기
        for i in 0 to DEPTH-1 loop
            read_value(clk, rd_en, dout, i + 100);
        end loop;
        tick(1);
        assert empty = '1' report "after full-drain: empty=1 expected" severity error;

        -- === 시나리오 4: Underflow 시도 — 비어 있는 상태에서 rd_en 시 무시되고 count 불변 ===
        for i in 0 to 4 loop
            rd_en <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            assert to_integer(unsigned(count)) = 0
                report "underflow: count should stay at 0"
                severity error;
        end loop;
        rd_en <= '0';

        -- === 시나리오 5: Almost-full / almost-empty 플래그 ===
        -- DEPTH-1개 채우기 → almost_full='1' (threshold = DEPTH-1)
        for i in 0 to DEPTH-2 loop
            write_value(clk, wr_en, din, i);
        end loop;
        tick(1);
        assert almost_full = '1'
            report "almost_full should assert at count=DEPTH-1"
            severity error;
        assert full = '0'
            report "not quite full yet"
            severity error;

        -- 하나 더 채워 full
        write_value(clk, wr_en, din, 99);
        tick(1);
        assert full = '1' report "full after one more" severity error;

        -- 모두 비우기
        for i in 0 to DEPTH-1 loop
            rd_en <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        rd_en <= '0';
        tick(1);
        assert empty = '1' report "fully drained" severity error;
        assert almost_empty = '1' report "almost_empty at count=0" severity error;

        -- 하나만 채워 almost_empty 지속 (threshold=1)
        write_value(clk, wr_en, din, 42);
        tick(1);
        assert almost_empty = '1'
            report "almost_empty should assert at count=1"
            severity error;
        assert empty = '0'
            report "not empty anymore"
            severity error;

        -- 하나 더 채우면 count=2 → almost_empty='0'
        write_value(clk, wr_en, din, 43);
        tick(1);
        assert almost_empty = '0'
            report "almost_empty should deassert at count=2"
            severity error;

        -- 정리
        for i in 1 to 2 loop
            rd_en <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        rd_en <= '0';
        tick(1);

        -- === 시나리오 6: 동시 wr/rd — count 불변 ===
        -- 먼저 절반 채우기
        for i in 0 to DEPTH/2 - 1 loop
            write_value(clk, wr_en, din, i + 50);
        end loop;
        tick(1);
        assert to_integer(unsigned(count)) = DEPTH/2
            report "pre-concurrent: count should be DEPTH/2"
            severity error;

        -- 5회 연속으로 wr_en과 rd_en 동시에
        for i in 0 to 4 loop
            din <= std_logic_vector(to_unsigned(i + 200, WIDTH));
            wr_en <= '1';
            rd_en <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            assert to_integer(unsigned(count)) = DEPTH/2
                report "concurrent wr+rd: count should remain DEPTH/2, got=" &
                       integer'image(to_integer(unsigned(count)))
                severity error;
        end loop;
        wr_en <= '0';
        rd_en <= '0';

        report "tb_fifo: PASS (all)";
```

- [ ] **Step 2: Run, verify PASS**

```bash
cd /Users/chan-uhyeon/Programming/fpga/03_memory_fifo
make MODULES=fifo test
```
Expected: `tb_fifo: PASS (all)`.

- [ ] **Step 3: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 03_memory_fifo/tb/tb_fifo.vhd
git commit -m "test(03): extend FIFO testbench with overflow, underflow, almost flags, concurrent wr/rd"
```

---

## Task 3: UART 수신기

UART TX를 거꾸로 한 FSM. start bit 감지 → BIT_CLKS/2만큼 기다려 start bit 중앙에서 확인 → BIT_CLKS마다 데이터 bit 샘플 → stop bit 확인 → `rx_valid` 1-cycle pulse로 완료 알림.

**Files:**
- Create: `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/rtl/uart_rx.vhd`
- Create: `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/tb/tb_uart_rx.vhd`

- [ ] **Step 1: Testbench 먼저** (Week 2의 uart_tx를 stimulus로 재사용)

Create `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/tb/tb_uart_rx.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart_rx is
end entity;

architecture sim of tb_uart_rx is
    constant CLK_FREQ_HZ : positive := 1_000_000;
    constant BAUD_RATE   : positive := 100_000;
    constant CLK_PER     : time     := 10 ns;
    constant BIT_CLKS    : positive := CLK_FREQ_HZ / BAUD_RATE;
    constant BIT_TIME    : time     := BIT_CLKS * CLK_PER;

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal serial_in : std_logic := '1';  -- idle high
    signal rx_data   : std_logic_vector(7 downto 0);
    signal rx_valid  : std_logic;

    signal sim_done : boolean := false;

    -- testbench가 직접 LSB-first로 비트 전송하는 helper
    procedure tx_byte(signal serial : out std_logic;
                      constant b : in std_logic_vector(7 downto 0)) is
    begin
        -- start bit
        serial <= '0';
        wait for BIT_TIME;
        -- data bits LSB first
        for i in 0 to 7 loop
            serial <= b(i);
            wait for BIT_TIME;
        end loop;
        -- stop bit
        serial <= '1';
        wait for BIT_TIME;
    end procedure;

begin
    dut : entity work.uart_rx
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            BAUD_RATE   => BAUD_RATE
        )
        port map (
            clk => clk, rst => rst,
            serial_in => serial_in,
            rx_data => rx_data,
            rx_valid => rx_valid
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
    begin
        rst <= '1';
        wait for 3 * CLK_PER;
        rst <= '0';
        wait for 2 * CLK_PER;

        assert rx_valid = '0'
            report "initial: rx_valid should be 0"
            severity error;

        -- 전 256 바이트 송신 + 수신 비교
        for v in 0 to 255 loop
            tx_byte(serial_in, std_logic_vector(to_unsigned(v, 8)));

            -- stop bit 끝난 직후부터 rx_valid='1' pulse 기다림 (최대 몇 cycles 안에)
            -- rx_valid는 1-cycle pulse이므로 if ... elsif로 확인
            for k in 0 to BIT_CLKS loop
                if rx_valid = '1' then
                    exit;
                end if;
                wait until rising_edge(clk);
                wait for 1 ns;
            end loop;

            assert rx_valid = '1'
                report "rx_valid not asserted for v=" & integer'image(v)
                severity error;

            assert rx_data = std_logic_vector(to_unsigned(v, 8))
                report "rx_data mismatch for v=" & integer'image(v) &
                       ": got=" & integer'image(to_integer(unsigned(rx_data)))
                severity error;

            -- rx_valid가 다음 cycle에 deassert 되어야 (1-cycle pulse)
            wait until rising_edge(clk);
            wait for 1 ns;
            assert rx_valid = '0'
                report "rx_valid should be 1-cycle pulse, stayed high for v=" &
                       integer'image(v)
                severity error;
        end loop;

        report "tb_uart_rx: PASS (256 bytes)";
        sim_done <= true;
        wait;
    end process;
end architecture;
```

- [ ] **Step 2: Stub uart_rx**

Create `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/rtl/uart_rx.vhd`:
```vhdl
library ieee;
use ieee.std_logic_1164.all;

entity uart_rx is
    generic (
        CLK_FREQ_HZ : positive := 100_000_000;
        BAUD_RATE   : positive := 115_200
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        serial_in : in  std_logic;
        rx_data   : out std_logic_vector(7 downto 0);
        rx_valid  : out std_logic
    );
end entity;

architecture rtl of uart_rx is
begin
    rx_data  <= (others => '0');
    rx_valid <= '0';
end architecture;
```

- [ ] **Step 3: Run, verify FAIL (uart_rx only)**

```bash
cd /Users/chan-uhyeon/Programming/fpga/03_memory_fifo
make MODULES=uart_rx test
```
Expected: `rx_valid not asserted for v=0` FAIL.

- [ ] **Step 4: 구현**

Overwrite `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/rtl/uart_rx.vhd` entirely with:
```vhdl
library ieee;
use ieee.std_logic_1164.all;

entity uart_rx is
    generic (
        CLK_FREQ_HZ : positive := 100_000_000;
        BAUD_RATE   : positive := 115_200
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        serial_in : in  std_logic;
        rx_data   : out std_logic_vector(7 downto 0);
        rx_valid  : out std_logic
    );
end entity;

architecture rtl of uart_rx is
    constant BIT_CLKS : positive := CLK_FREQ_HZ / BAUD_RATE;
    constant HALF_BIT : positive := BIT_CLKS / 2;

    type state_t is (IDLE, START, DATA, STOP);
    signal state    : state_t := IDLE;

    signal cnt      : integer range 0 to BIT_CLKS-1 := 0;
    signal bit_idx  : integer range 0 to 7 := 0;
    signal buf      : std_logic_vector(7 downto 0) := (others => '0');
    signal data_r   : std_logic_vector(7 downto 0) := (others => '0');
    signal valid_r  : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            valid_r <= '0';  -- default; 1-cycle pulse만 낸다
            if rst = '1' then
                state   <= IDLE;
                cnt     <= 0;
                bit_idx <= 0;
                buf     <= (others => '0');
                data_r  <= (others => '0');
            else
                case state is
                    when IDLE =>
                        cnt     <= 0;
                        bit_idx <= 0;
                        if serial_in = '0' then
                            state <= START;
                        end if;

                    when START =>
                        -- start bit 중앙 (HALF_BIT 대기)에서 재확인
                        if cnt = HALF_BIT-1 then
                            cnt <= 0;
                            if serial_in = '0' then
                                state <= DATA;
                            else
                                state <= IDLE;  -- glitch 취급
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    when DATA =>
                        -- BIT_CLKS 주기마다 샘플
                        if cnt = BIT_CLKS-1 then
                            cnt <= 0;
                            buf(bit_idx) <= serial_in;
                            if bit_idx = 7 then
                                bit_idx <= 0;
                                state   <= STOP;
                            else
                                bit_idx <= bit_idx + 1;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    when STOP =>
                        if cnt = BIT_CLKS-1 then
                            cnt     <= 0;
                            if serial_in = '1' then
                                data_r  <= buf;
                                valid_r <= '1';
                            end if;
                            state <= IDLE;
                        else
                            cnt <= cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    rx_data  <= data_r;
    rx_valid <= valid_r;
end architecture;
```

- [ ] **Step 5: Run, verify PASS**

```bash
cd /Users/chan-uhyeon/Programming/fpga/03_memory_fifo
make MODULES=uart_rx test
```
Expected: `tb_uart_rx: PASS (256 bytes)`.

- [ ] **Step 6: 루트에서 전체 실행**

```bash
cd /Users/chan-uhyeon/Programming/fpga
make test
```
Expected: Week 1+2+3 모든 testbench(7개) 통과.

- [ ] **Step 7: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 03_memory_fifo/rtl/uart_rx.vhd 03_memory_fifo/tb/tb_uart_rx.vhd
git commit -m "feat(03): add uart_rx with midpoint sampling and 256-byte tb"
```

---

## Task 4: Week 3 README와 학습 일지

- [ ] **Step 1: Week 3 README**

Create `/Users/chan-uhyeon/Programming/fpga/03_memory_fifo/README.md`:
```markdown
# Week 3 — 메모리, Sync FIFO, UART 수신기

## 모듈

| 모듈 | 파일 | 설명 |
|---|---|---|
| `fifo` | `rtl/fifo.vhd` | WIDTH·DEPTH·almost 플래그 threshold 전부 generic. 메모리 추론 (array of std_logic_vector) 패턴 |
| `uart_rx` | `rtl/uart_rx.vhd` | 8-N-1 UART 수신기 (midpoint 샘플링). rx_valid 1-cycle pulse로 수신 완료 알림 |

## 검증

- `tb_fifo`: fill·drain·overflow·underflow·almost-full/empty·동시 wr/rd 6 시나리오
- `tb_uart_rx`: 내장 `tx_byte` procedure로 0x00~0xFF 256 바이트 송신 → DUT 수신 값 및 rx_valid 타이밍 검증

실행:
```
make test
```

## 배운 것

- VHDL에서 `type ram_t is array ... of std_logic_vector(...)` + `signal ram : ram_t` 패턴이 합성 툴에 **BRAM/LUT-RAM 추론** 신호가 된다
- Sync FIFO의 full/empty 정의: pointer (wr_ptr, rd_ptr) + count. count가 단순하고 오류 적음
- UART 수신기의 midpoint 샘플링: start bit 감지 후 HALF_BIT 대기 → 이후 BIT_CLKS마다 샘플
- 1-cycle pulse 출력 패턴: `valid_r <= '0';`을 process 최상단에 두고 특정 조건에서만 `'1'` 덮어쓰기
```

- [ ] **Step 2: Week 3 학습 일지**

Create `/Users/chan-uhyeon/Programming/fpga/notes/week-03.md`:
```markdown
# Week 3 학습 일지

## 새로 알게 된 것

- **메모리 추론**: VHDL에서 명시적 `BRAM` 프리미티브를 쓰지 않고 `type ram_t is array (0 to DEPTH-1) of std_logic_vector(WIDTH-1 downto 0)` 배열을 signal로 선언하면, Xilinx/Intel 툴이 BRAM 또는 LUT-RAM으로 추론한다. 읽기·쓰기 포트가 둘 이상이면 dual-port BRAM으로 추론될 수 있다.
- **Generic 간 의존**: FIFO의 `ALMOST_FULL_THRESHOLD : positive := DEPTH-1`처럼 한 generic의 기본값이 다른 generic을 참조할 수 있다. 사용자가 DEPTH를 바꾸면 threshold 기본값도 자동 추적됨.
- **1-cycle pulse 패턴**: 출력 신호를 매 cycle `<= '0'`으로 default 덮어쓰기하고, 특정 조건에서만 `<= '1'`. 이러면 latch 추론 없이 단일 cycle pulse가 자연스럽게 나옴.
- **UART RX midpoint sampling**: start bit 중심 샘플링 후 그 시점부터 BIT_CLKS 주기로 8개 data bit를 중앙에서 샘플. TX와 달리 `HALF_BIT = BIT_CLKS/2`를 명시적으로 사용.

## 막힌 지점 / 디버깅

- (실제 작업 중 기록)

## Phase 1 마감 점검

- Week 1~3 전체 testbench가 루트 `make test` 한 번으로 모두 PASS
- 자가 체크리스트: FSM·FIFO·UART 개념을 각각 3문장 이내로 설명 가능한지
- Phase 2 (DSP 코어) 진입 준비 — Python scipy 설치, `common/fixed_point_pkg`용 디렉토리 확인
```

- [ ] **Step 3: Commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add 03_memory_fifo/README.md notes/week-03.md
git commit -m "docs(03): add week 3 README and learning log"
```

---

## Task 5: Phase 1 최종 회고

- [ ] **Step 1: Clean 빌드 전체 검증**

```bash
cd /Users/chan-uhyeon/Programming/fpga
make clean && make test
```
Expected: Week 1~3 합 **7개 testbench** 전부 PASS.
- Week 1: tb_alu, tb_mux4, tb_priority_encoder
- Week 2: tb_counter, tb_uart_tx
- Week 3: tb_fifo, tb_uart_rx

- [ ] **Step 2: Phase 1 일지에 자가 체크 추가**

`/Users/chan-uhyeon/Programming/fpga/notes/week-03.md`의 `## 막힌 지점 / 디버깅` 섹션에 다음 4개 질문의 답변 추가 (Q1~Q4 형식):

1. FIFO의 `count` 신호를 두는 이유? pointer 두 개(wr_ptr, rd_ptr)만으로 full/empty를 구분할 수 없는 이유?
2. `type ram_t is array ... of std_logic_vector`와 `signal ram : ram_t`가 합성될 때 BRAM으로 추론되는 조건은?
3. UART RX의 `HALF_BIT` 계산이 BIT_CLKS의 정수 나눗셈인데, BIT_CLKS가 홀수면 어떤 문제가 생기는가? (예: BIT_CLKS=11)
4. Phase 1에서 배운 세 가지 검증 패턴(exhaustive input, TDD stub-fail-pass, loopback 시뮬)을 한 문장씩 요약.

- [ ] **Step 3: Phase 2 진입 가능 여부 판단**

4개 질문 중 3개 이상 자신 있으면 Phase 2 (4~6주차: 고정소수점·FIR·IIR/CIC) plan 작성을 요청한다. 2개 이하면 약한 주제를 지정해 보강 요청한다.

- [ ] **Step 4: 최종 commit**

```bash
cd /Users/chan-uhyeon/Programming/fpga
git add notes/week-03.md
git commit -m "docs(03): fill in week 3 retrospective and phase 1 closeout" || true
```

---

## 완료 기준

- 루트 `make test` 한 번에 Week 1+2+3 합 7개 testbench PASS.
- `fifo`가 fill/drain/overflow/underflow/almost/concurrent 6 시나리오 검증.
- `uart_rx`가 256 바이트 exhaustive 검증.
- `notes/week-03.md` 회고 완료.

## 범위 밖 (Phase 2 이후)

- 고정소수점 패키지 `fixed_point_pkg` (Week 4)
- FIR 필터 (Week 5)
- IIR / CIC (Week 6)
- UART TX + RX + FIFO 통합 loopback (원하면 Week 3 말미 추가 실습, but YAGNI)
