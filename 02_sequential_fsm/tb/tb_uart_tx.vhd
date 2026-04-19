--=============================================================================
-- tb_uart_tx.vhd — uart_tx.vhd 검증 (256 바이트 round-trip)
--=============================================================================
-- 전략:
--   TB 가 "UART RX" 역할을 에뮬레이션 (rx_byte procedure) 하여 DUT 가 구동한
--   tx_line 을 비트 중앙에서 샘플해 수신값을 조립한다.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_uart_tx is
end entity;

architecture sim of tb_uart_tx is
    -- TB 시간 단축용 파라미터: clk=1MHz, baud=100kHz → BIT_CLKS=10
    constant CLK_FREQ_HZ : positive := 1_000_000;
    constant BAUD_RATE   : positive := 100_000;
    constant BIT_CLKS    : positive := CLK_FREQ_HZ / BAUD_RATE;
    constant CLK_PER     : time     := 10 ns;
    constant BIT_TIME    : time     := BIT_CLKS * CLK_PER;

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal tx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_send : std_logic := '0';
    signal tx_busy : std_logic;
    signal tx_line : std_logic;

    signal sim_done : boolean := false;

    --------------------------------------------------------------------------
    -- procedure rx_byte: UART 라인에서 한 바이트를 수신해 variable 로 돌려줌
    --
    -- 호출 규약 (caller 측):
    --   * 호출 시점에 serial 은 이미 start bit('0') 구간의 어딘가에 들어와 있어야 함.
    --     (일반적으로 "tx_line = '0' 감지 직후" 호출)
    --
    -- 처리 흐름:
    --   1) BIT_TIME/2 대기 → start bit 중앙에서 재확인.
    --   2) 8번 BIT_TIME 씩 진행하며 bit 중앙에서 D0..D7 을 tmp 에 누적.
    --   3) BIT_TIME 더 진행해 stop bit 중앙에서 '1' 확인.
    --
    -- parameter:
    --   signal   serial   : in  → 외부 signal 참조 (wait 가능)
    --   variable data_out : out → 결과 저장 (즉시 갱신)
    --------------------------------------------------------------------------
    procedure rx_byte(signal serial : in std_logic;
                      variable data_out : out std_logic_vector(7 downto 0)) is
        variable tmp : std_logic_vector(7 downto 0) := (others => '0');
    begin
        -- 1) start bit 중앙으로 이동
        wait for BIT_TIME / 2;
        assert serial = '0'
            report "rx_byte: expected start bit=0 at mid"
            severity error;

        -- 2) 각 데이터 비트 중앙에서 샘플 (LSB-first)
        for i in 0 to 7 loop
            wait for BIT_TIME;
            tmp(i) := serial;
        end loop;

        -- 3) stop bit 중앙
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
    begin
        ------------------------------------------------------------------
        -- 초기 리셋
        ------------------------------------------------------------------
        rst <= '1';
        wait for 3 * CLK_PER;
        rst <= '0';
        wait for 2 * CLK_PER;

        assert tx_line = '1' and tx_busy = '0'
            report "initial: line should be idle(1), not busy"
            severity error;

        ------------------------------------------------------------------
        -- 단일 바이트 테스트: 0x55 (비트 패턴 01010101 — 토글 많음, 시각적 확인 용이)
        ------------------------------------------------------------------
        tx_data <= x"55";
        tx_send <= '1';
        wait until rising_edge(clk);   -- tx_send 는 1-cycle pulse
        tx_send <= '0';

        -- 한 클럭 뒤 busy 올라왔는지 확인 (상태 전이 후)
        wait for CLK_PER;
        assert tx_busy = '1'
            report "tx_busy should assert after tx_send"
            severity error;

        -- IDLE 에서 pre-drive 로 이미 '0' 일 수 있으므로 guard 후 rx_byte 호출.
        -- "wait until <expr>" 은 expr 이 참으로 바뀔 때까지 대기.
        if tx_line /= '0' then
            wait until tx_line = '0';
        end if;
        rx_byte(tx_line, rx);
        assert rx = x"55"
            report "rx mismatch for 0x55: got=" & integer'image(to_integer(unsigned(rx)))
            severity error;

        -- rx_byte 는 stop bit 중앙에서 반환 → 남은 BIT_TIME/2 + 여유 대기 후 busy 내려감 확인
        wait for BIT_TIME / 2 + CLK_PER;
        assert tx_busy = '0'
            report "tx_busy should deassert after stop bit"
            severity error;
        assert tx_line = '1'
            report "tx_line should be idle after send"
            severity error;

        ------------------------------------------------------------------
        -- 다중 바이트 테스트: 0x00 ~ 0xFF 전부 round-trip
        ------------------------------------------------------------------
        for v in 0 to 255 loop
            -- 직전 송신이 아직 진행 중이면 완료까지 대기
            if tx_busy = '1' then
                wait until tx_busy = '0';
                wait for 2 * CLK_PER;
            end if;

            tx_data <= std_logic_vector(to_unsigned(v, 8));
            tx_send <= '1';
            wait until rising_edge(clk);
            tx_send <= '0';

            wait for CLK_PER;
            assert tx_busy = '1'
                report "multi v=" & integer'image(v) & ": tx_busy not asserted"
                severity error;

            -- IDLE → START 전이 시 tx_line 이 이미 '0' 로 pre-drive 되었을 수 있으므로
            -- '0' 아닐 때만 "wait until" (이미 '0' 이면 바로 진행).
            if tx_line /= '0' then
                wait until tx_line = '0';
            end if;
            rx_byte(tx_line, rx);
            assert rx = std_logic_vector(to_unsigned(v, 8))
                report "multi v=" & integer'image(v) &
                       ": rx mismatch, got=" & integer'image(to_integer(unsigned(rx)))
                severity error;
        end loop;

        -- 마지막 송신 정리
        if tx_busy = '1' then
            wait until tx_busy = '0';
        end if;

        report "tb_uart_tx: PASS (256 bytes)";
        sim_done <= true;
        wait;
    end process;
end architecture;
