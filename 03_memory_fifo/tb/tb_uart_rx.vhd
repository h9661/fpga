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
    signal serial_in : std_logic := '1';
    signal rx_data   : std_logic_vector(7 downto 0);
    signal rx_valid  : std_logic;

    signal sim_done : boolean := false;

    procedure tx_byte(signal serial : out std_logic;
                      constant b : in std_logic_vector(7 downto 0)) is
    begin
        serial <= '0';
        wait for BIT_TIME;
        for i in 0 to 7 loop
            serial <= b(i);
            wait for BIT_TIME;
        end loop;
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

        for v in 0 to 255 loop
            tx_byte(serial_in, std_logic_vector(to_unsigned(v, 8)));

            -- rx_valid 1-cycle pulse 감지 (최대 BIT_CLKS+1 cycles 대기)
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
