--=============================================================================
-- tb_uart_rx.vhd — uart_rx.vhd 검증 (256 바이트 왕복)
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. "TB 가 반대편 장치를 에뮬레이션" 하는 패턴 (여기선 UART TX 측 흉내)
--   2. constant 파라미터를 쓰는 procedure (signal 불필요)
--   3. 1-cycle pulse 신호(rx_valid) 를 폴링 + assert 로 검증
--   4. 안쪽 for 루프 탈출하는 exit 문
--
-- 【이 TB 의 전략】
--   TB 가 serial_in 라인에 직접 "start→D0..D7→stop" 파형을 만들어 보낸다
--   (tx_byte procedure). DUT(uart_rx) 가 이를 받아 rx_data/rx_valid 를
--   올바르게 내는지 확인. 0x00..0xFF 전 256 바이트.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_uart_rx is
end entity;

architecture sim of tb_uart_rx is
    --------------------------------------------------------------------------
    -- 시뮬 시간 단축을 위해 현실값보다 작게 설정.
    --   clk = 1 MHz, baud = 100 kHz → BIT_CLKS = 10 (한 bit 당 10 clk)
    --   BIT_TIME = 100 ns (10 clk × 10 ns)
    -- uart_rx 로직은 "BIT_CLKS 상대 시간" 으로 동작하므로 비율이 맞으면 무방.
    --------------------------------------------------------------------------
    constant CLK_FREQ_HZ : positive := 1_000_000;
    constant BAUD_RATE   : positive := 100_000;
    constant CLK_PER     : time     := 10 ns;
    constant BIT_CLKS    : positive := CLK_FREQ_HZ / BAUD_RATE;   -- 10
    constant BIT_TIME    : time     := BIT_CLKS * CLK_PER;        -- 100 ns

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal serial_in : std_logic := '1';    -- UART idle = '1'
    signal rx_data   : std_logic_vector(7 downto 0);
    signal rx_valid  : std_logic;

    signal sim_done : boolean := false;

    --------------------------------------------------------------------------
    -- 【tx_byte procedure: UART 프레임을 직접 만들어 전송】
    --
    -- 파라미터:
    --   signal serial : out std_logic
    --     → serial_in 을 직접 드라이브하기 위해 signal out 으로 선언.
    --       wait for 와 함께 쓰려면 signal 키워드 필수.
    --
    --   constant b : in std_logic_vector(7 downto 0)
    --     → 호출 시점 값이 복사되어 들어오는 상수. signal 아니라 wait 중에
    --       값이 바뀔 걱정이 없다. LSB-first 로 b(0) 부터 전송.
    --
    -- 프레임:
    --   idle(1) → start(0) [BIT_TIME] → D0..D7 각 [BIT_TIME] → stop(1) [BIT_TIME]
    --   → 다시 idle 로 돌아옴 (procedure 끝에서 serial <= '1' 상태 유지)
    --------------------------------------------------------------------------
    procedure tx_byte(signal serial : out std_logic;
                      constant b : in std_logic_vector(7 downto 0)) is
    begin
        -- START bit: '0' 을 BIT_TIME 만큼 유지
        serial <= '0';
        wait for BIT_TIME;

        -- DATA 8비트 (LSB-first → i=0 부터 내보냄)
        for i in 0 to 7 loop
            serial <= b(i);
            wait for BIT_TIME;
        end loop;

        -- STOP bit: '1' 한 bit
        serial <= '1';
        wait for BIT_TIME;
    end procedure;

begin
    --------------------------------------------------------------------------
    -- DUT 인스턴스화.
    --------------------------------------------------------------------------
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

    --------------------------------------------------------------------------
    -- 클럭 생성.
    --------------------------------------------------------------------------
    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PER/2;
            clk <= '1'; wait for CLK_PER/2;
        end loop;
        wait;
    end process;

    --------------------------------------------------------------------------
    -- 자극/검증 프로세스 — 0x00..0xFF 256바이트 왕복.
    --------------------------------------------------------------------------
    stimulus : process
    begin
        -- 리셋 → 안정화
        rst <= '1';
        wait for 3 * CLK_PER;
        rst <= '0';
        wait for 2 * CLK_PER;

        -- 초기 valid 는 반드시 '0' 이어야 한다 (아직 뭔가 받지 않았으므로).
        assert rx_valid = '0'
            report "initial: rx_valid should be 0"
            severity error;

        -- 256 바이트 전부 round-trip
        for v in 0 to 255 loop
            -- 1) 한 바이트 전송 (TB → DUT)
            tx_byte(serial_in, std_logic_vector(to_unsigned(v, 8)));

            ----------------------------------------------------------------
            -- 2) rx_valid pulse 폴링.
            --
            --   tx_byte 리턴 시점에 DUT 는 아직 STOP 윈도우를 카운트 중일 수
            --   있다 (stop bit 중앙 샘플 이후 HALF_BIT 여유가 남았기 때문).
            --   최대 BIT_CLKS+1 클럭 동안 rx_valid='1' 을 기다리되, 발견 즉시
            --   exit 로 탈출 → 불필요한 대기 제거.
            --
            -- 【exit 문】
            --   C 의 break 와 동일. 가장 안쪽 loop 를 즉시 탈출.
            --   라벨과 함께 쓰면 중첩 루프에서 바깥 루프도 탈출 가능.
            ----------------------------------------------------------------
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

            -- 3) 값이 정확한지 확인
            assert rx_data = std_logic_vector(to_unsigned(v, 8))
                report "rx_data mismatch for v=" & integer'image(v) &
                       ": got=" & integer'image(to_integer(unsigned(rx_data)))
                severity error;

            -- 4) rx_valid 는 "1-cycle pulse" 여야 한다 → 다음 클럭엔 반드시 '0'
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
