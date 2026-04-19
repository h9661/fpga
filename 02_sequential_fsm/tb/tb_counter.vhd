--=============================================================================
-- tb_counter.vhd — counter.vhd 동작/포화/재리셋 검증
--=============================================================================
-- 시나리오:
--   1) 리셋: q=0, saturated=0 확인
--   2) en=0 에서 클럭 여러 개 → q 불변 확인
--   3) en=1 → 1~15 까지 정확히 증가하는지 확인
--   4) 포화: saturated='1', 추가 클럭에서도 q=15 유지
--   5) 재리셋: q=0, saturated=0 복귀
--=============================================================================

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

    -- 클럭 생성: sensitivity list 없는 process 는 본문 wait 로 제어.
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
        ----------------------------------------------------------------------
        -- 1) 리셋 시퀀스
        ----------------------------------------------------------------------
        rst <= '1'; en <= '0';
        wait for 3 * CLK_PER;

        -- q'range: 'RANGE 는 해당 신호/타입의 인덱스 범위를 돌려주는 속성.
        -- q 는 (WIDTH-1 downto 0) 이므로 q'range = "3 downto 0" 같이 해석된다.
        -- (q'range => '0') 은 "그 범위의 모든 원소를 '0' 으로" 라는 aggregate.
        assert q = (q'range => '0')
            report "after reset q should be 0"
            severity error;
        assert saturated = '0'
            report "after reset saturated should be 0"
            severity error;

        ----------------------------------------------------------------------
        -- 2) rst 해제 후에도 en=0 이면 q 불변이어야 함
        ----------------------------------------------------------------------
        rst <= '0';
        wait for 3 * CLK_PER;
        assert q = (q'range => '0')
            report "en=0: q should not advance"
            severity error;

        ----------------------------------------------------------------------
        -- 3) en=1 → 1,2,...,15 까지 정확히 증가
        ----------------------------------------------------------------------
        en <= '1';
        for i in 1 to 15 loop
            wait until rising_edge(clk);
            wait for 1 ns;
            assert unsigned(q) = to_unsigned(i, WIDTH)
                report "count fail at step " & integer'image(i) &
                       ": got=" & integer'image(to_integer(unsigned(q)))
                severity error;
        end loop;

        -- 최대값 도달 → saturated = '1'
        assert saturated = '1'
            report "saturated should assert when q=max"
            severity error;

        ----------------------------------------------------------------------
        -- 4) 포화 유지: 추가 클럭에도 q=15 그대로
        ----------------------------------------------------------------------
        for i in 1 to 5 loop
            wait until rising_edge(clk);
            wait for 1 ns;
            assert unsigned(q) = to_unsigned(15, WIDTH)
                report "saturation fail: q should stay at 15"
                severity error;
        end loop;

        ----------------------------------------------------------------------
        -- 5) 재리셋 확인
        ----------------------------------------------------------------------
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
