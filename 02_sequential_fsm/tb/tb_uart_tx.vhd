library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart_tx is
end entity;

architecture sim of tb_uart_tx is
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

    procedure rx_byte(signal serial : in std_logic;
                      variable data_out : out std_logic_vector(7 downto 0)) is
        variable tmp : std_logic_vector(7 downto 0) := (others => '0');
    begin
        wait for BIT_TIME / 2;
        assert serial = '0'
            report "rx_byte: expected start bit=0 at mid"
            severity error;

        for i in 0 to 7 loop
            wait for BIT_TIME;
            tmp(i) := serial;
        end loop;

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
        rst <= '1';
        wait for 3 * CLK_PER;
        rst <= '0';
        wait for 2 * CLK_PER;

        assert tx_line = '1' and tx_busy = '0'
            report "initial: line should be idle(1), not busy"
            severity error;

        tx_data <= x"55";
        tx_send <= '1';
        wait until rising_edge(clk);
        tx_send <= '0';

        wait for CLK_PER;
        assert tx_busy = '1'
            report "tx_busy should assert after tx_send"
            severity error;

        if tx_line /= '0' then
            wait until tx_line = '0';
        end if;
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
