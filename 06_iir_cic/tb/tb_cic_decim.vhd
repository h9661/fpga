--=============================================================================
-- tb_cic_decim.vhd — CIC decimator 비트 정합 testbench
--=============================================================================
-- 헤더 1줄: R M N (8 1 3 만 지원하는 RTL — drift 시 immediate fail)
-- 2줄:    N_IN
-- 다음 N_IN 줄: x_q15 (한 줄에 하나)
-- 다음 1줄: N_OUT
-- 마지막 N_OUT 줄: y_q15
--
-- 시뮬: x_in 을 한 cycle 에 한 sample 씩 push, R 입력당 한 출력 비트 비교.
-- y_valid='1' 이 검출되는 시점에서 y_out 정수 비교.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
use std.textio.all;

library work;
    use work.fixed_point_pkg.all;

entity tb_cic_decim is
end entity;

architecture sim of tb_cic_decim is
    constant CLK_PER : time := 10 ns;
    constant R_GEN : positive := 8;
    constant N_GEN : positive := 3;

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal x_valid : std_logic := '0';
    signal x_in    : q15_t := (others => '0');
    signal y_valid : std_logic;
    signal y_out   : q15_t;

    signal sim_done : boolean := false;
begin
    dut : entity work.cic_decim
        generic map (R => R_GEN, N => N_GEN)
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
        file vec_file : text open read_mode is "data/cic_vectors.txt";
        variable L : line;
        variable r_f, m_f, n_f : integer;
        variable n_in, n_out : integer;
        variable v : integer;
        variable got : integer;
        variable out_idx : integer;

        type int_arr_t is array (natural range <>) of integer;
        variable x_arr : int_arr_t(0 to 1023);
        variable y_arr : int_arr_t(0 to 255);
    begin
        -- ─── 헤더 R M N ────────────────────────────────────────────────
        readline(vec_file, L);
        read(L, r_f); read(L, m_f); read(L, n_f);
        assert r_f = R_GEN and m_f = 1 and n_f = N_GEN
            report "tb_cic_decim: header (R M N) drift: file=(" &
                   integer'image(r_f) & "," & integer'image(m_f) & "," &
                   integer'image(n_f) & ") rtl=(" &
                   integer'image(R_GEN) & ",1," & integer'image(N_GEN) & ")"
            severity failure;

        readline(vec_file, L);
        read(L, n_in);
        for i in 0 to n_in-1 loop
            readline(vec_file, L);
            read(L, v);
            x_arr(i) := v;
        end loop;
        readline(vec_file, L);
        read(L, n_out);
        for i in 0 to n_out-1 loop
            readline(vec_file, L);
            read(L, v);
            y_arr(i) := v;
        end loop;

        -- 리셋
        rst <= '1';
        for i in 1 to 4 loop wait until rising_edge(clk); wait for 1 ns; end loop;
        rst <= '0';
        wait until rising_edge(clk); wait for 1 ns;

        out_idx := 0;
        for i in 0 to n_in-1 loop
            x_in    <= to_signed(x_arr(i), 16);
            x_valid <= '1';
            wait until rising_edge(clk); wait for 1 ns;
            -- 매 R 번째 input 직후 y_valid 가 '1' pulse.
            -- (i+1) mod R = 0 인 입력 다음 cycle 의 시작점에 y_out 도 갱신됨.
            if y_valid = '1' then
                got := to_integer(y_out);
                assert out_idx < n_out
                    report "tb_cic_decim: extra y_valid at i=" & integer'image(i)
                    severity failure;
                assert got = y_arr(out_idx)
                    report "tb_cic_decim: out " & integer'image(out_idx) &
                           " mismatch: got=" & integer'image(got) &
                           " exp=" & integer'image(y_arr(out_idx))
                    severity error;
                out_idx := out_idx + 1;
            end if;
        end loop;
        x_valid <= '0';

        assert out_idx = n_out
            report "tb_cic_decim: only got " & integer'image(out_idx) &
                   " outputs, expected " & integer'image(n_out)
            severity failure;

        report "tb_cic_decim: PASS (" & integer'image(n_in) &
               " in -> " & integer'image(n_out) & " out, bit-exact)";
        sim_done <= true;
        wait;
    end process;
end architecture;
