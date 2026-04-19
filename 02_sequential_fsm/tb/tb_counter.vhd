--=============================================================================
-- tb_counter.vhd — counter.vhd 동작/포화/재리셋 검증
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. 클럭을 갖는 TB 의 기본 구조 (clk_gen + stimulus 두 프로세스)
--   2. 'range 속성으로 벡터 폭을 선언 시점에 의존하지 않는 비교식 쓰기
--   3. 시나리오 (리셋 → 카운트 → 포화 → 재리셋) 를 단계별로 검증
--
-- 【이 TB 의 전략】
--   동기 리셋 후 q=0 확인 → en=0 에서 멈춤 확인 → en=1 로 1..15 증가 확인 →
--   최대값 포화 확인 → 재리셋으로 원상 복귀 확인.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_counter is
end entity;

architecture sim of tb_counter is
    constant WIDTH     : positive := 4;
    -- time 리터럴: "<숫자> <단위>" 형식. 단위: fs/ps/ns/us/ms/sec/min/hr.
    -- CLK_PER = 10 ns → 주파수 100 MHz 의 한 주기.
    constant CLK_PER   : time := 10 ns;

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';   -- 초기에 리셋 걸어두고 시작
    signal en        : std_logic := '0';
    signal q         : std_logic_vector(WIDTH-1 downto 0);
    signal saturated : std_logic;

    -- sim_done: clk_gen 루프 종료 플래그. stimulus 가 모든 단계를 마치고
    -- "이제 시뮬레이션 멈춰도 된다" 를 알리는 용도.
    signal sim_done : boolean := false;
begin
    dut : entity work.counter
        generic map (WIDTH => WIDTH)
        port map (clk => clk, rst => rst, en => en, q => q, saturated => saturated);

    --------------------------------------------------------------------------
    -- 【클럭 생성 프로세스】
    --   sensitivity list 가 없는 process 는 본문의 "wait" 로 스케줄 제어.
    --   여기선 while 루프로 무한 토글 + 본문 wait 로 실제 시간 흐름.
    --
    --   clk <= '0' 후 CLK_PER/2 대기, clk <= '1' 후 또 CLK_PER/2 대기 → 한 주기.
    --
    --   sim_done='true' 가 되면 루프 종료 → 마지막 "wait;" 에서 영구 정지.
    --   GHDL 같은 시뮬레이터는 "모든 프로세스가 정지" 를 감지하면 시뮬을 끝낸다.
    --------------------------------------------------------------------------
    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PER/2;
            clk <= '1'; wait for CLK_PER/2;
        end loop;
        wait;
    end process;

    --------------------------------------------------------------------------
    -- 자극/검증 프로세스.
    --------------------------------------------------------------------------
    stimulus : process
    begin
        ----------------------------------------------------------------------
        -- 1) 리셋 시퀀스: 몇 클럭 유지 후 q=0, saturated=0 확인.
        ----------------------------------------------------------------------
        rst <= '1'; en <= '0';
        wait for 3 * CLK_PER;   -- 3 주기 = 3 번의 상승 엣지 경험 보장

        -- 【q'range aggregate 】
        --   q'range = q 의 인덱스 범위. q 는 (WIDTH-1 downto 0) 이므로 여기선
        --   "3 downto 0" 같은 걸 반환한다.
        --   (q'range => '0') 은 "이 범위의 모든 원소를 '0' 으로 채우라" 라는 aggregate.
        --   직접 "0000" 같은 리터럴을 쓰면 WIDTH 를 바꿀 때 일일이 수정해야 해서
        --   generic-친화적인 이 방식이 좋다.
        assert q = (q'range => '0')
            report "after reset q should be 0"
            severity error;
        assert saturated = '0'
            report "after reset saturated should be 0"
            severity error;

        ----------------------------------------------------------------------
        -- 2) rst 해제 후에도 en=0 이면 q 불변이어야 함.
        ----------------------------------------------------------------------
        rst <= '0';
        wait for 3 * CLK_PER;
        assert q = (q'range => '0')
            report "en=0: q should not advance"
            severity error;

        ----------------------------------------------------------------------
        -- 3) en=1 → 1,2,...,15 까지 정확히 증가.
        --    매 클럭 엣지 직후에 q 값을 읽고 기대 정수와 비교.
        ----------------------------------------------------------------------
        en <= '1';
        for i in 1 to 15 loop
            wait until rising_edge(clk);   -- 다음 상승 엣지까지 대기
            wait for 1 ns;                 -- delta 처리 후 안정 상태에서 관찰
            assert unsigned(q) = to_unsigned(i, WIDTH)
                report "count fail at step " & integer'image(i) &
                       ": got=" & integer'image(to_integer(unsigned(q)))
                severity error;
        end loop;

        -- 최대값(15) 도달 → saturated='1'
        assert saturated = '1'
            report "saturated should assert when q=max"
            severity error;

        ----------------------------------------------------------------------
        -- 4) 포화 유지: 추가 클럭을 더 줘도 q=15 그대로.
        ----------------------------------------------------------------------
        for i in 1 to 5 loop
            wait until rising_edge(clk);
            wait for 1 ns;
            assert unsigned(q) = to_unsigned(15, WIDTH)
                report "saturation fail: q should stay at 15"
                severity error;
        end loop;

        ----------------------------------------------------------------------
        -- 5) 재리셋: 동작 중에도 rst='1' 한 클럭이면 즉시 0 으로 복귀.
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

        -- 모든 단계 통과.
        report "tb_counter: PASS";
        sim_done <= true;
        wait;
    end process;
end architecture;
