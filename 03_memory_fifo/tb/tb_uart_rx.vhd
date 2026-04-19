--=============================================================================
-- tb_uart_rx.vhd — uart_rx.vhd 검증 (256바이트 왕복 테스트)
--=============================================================================
-- 전략:
--   TB 가 "UART TX" 역할을 대신 수행해 serial_in 라인을 비트 단위로 구동한다.
--   DUT(uart_rx) 가 각 프레임을 올바르게 수신해 rx_data/rx_valid 를 내놓는지 확인.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_uart_rx is
end entity;

architecture sim of tb_uart_rx is
    --------------------------------------------------------------------------
    -- TB 전용 파라미터
    --   시뮬 시간을 줄이려 현실값보다 작게 잡는다.
    --   clk=1 MHz, baud=100 kHz → BIT_CLKS = 10 (한 bit 당 10 clk).
    --------------------------------------------------------------------------
    constant CLK_FREQ_HZ : positive := 1_000_000;
    constant BAUD_RATE   : positive := 100_000;
    constant CLK_PER     : time     := 10 ns;
    constant BIT_CLKS    : positive := CLK_FREQ_HZ / BAUD_RATE;   -- 10
    -- BIT_TIME: 한 bit 동안 유지해야 하는 실제 시간 (물리 타입 곱셈).
    constant BIT_TIME    : time     := BIT_CLKS * CLK_PER;

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal serial_in : std_logic := '1';    -- UART idle = '1'
    signal rx_data   : std_logic_vector(7 downto 0);
    signal rx_valid  : std_logic;

    signal sim_done : boolean := false;

    --------------------------------------------------------------------------
    -- procedure tx_byte: 한 바이트를 UART 프레임으로 직렬 송출
    --
    --   "constant b : in std_logic_vector(7 downto 0)"
    --     → 호출 시점 값이 그대로 복사된 상수 파라미터.
    --       signal 인자와 달리 driver/resolve 를 걱정할 필요 없음.
    --
    --   LSB-first 전송: UART 표준은 비트 0을 먼저 전송한다.
    --------------------------------------------------------------------------
    procedure tx_byte(signal serial : out std_logic;
                      constant b : in std_logic_vector(7 downto 0)) is
    begin
        -- START bit: '0' 을 BIT_TIME 만큼 유지
        serial <= '0';
        wait for BIT_TIME;
        -- DATA 8비트: b(0), b(1), ..., b(7) 순서 (LSB-first)
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
    -- DUT 인스턴스화
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
    -- 클럭 생성
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
    -- 자극 프로세스 — 0x00..0xFF 256개 바이트 모두 전송 후 수신 확인
    --------------------------------------------------------------------------
    stimulus : process
    begin
        -- 초기 리셋: 3 clk 동안 rst 유지 → 해제 → 안정화 대기
        rst <= '1';
        wait for 3 * CLK_PER;
        rst <= '0';
        wait for 2 * CLK_PER;

        -- 전원 인가 직후 rx_valid 가 잘못 떠있지 않은지 확인
        assert rx_valid = '0'
            report "initial: rx_valid should be 0"
            severity error;

        -- 256 바이트 모두 round-trip 검증
        for v in 0 to 255 loop
            -- 한 바이트 프레임을 DUT 로 전송
            tx_byte(serial_in, std_logic_vector(to_unsigned(v, 8)));

            ------------------------------------------------------------------
            -- rx_valid 펄스 폴링:
            --   tx_byte 리턴 시점에 DUT 는 아직 STOP 윈도우를 카운트 중일 수 있다.
            --   최대 BIT_CLKS+1 클럭 동안 rx_valid='1' 를 기다리되, 발견 즉시 탈출.
            --   "exit" 는 가장 안쪽 loop 를 종료 (중첩 루프라도 가장 안쪽).
            --   라벨과 함께 쓰면 "exit <label>" 로 바깥 루프도 나갈 수 있다.
            ------------------------------------------------------------------
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

            -- 수신 데이터 값 일치 확인
            assert rx_data = std_logic_vector(to_unsigned(v, 8))
                report "rx_data mismatch for v=" & integer'image(v) &
                       ": got=" & integer'image(to_integer(unsigned(rx_data)))
                severity error;

            -- rx_valid 는 1-cycle pulse 여야 함 → 다음 클럭엔 반드시 '0'
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
