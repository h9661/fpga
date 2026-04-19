--=============================================================================
-- tb_uart_tx.vhd — uart_tx.vhd 검증 (256 바이트 round-trip)
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. wait 가 있는 procedure 로 "시간 흐름" 을 감싼 헬퍼 만들기
--   2. TB 가 "반대편 장치" 를 에뮬레이션하는 패턴 (UART RX 측 흉내)
--   3. procedure 의 signal vs variable 파라미터 선언
--   4. 상태 폴링 ("wait until <cond>", "if ... wait until ...")
--
-- 【이 TB 의 전략】
--   DUT(uart_tx) 가 시리얼 라인을 구동하면, TB 가 UART 수신기 역할을 해서
--   비트 중앙 샘플링으로 바이트를 복원한다. 원래 보낸 바이트와 복원값이
--   같아야 PASS. 0x00~0xFF 256 개 모두 테스트.
--
-- 【TB 시간 축의 직관】
--   CLK_PER = 10 ns → clk 주파수 1 MHz 에 해당 (1e8 ns / 10 ns per cycle).
--   BAUD_RATE = 100 kHz → 한 비트 = 10 clk = 100 ns = BIT_TIME.
--   시뮬 시간 단축을 위해 현실값보다 작게 잡았다. 로직은 비율로 동작하므로 무방.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_uart_tx is
end entity;

architecture sim of tb_uart_tx is
    -- TB 전용 파라미터.
    constant CLK_FREQ_HZ : positive := 1_000_000;
    constant BAUD_RATE   : positive := 100_000;
    constant BIT_CLKS    : positive := CLK_FREQ_HZ / BAUD_RATE;  -- 10
    constant CLK_PER     : time     := 10 ns;
    constant BIT_TIME    : time     := BIT_CLKS * CLK_PER;       -- time × integer 허용

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal tx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_send : std_logic := '0';
    signal tx_busy : std_logic;
    signal tx_line : std_logic;

    signal sim_done : boolean := false;

    --------------------------------------------------------------------------
    -- 【rx_byte procedure: UART 수신기 흉내】
    --
    -- 호출 규약:
    --   * 호출 직전 serial 이 이미 start bit('0') 구간의 어딘가에 진입해 있어야 한다.
    --     (일반적으로 "tx_line='0' 감지 직후" 에 호출)
    --
    -- 내부 타이밍:
    --   1) BIT_TIME/2 대기 → start bit 의 "중앙" 에 도달. 거기서 '0' 인지 재확인.
    --   2) 각 BIT_TIME 마다 비트 중앙에서 샘플 → 8개 데이터 비트 수집 (LSB-first).
    --   3) 한 번 더 BIT_TIME 진행해 stop bit 중앙에서 '1' 인지 확인.
    --
    --   반환 시점은 "stop bit 중앙" — 호출자는 필요하면 BIT_TIME/2 더 기다려
    --   stop bit 이 완전히 끝난 뒤에 다음 동작을 진행해야 한다.
    --
    -- 【procedure 파라미터의 class】
    --   기본 class 는 "in constant" (변경 불가). signal/variable/constant 로
    --   명시 가능. 여기서:
    --     signal serial    : in std_logic   → 외부 signal 참조, wait 가능
    --     variable data_out: out slv        → caller 쪽 variable 을 직접 갱신
    --
    --   signal 안 쓰고 그냥 "in std_logic" 이라 했으면 호출 시점 값이 "복사" 되어
    --   들어와 wait 중에 값이 바뀌어도 보이지 않는다.
    --------------------------------------------------------------------------
    procedure rx_byte(signal serial : in std_logic;
                      variable data_out : out std_logic_vector(7 downto 0)) is
        variable tmp : std_logic_vector(7 downto 0) := (others => '0');
    begin
        -- 1) start bit 중앙으로 점프
        wait for BIT_TIME / 2;
        assert serial = '0'
            report "rx_byte: expected start bit=0 at mid"
            severity error;

        -- 2) 8 비트 수집 (LSB-first: i=0 먼저 읽어야 함)
        for i in 0 to 7 loop
            wait for BIT_TIME;        -- 다음 비트 중앙으로 이동
            tmp(i) := serial;
        end loop;

        -- 3) stop bit 중앙 확인
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

        -- 초기 상태 점검: 라인 idle, busy 내려가 있음.
        assert tx_line = '1' and tx_busy = '0'
            report "initial: line should be idle(1), not busy"
            severity error;

        ------------------------------------------------------------------
        -- 단일 바이트 테스트: 0x55 = 01010101 (토글 많은 패턴, 눈으로 보기 좋음)
        ------------------------------------------------------------------
        tx_data <= x"55";
        tx_send <= '1';
        wait until rising_edge(clk);   -- tx_send 는 1-cycle pulse
        tx_send <= '0';

        -- 한 클럭 지난 뒤 busy 가 올라와 있어야 함.
        wait for CLK_PER;
        assert tx_busy = '1'
            report "tx_busy should assert after tx_send"
            severity error;

        -- 【wait until <조건>】
        --   조건이 참이 될 때까지 프로세스를 잠재운다. 이벤트 기반.
        --   여기선 "tx_line 이 '0' 이 되는 순간" 까지 기다림 = start bit 시작.
        --   단, IDLE 에서 pre-drive 로 이미 '0' 일 수도 있으므로 guard 로 감싼다.
        if tx_line /= '0' then
            wait until tx_line = '0';
        end if;

        rx_byte(tx_line, rx);          -- 한 바이트 수신 복원
        assert rx = x"55"
            report "rx mismatch for 0x55: got=" & integer'image(to_integer(unsigned(rx)))
            severity error;

        -- rx_byte 는 stop bit 중앙에서 반환했으므로, stop bit 끝까지는
        -- 남은 BIT_TIME/2 만큼 + 여유 1 CLK_PER 정도 더 대기.
        wait for BIT_TIME / 2 + CLK_PER;
        assert tx_busy = '0'
            report "tx_busy should deassert after stop bit"
            severity error;
        assert tx_line = '1'
            report "tx_line should be idle after send"
            severity error;

        ------------------------------------------------------------------
        -- 다중 바이트 테스트: 0x00..0xFF 전부 round-trip.
        ------------------------------------------------------------------
        for v in 0 to 255 loop
            -- 직전 송신이 아직 진행 중이면 완료까지 대기.
            if tx_busy = '1' then
                wait until tx_busy = '0';
                wait for 2 * CLK_PER;   -- 여유 안정화
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

            -- start bit 감지 (pre-drive 때문에 이미 '0' 일 수 있어 guard)
            if tx_line /= '0' then
                wait until tx_line = '0';
            end if;
            rx_byte(tx_line, rx);
            assert rx = std_logic_vector(to_unsigned(v, 8))
                report "multi v=" & integer'image(v) &
                       ": rx mismatch, got=" & integer'image(to_integer(unsigned(rx)))
                severity error;
        end loop;

        -- 마지막 송신 완료까지 마무리.
        if tx_busy = '1' then
            wait until tx_busy = '0';
        end if;

        report "tb_uart_tx: PASS (256 bytes)";
        sim_done <= true;
        wait;
    end process;
end architecture;
