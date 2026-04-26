--=============================================================================
-- tb_iir_biquad.vhd — IIR biquad 비트 정합 testbench
--=============================================================================
-- 헤더 1줄 (b0 b1 b2 a1 a2) → 패키지 상수와 일치 검증
-- 헤더 2줄 N_SAMPLES
-- 이후 N개 줄 (x_q15, y_q15)
-- 매 sample 1-cycle latency 후 y_out 정수 비교
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
use std.textio.all;

library work;
    use work.fixed_point_pkg.all;
    use work.iir_coeffs_pkg.all;

entity tb_iir_biquad is
end entity;

architecture sim of tb_iir_biquad is
    constant CLK_PER : time := 10 ns;

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal x_valid : std_logic := '0';
    signal x_in    : q15_t := (others => '0');
    signal y_valid : std_logic;
    signal y_out   : q15_t;

    signal sim_done : boolean := false;
begin
    dut : entity work.iir_biquad
        port map (
            clk     => clk,
            rst     => rst,
            x_valid => x_valid,
            x_in    => x_in,
            y_valid => y_valid,
            y_out   => y_out
        );

    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PER/2;
            clk <= '1'; wait for CLK_PER/2;
        end loop;
        wait;
    end process;

    stim : process
        file vec_file : text open read_mode is "data/iir_vectors.txt";
        variable L : line;
        variable b0_f, b1_f, b2_f, a1_f, a2_f : integer;
        variable n_samples : integer;
        variable x_int, y_exp : integer;
        variable got : integer;

        type int_arr_t is array (natural range <>) of integer;
        variable x_arr : int_arr_t(0 to 1023);
        variable y_arr : int_arr_t(0 to 1023);
    begin
        -- ─── 계수 parity ────────────────────────────────────────────────
        readline(vec_file, L);
        read(L, b0_f); read(L, b1_f); read(L, b2_f);
        read(L, a1_f); read(L, a2_f);
        assert b0_f = to_integer(BIQUAD_LP_B0)
            report "tb_iir_biquad: b0 drift: file=" & integer'image(b0_f) &
                   " pkg=" & integer'image(to_integer(BIQUAD_LP_B0))
            severity failure;
        assert b1_f = to_integer(BIQUAD_LP_B1)
            report "tb_iir_biquad: b1 drift" severity failure;
        assert b2_f = to_integer(BIQUAD_LP_B2)
            report "tb_iir_biquad: b2 drift" severity failure;
        assert a1_f = to_integer(BIQUAD_LP_A1)
            report "tb_iir_biquad: a1 drift" severity failure;
        assert a2_f = to_integer(BIQUAD_LP_A2)
            report "tb_iir_biquad: a2 drift" severity failure;

        -- ─── 데이터 ────────────────────────────────────────────────────
        readline(vec_file, L);
        read(L, n_samples);

        for i in 0 to n_samples-1 loop
            readline(vec_file, L);
            read(L, x_int);
            read(L, y_exp);
            x_arr(i) := x_int;
            y_arr(i) := y_exp;
        end loop;

        -- 리셋
        rst <= '1';
        for i in 1 to 4 loop wait until rising_edge(clk); wait for 1 ns; end loop;
        rst <= '0';
        wait until rising_edge(clk); wait for 1 ns;

        -- 시퀀스 입력
        for i in 0 to n_samples-1 loop
            x_in    <= to_signed(x_arr(i), 16);
            x_valid <= '1';
            wait until rising_edge(clk); wait for 1 ns;

            got := to_integer(y_out);
            assert got = y_arr(i)
                report "tb_iir_biquad: sample " & integer'image(i) &
                       " mismatch: got=" & integer'image(got) &
                       " exp=" & integer'image(y_arr(i))
                severity error;
        end loop;
        x_valid <= '0';

        report "tb_iir_biquad: PASS (" & integer'image(n_samples) &
               " samples, bit-exact)";
        sim_done <= true;
        wait;
    end process;
end architecture;
