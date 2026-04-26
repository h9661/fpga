--=============================================================================
-- tb_fir.vhd — 8-tap LP FIR 비트 정합 testbench
--=============================================================================
-- 【검증 전략】
--   1. 첫 줄 "N_TAPS c0 c1 ... c7" 을 읽어 LP8_COEFS 패키지 상수와 일치 검사
--      → 계수 drift 즉시 감지.
--   2. "N_SAMPLES" 읽기.
--   3. (x_q15[i], y_q15_exp[i]) 64 sample 을 한 cycle 에 한 sample 씩 입력하고
--      1-cycle latency 후 y_out 정수 비교.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
use std.textio.all;

library work;
    use work.fixed_point_pkg.all;
    use work.fir_coeffs_pkg.all;

entity tb_fir is
end entity;

architecture sim of tb_fir is
    constant CLK_PER : time := 10 ns;

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal x_valid : std_logic := '0';
    signal x_in    : q15_t := (others => '0');
    signal y_valid : std_logic;
    signal y_out   : q15_t;

    signal sim_done : boolean := false;
begin
    dut : entity work.fir
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
        file vec_file : text open read_mode is "data/fir_vectors.txt";
        variable L         : line;
        variable n_taps    : integer;
        variable n_samples : integer;
        variable c_int, x_int, y_int_exp : integer;
        variable got       : integer;

        type int_arr_t is array (natural range <>) of integer;
        variable x_arr : int_arr_t(0 to 1023);
        variable y_arr : int_arr_t(0 to 1023);
    begin
        -- ─── 헤더: N_TAPS + 계수 ──────────────────────────────────────────
        readline(vec_file, L);
        read(L, n_taps);
        assert n_taps = LP8_COEFS'length
            report "tb_fir: N_TAPS mismatch: file=" & integer'image(n_taps) &
                   " pkg=" & integer'image(LP8_COEFS'length)
            severity failure;

        for k in 0 to n_taps-1 loop
            read(L, c_int);
            assert to_integer(LP8_COEFS(k)) = c_int
                report "tb_fir: coef[" & integer'image(k) & "] drift: file=" &
                       integer'image(c_int) & " pkg=" &
                       integer'image(to_integer(LP8_COEFS(k)))
                severity failure;
        end loop;

        -- ─── N_SAMPLES + 데이터 ─────────────────────────────────────────────
        readline(vec_file, L);
        read(L, n_samples);
        assert n_samples > 0 and n_samples <= 1024
            report "tb_fir: bad N_SAMPLES=" & integer'image(n_samples)
            severity failure;

        for i in 0 to n_samples-1 loop
            readline(vec_file, L);
            read(L, x_int);
            read(L, y_int_exp);
            x_arr(i) := x_int;
            y_arr(i) := y_int_exp;
        end loop;

        -- ─── 리셋 ────────────────────────────────────────────────────────
        rst <= '1'; x_valid <= '0';
        for i in 1 to 4 loop
            wait until rising_edge(clk); wait for 1 ns;
        end loop;
        rst <= '0';
        wait until rising_edge(clk); wait for 1 ns;

        -- ─── 시퀀스 입력 ──────────────────────────────────────────────────
        -- 매 입력 후 1 cycle 지연으로 y_out 갱신.
        for i in 0 to n_samples-1 loop
            x_in    <= to_signed(x_arr(i), 16);
            x_valid <= '1';
            wait until rising_edge(clk); wait for 1 ns;

            -- 이 시점 y_out = h[0]·x_arr(i) + h[1]·x_dly(0) + ... 이며 Python
            -- 에서 같은 계수·같은 라운딩으로 계산한 y_arr(i) 와 비트 정합.
            got := to_integer(y_out);
            assert got = y_arr(i)
                report "tb_fir: sample " & integer'image(i) &
                       " mismatch: got=" & integer'image(got) &
                       " exp=" & integer'image(y_arr(i))
                severity error;
            assert y_valid = '1'
                report "tb_fir: y_valid should be '1' at sample " &
                       integer'image(i)
                severity error;
        end loop;
        x_valid <= '0';

        -- 1 cycle 후 y_valid='0' 으로 떨어져야 (1-cycle pulse 패턴)
        wait until rising_edge(clk); wait for 1 ns;
        assert y_valid = '0'
            report "tb_fir: y_valid should deassert after sequence end"
            severity error;

        report "tb_fir: PASS (" & integer'image(n_samples) &
               " samples, bit-exact)";
        sim_done <= true;
        wait;
    end process;
end architecture;
