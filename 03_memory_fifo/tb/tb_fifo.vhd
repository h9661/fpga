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

    -- FWFT: dout shows head, sample BEFORE advancing with rd_en pulse.
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
            write_value(clk, wr_en, din, i * 11);
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
