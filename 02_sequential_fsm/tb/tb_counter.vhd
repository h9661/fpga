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
        rst <= '1'; en <= '0';
        wait for 3 * CLK_PER;
        assert q = (q'range => '0')
            report "after reset q should be 0"
            severity error;
        assert saturated = '0'
            report "after reset saturated should be 0"
            severity error;

        rst <= '0';
        wait for 3 * CLK_PER;
        assert q = (q'range => '0')
            report "en=0: q should not advance"
            severity error;

        en <= '1';
        for i in 1 to 15 loop
            wait until rising_edge(clk);
            wait for 1 ns;
            assert unsigned(q) = to_unsigned(i, WIDTH)
                report "count fail at step " & integer'image(i) &
                       ": got=" & integer'image(to_integer(unsigned(q)))
                severity error;
        end loop;

        assert saturated = '1'
            report "saturated should assert when q=max"
            severity error;

        for i in 1 to 5 loop
            wait until rising_edge(clk);
            wait for 1 ns;
            assert unsigned(q) = to_unsigned(15, WIDTH)
                report "saturation fail: q should stay at 15"
                severity error;
        end loop;

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
