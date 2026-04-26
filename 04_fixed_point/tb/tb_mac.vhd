--=============================================================================
-- tb_mac.vhd — MAC 비트 정합 testbench
--=============================================================================
-- 【검증 전략】
--   1. Python(numpy) 이 미리 만든 골든 벡터 파일을 std.textio 로 읽는다.
--   2. (a, b) 를 한 cycle 에 한 쌍씩 push, 3-cycle latency 후 acc_out 읽기.
--   3. integer 비교로 한 LSB 라도 어긋나면 FAIL.
--
-- 【두 시나리오】
--   시나리오 A — 연속 push: 16 샘플을 cycle 마다 한 개씩 입력. 모든 입력이
--                들어간 뒤 3 cycle 더 기다린 시점에서 final acc 비교.
--   시나리오 B — 격리 push: 매 입력 후 3 cycle 비우기. 매 샘플의 부분 누산
--                 acc[i] 가 acc_arr(i) 와 일치하는지 검증.
--
-- 【textio file path】
--   GHDL 은 ghdl -r 의 cwd 를 기준으로 file 경로를 해석한다. Makefile 이
--   언제나 04_fixed_point/ 에서 호출하므로 "data/mac_vectors.txt" 로 충분.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
use std.textio.all;

library work;
    use work.fixed_point_pkg.all;

entity tb_mac is
end entity;

architecture sim of tb_mac is
    constant CLK_PER : time := 10 ns;

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal clr       : std_logic := '0';
    signal in_valid  : std_logic := '0';
    signal a_in      : q15_t := (others => '0');
    signal b_in      : q15_t := (others => '0');
    signal acc_out   : signed(39 downto 0);
    signal out_valid : std_logic;

    signal sim_done : boolean := false;
begin
    dut : entity work.mac
        port map (
            clk       => clk,
            rst       => rst,
            clr       => clr,
            in_valid  => in_valid,
            a_in      => a_in,
            b_in      => b_in,
            acc_out   => acc_out,
            out_valid => out_valid
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
        file vec_file : text open read_mode is "data/mac_vectors.txt";
        variable L         : line;
        variable n_samples : integer;
        variable a_int     : integer;
        variable b_int     : integer;
        variable acc_exp   : integer;

        type int_arr_t is array (natural range <>) of integer;
        variable a_arr   : int_arr_t(0 to 1023);
        variable b_arr   : int_arr_t(0 to 1023);
        variable acc_arr : int_arr_t(0 to 1023);
        variable got     : integer;
    begin
        -- ─── 골든 벡터 읽기 ────────────────────────────────────────────
        readline(vec_file, L);
        read(L, n_samples);
        assert n_samples > 0 and n_samples <= 1024
            report "tb_mac: bad N=" & integer'image(n_samples)
            severity failure;

        for i in 0 to n_samples-1 loop
            readline(vec_file, L);
            read(L, a_int);
            read(L, b_int);
            read(L, acc_exp);
            a_arr(i)   := a_int;
            b_arr(i)   := b_int;
            acc_arr(i) := acc_exp;
        end loop;

        -- ─── 리셋 + clr ─────────────────────────────────────────────────
        rst <= '1'; clr <= '0'; in_valid <= '0';
        for i in 1 to 4 loop
            wait until rising_edge(clk); wait for 1 ns;
        end loop;
        rst <= '0';
        clr <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        clr <= '0';
        wait until rising_edge(clk); wait for 1 ns;

        assert acc_out = to_signed(0, 40)
            report "after rst+clr: acc should be 0"
            severity error;

        -- ─── 시나리오 A: 연속 push ─────────────────────────────────────
        for i in 0 to n_samples-1 loop
            a_in     <= to_signed(a_arr(i), 16);
            b_in     <= to_signed(b_arr(i), 16);
            in_valid <= '1';
            wait until rising_edge(clk); wait for 1 ns;
        end loop;
        in_valid <= '0';

        -- 마지막 샘플이 누산기에 반영될 때까지 추가로 3 cycle 대기.
        for i in 1 to 3 loop
            wait until rising_edge(clk); wait for 1 ns;
        end loop;

        got := to_integer(acc_out);
        assert got = acc_arr(n_samples-1)
            report "tb_mac: scenario-A final acc mismatch: got=" &
                   integer'image(got) &
                   " expected=" & integer'image(acc_arr(n_samples-1))
            severity error;

        -- ─── 시나리오 B: 격리 push (부분 누산 정합) ─────────────────────
        rst <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        rst <= '0';
        clr <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        clr <= '0';
        wait until rising_edge(clk); wait for 1 ns;

        for i in 0 to n_samples-1 loop
            a_in     <= to_signed(a_arr(i), 16);
            b_in     <= to_signed(b_arr(i), 16);
            in_valid <= '1';
            wait until rising_edge(clk); wait for 1 ns;
            in_valid <= '0';

            -- 3 cycle 더 기다리면 i 번째 곱이 acc 까지 도달.
            for k in 1 to 3 loop
                wait until rising_edge(clk); wait for 1 ns;
            end loop;

            got := to_integer(acc_out);
            assert got = acc_arr(i)
                report "tb_mac: scenario-B partial acc mismatch at i=" &
                       integer'image(i) &
                       " got=" & integer'image(got) &
                       " expected=" & integer'image(acc_arr(i))
                severity error;
        end loop;

        report "tb_mac: PASS (" & integer'image(n_samples) &
               " samples, bit-exact)";
        sim_done <= true;
        wait;
    end process;
end architecture;
