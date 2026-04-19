--=============================================================================
-- tb_fifo.vhd — fifo.vhd 검증용 테스트벤치 (시뮬 전용, 합성 대상 아님)
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. 큰 테스트벤치의 구조 — 여러 시나리오를 단계별로 실행
--   2. procedure 파라미터의 signal / in / out 조합
--   3. FWFT 규약에 맞춘 읽기 헬퍼 (dout 샘플 → rd_en 펄스 순서)
--   4. 오버플로/언더플로/almost-full 등 경계 동작 검증 패턴
--
-- 【시나리오 구성】
--   1) 리셋
--   2) DEPTH 개 쓰기 → full 도달 확인
--   3) DEPTH 개 읽기 → FIFO 순서 확인
--   4) 오버플로 무시 → count 불변
--   5) 언더플로 무시 → count 불변
--   6) almost_full / almost_empty 전이 확인
--   7) 동시 wr/rd → count 불변
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_fifo is
end entity;

architecture sim of tb_fifo is
    constant WIDTH   : positive := 8;
    constant DEPTH   : positive := 8;
    constant CLK_PER : time := 10 ns;

    -- DUT 연결 신호들.
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

    --------------------------------------------------------------------------
    -- 【tick(n): n 개의 상승 엣지만큼 대기】
    --   * in 파라미터는 기본 class 가 constant (변경 불가).
    --   * 본문에 wait 이 있으므로 process context 에서만 호출 가능.
    --   * "wait for 1 ns" 는 엣지 직후의 delta 가 모두 처리된 "안정된 순간" 에
    --     signal 을 관찰하기 위한 관용구.
    --------------------------------------------------------------------------
    procedure tick(n : in positive) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
    end procedure;

    --------------------------------------------------------------------------
    -- 【write_value: 한 클럭짜리 wr_en 펄스로 값을 저장】
    --
    --   procedure 파라미터 class 설명:
    --     signal clk_s   : in  std_logic  → 외부 clk 를 signal 로 참조 (wait 가능)
    --     signal wr_en_s : out std_logic  → 호출자의 wr_en 을 직접 드라이브
    --     signal din_s   : out slv        → din 도 마찬가지
    --     v              : in natural     → 숫자 값 (기본 class = constant)
    --
    --   "signal" 키워드 없이 파라미터를 썼다면 값이 "복사" 되어 들어와 wait 중
    --   값이 바뀌어도 보이지 않는다. wait 가 필요한 procedure 에선 signal 필수.
    --------------------------------------------------------------------------
    procedure write_value(signal clk_s   : in    std_logic;
                          signal wr_en_s : out   std_logic;
                          signal din_s   : out   std_logic_vector(WIDTH-1 downto 0);
                          v : in natural) is
    begin
        din_s   <= std_logic_vector(to_unsigned(v, WIDTH));
        wr_en_s <= '1';
        wait until rising_edge(clk_s);
        wait for 1 ns;
        wr_en_s <= '0';
    end procedure;

    --------------------------------------------------------------------------
    -- 【read_value: FWFT 규약 — 읽고 비교 후 rd_en 펄스】
    --
    -- 순서가 중요:
    --   (a) 먼저 dout 을 샘플해 기대값과 assert 로 비교
    --   (b) 그 후에 rd_en 을 1 사이클 올려 rd_ptr 을 전진
    --
    -- 이유: FWFT 에선 dout = ram(rd_ptr) 로 "현재 head" 가 항상 보인다.
    --       rd_en 을 먼저 올리면 다음 엣지에 포인터가 전진해 "다음 워드" 가
    --       dout 에 나타난다. 검증 대상은 "현재 head" 이므로 올리기 전에
    --       샘플해야 맞다.
    --
    -- variable got : natural  → 지역 변수. ":=" 로 즉시 대입 (블로킹).
    --                           변환 과정을 한 번에 담기 편리.
    --------------------------------------------------------------------------
    procedure read_value(signal clk_s   : in    std_logic;
                         signal rd_en_s : out   std_logic;
                         signal dout_s  : in    std_logic_vector(WIDTH-1 downto 0);
                         expected : in natural) is
        variable got : natural;
    begin
        got := to_integer(unsigned(dout_s));

        -- 실패 시 진단에 필요한 정보를 풍부하게 담는다. "&" 로 문자열 이어붙이기.
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
    --------------------------------------------------------------------------
    -- DUT 인스턴스화.
    --------------------------------------------------------------------------
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

    --------------------------------------------------------------------------
    -- 클럭 생성.
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
        -- 1) 리셋: 몇 클럭 유지 후 empty/count=0 확인
        ----------------------------------------------------------------------
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

        ----------------------------------------------------------------------
        -- 2) DEPTH 개 쓰기 → full 도달
        ----------------------------------------------------------------------
        for i in 0 to DEPTH-1 loop
            assert full = '0'
                report "should not be full at i=" & integer'image(i)
                severity error;
            write_value(clk, wr_en, din, i * 11);   -- 0, 11, 22, ... 저장
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

        ----------------------------------------------------------------------
        -- 3) DEPTH 개 읽기 — FIFO 순서 (들어간 순서 그대로 나와야)
        ----------------------------------------------------------------------
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

        ----------------------------------------------------------------------
        -- 4) 오버플로: 꽉 찬 상태에서 wr_en 을 올려도 count 불변
        --    데이터도 안 깨져야 함 — 원래 저장한 i+100 값이 그대로 나와야.
        ----------------------------------------------------------------------
        for i in 0 to DEPTH-1 loop
            write_value(clk, wr_en, din, i + 100);  -- 100..107 저장
        end loop;
        tick(1);
        assert full = '1' report "pre-overflow: full=1 expected" severity error;

        -- 5 사이클간 "꽉 찬 상태에서 추가 쓰기 시도" → count = DEPTH 유지 확인
        for i in 0 to 4 loop
            din <= std_logic_vector(to_unsigned(255, WIDTH));
            wr_en <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            assert to_integer(unsigned(count)) = DEPTH
                report "overflow: count should stay at DEPTH"
                severity error;
        end loop;
        wr_en <= '0';

        -- 이제 비우면서 원래 값이 그대로인지 확인.
        for i in 0 to DEPTH-1 loop
            read_value(clk, rd_en, dout, i + 100);
        end loop;
        tick(1);
        assert empty = '1' report "after full-drain: empty=1 expected" severity error;

        ----------------------------------------------------------------------
        -- 5) 언더플로: 비어있는데 rd_en 시도 → count 불변 (=0)
        ----------------------------------------------------------------------
        for i in 0 to 4 loop
            rd_en <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            assert to_integer(unsigned(count)) = 0
                report "underflow: count should stay at 0"
                severity error;
        end loop;
        rd_en <= '0';

        ----------------------------------------------------------------------
        -- 6) almost_full / almost_empty 플래그 전이
        ----------------------------------------------------------------------
        -- DEPTH-1 개 쓰기 → count=DEPTH-1 → almost_full='1', full='0'
        for i in 0 to DEPTH-2 loop
            write_value(clk, wr_en, din, i);
        end loop;
        tick(1);
        assert almost_full = '1'
            report "almost_full should assert at count=DEPTH-1"
            severity error;
        assert full = '0'
            report "not quite full yet"
            severity error;

        write_value(clk, wr_en, din, 99);   -- 한 개 더 → full
        tick(1);
        assert full = '1' report "full after one more" severity error;

        -- 모두 비움
        for i in 0 to DEPTH-1 loop
            rd_en <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        rd_en <= '0';
        tick(1);
        assert empty = '1' report "fully drained" severity error;
        assert almost_empty = '1' report "almost_empty at count=0" severity error;

        write_value(clk, wr_en, din, 42);   -- count=1
        tick(1);
        assert almost_empty = '1'
            report "almost_empty should assert at count=1"
            severity error;
        assert empty = '0'
            report "not empty anymore"
            severity error;

        write_value(clk, wr_en, din, 43);   -- count=2 → almost_empty 해제
        tick(1);
        assert almost_empty = '0'
            report "almost_empty should deassert at count=2"
            severity error;

        -- 다음 시나리오 준비: count=0 으로 비우기
        for i in 1 to 2 loop
            rd_en <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        rd_en <= '0';
        tick(1);

        ----------------------------------------------------------------------
        -- 7) 동시 wr/rd → count 불변
        ----------------------------------------------------------------------
        for i in 0 to DEPTH/2 - 1 loop
            write_value(clk, wr_en, din, i + 50);  -- 절반까지 채움
        end loop;
        tick(1);
        assert to_integer(unsigned(count)) = DEPTH/2
            report "pre-concurrent: count should be DEPTH/2"
            severity error;

        -- wr_en=rd_en=1 을 5 사이클 유지 → count = DEPTH/2 그대로
        for i in 0 to 4 loop
            din <= std_logic_vector(to_unsigned(i + 200, WIDTH));
            wr_en <= '1';
            rd_en <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            assert to_integer(unsigned(count)) = DEPTH/2
                report "concurrent wr+rd: count should remain DEPTH/2, got=" &
                       integer'image(to_integer(unsigned(count)))
                severity error;
        end loop;
        wr_en <= '0';
        rd_en <= '0';

        ----------------------------------------------------------------------
        -- 종료
        ----------------------------------------------------------------------
        report "tb_fifo: PASS (all)";
        sim_done <= true;
        wait;
    end process;
end architecture;
