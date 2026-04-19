--=============================================================================
-- tb_fifo.vhd — fifo.vhd 검증용 테스트벤치 (시뮬레이션 전용, 합성 대상 아님)
--=============================================================================
-- 테스트벤치의 역할:
--   1) DUT(Device Under Test)를 인스턴스화하고 신호를 모두 연결.
--   2) 클럭/리셋을 인공적으로 생성.
--   3) 자극(stimulus)을 인가하고 기대값을 assert로 검증.
--
-- 시뮬레이션 전용 구문 (합성 불가):
--   wait for <time>, wait until, assert/report, time literal, file I/O 등.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

-- 테스트벤치 entity는 port가 없다. 시뮬레이션에서 최상위(top)로 "자기 자신"이 됨.
entity tb_fifo is
end entity;

architecture sim of tb_fifo is
    --------------------------------------------------------------------------
    -- 테스트 파라미터
    --------------------------------------------------------------------------
    constant WIDTH   : positive := 8;
    constant DEPTH   : positive := 8;
    -- time: VHDL 기본 제공 물리(physical) 타입. 단위: fs/ps/ns/us/ms/sec/min/hr.
    constant CLK_PER : time := 10 ns;

    --------------------------------------------------------------------------
    -- DUT 연결용 신호 (TB와 DUT의 port 를 잇는 와이어)
    --------------------------------------------------------------------------
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

    -- boolean 도 VHDL 기본 타입. clk 생성 루프 종료 플래그로 사용.
    signal sim_done : boolean := false;

    --------------------------------------------------------------------------
    -- procedure tick: n 개의 상승엣지 만큼 대기
    --   * procedure 는 parameter 마다 class(in/out/inout/signal/variable/constant)를
    --     명시. 여기선 n은 in constant (문법상 constant 생략 가능, 기본이 constant).
    --   * 본문에 wait 이 등장 → 이 procedure 는 반드시 process 문맥에서 호출되어야 함.
    --   * "wait for 1 ns"는 signal 업데이트가 안정된 다음 순간을 관찰하려는 관용구
    --     (rising_edge 직후에는 delta-cycle 전파가 남아있어 값이 불안정할 수 있음).
    --------------------------------------------------------------------------
    procedure tick(n : in positive) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
    end procedure;

    --------------------------------------------------------------------------
    -- procedure write_value: din/wr_en 을 한 클럭 펄스로 인가
    --   * signal 인자는 모드(in/out)에 따라 읽기/쓰기 권한이 달라진다.
    --     in → 읽기 전용, out → 쓰기 전용.
    --   * "signal clk_s : in std_logic" 처럼 "signal" 키워드가 있어야 실제 signal 이
    --     procedure 안으로 넘어간다 (없으면 값 복사 — wait 불가능).
    --------------------------------------------------------------------------
    procedure write_value(signal clk_s   : in    std_logic;
                          signal wr_en_s : out   std_logic;
                          signal din_s   : out   std_logic_vector(WIDTH-1 downto 0);
                          v : in natural) is
    begin
        -- natural v 를 WIDTH 비트 unsigned → std_logic_vector 로 변환해 din 에 드라이브.
        din_s   <= std_logic_vector(to_unsigned(v, WIDTH));
        wr_en_s <= '1';
        wait until rising_edge(clk_s);
        wait for 1 ns;
        wr_en_s <= '0';
    end procedure;

    --------------------------------------------------------------------------
    -- procedure read_value: FWFT 규약 → rd_en 올리기 직전에 dout 을 샘플해 비교
    --   순서가 중요: (a) dout 샘플 → (b) 기대값과 assert → (c) rd_en 펄스로 포인터 전진
    --
    --   variable vs signal:
    --     variable ":=" 는 즉시 반영 (블로킹, C의 = 에 유사).
    --     signal   "<=" 는 스케줄링 후 반영 (delta 사이클 뒤).
    --------------------------------------------------------------------------
    procedure read_value(signal clk_s   : in    std_logic;
                         signal rd_en_s : out   std_logic;
                         signal dout_s  : in    std_logic_vector(WIDTH-1 downto 0);
                         expected : in natural) is
        variable got : natural;
    begin
        got := to_integer(unsigned(dout_s));

        -- assert 문: 조건이 false면 report 메시지를 지정 severity 로 출력.
        --   severity: note < warning < error < failure.
        --   보통 시뮬레이터는 error/failure 시 옵션에 따라 실행을 중단한다.
        --   "&" 는 문자열/벡터 concatenation, integer'image(n) 은 정수→문자열 속성.
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
    -- DUT 인스턴스화 — direct entity instantiation (component 선언 생략 가능)
    --   문법: <label> : entity <library>.<entity>[(<arch>)]
    --           [ generic map (...) ] [ port map (...) ];
    --   "work" 는 현재 컴파일 중인 library 의 기본 논리적 이름.
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
    -- 클럭 생성 프로세스
    --   sensitivity list 없는 process 는 본문의 wait 문으로 일시정지한다.
    --   while 루프로 무한 토글, sim_done 되면 "wait;" (영구 대기) 에서 멈춤.
    --------------------------------------------------------------------------
    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PER/2;
            clk <= '1'; wait for CLK_PER/2;
        end loop;
        wait;   -- 프로세스 영구 정지 (이후 어떤 이벤트에도 깨어나지 않음)
    end process;

    --------------------------------------------------------------------------
    -- 자극 드라이버 프로세스 — 시나리오들을 순서대로 수행
    --------------------------------------------------------------------------
    stimulus : process
    begin
        ----------------------------------------------------------------------
        -- 리셋 시퀀스: rst 유지하며 몇 클럭 대기, 초기 상태 확인
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
        -- 시나리오 1: DEPTH 개 쓰기 → full 에 도달
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
        -- 시나리오 2: DEPTH 개 읽기 — FIFO 순서 (들어간 순서로 나와야 함)
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
        -- 시나리오 3: Overflow — 꽉 찬 상태에서 wr_en 시도는 무시되어야 함
        ----------------------------------------------------------------------
        for i in 0 to DEPTH-1 loop
            write_value(clk, wr_en, din, i + 100);  -- 100..107 저장
        end loop;
        tick(1);
        assert full = '1' report "pre-overflow: full=1 expected" severity error;

        -- 5 사이클 동안 추가 write 시도 → count 는 DEPTH 유지되어야 함.
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

        -- 원래 넣은 데이터가 그대로 보존되었는지 확인하며 비움.
        for i in 0 to DEPTH-1 loop
            read_value(clk, rd_en, dout, i + 100);
        end loop;
        tick(1);
        assert empty = '1' report "after full-drain: empty=1 expected" severity error;

        ----------------------------------------------------------------------
        -- 시나리오 4: Underflow — 비어있는데 rd_en 시도는 count 불변
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
        -- 시나리오 5: almost_full / almost_empty 플래그 전이 확인
        ----------------------------------------------------------------------
        -- DEPTH-1 개 쓰면 count=DEPTH-1 → almost_full 활성, full은 아직 0.
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

        -- 모두 비움.
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

        -- 다음 시나리오를 위해 2개 빼둠 (count=0).
        for i in 1 to 2 loop
            rd_en <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        rd_en <= '0';
        tick(1);

        ----------------------------------------------------------------------
        -- 시나리오 6: 동시 wr/rd — count 불변이어야 함
        ----------------------------------------------------------------------
        for i in 0 to DEPTH/2 - 1 loop
            write_value(clk, wr_en, din, i + 50);  -- 절반까지 채움
        end loop;
        tick(1);
        assert to_integer(unsigned(count)) = DEPTH/2
            report "pre-concurrent: count should be DEPTH/2"
            severity error;

        -- wr_en=rd_en=1 을 5 사이클 유지 → count 는 DEPTH/2 그대로.
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
        --   report 만 쓰면 severity 기본값은 note (단순 정보 메시지).
        --   sim_done 을 true 로 두면 clk_gen 루프가 종료되고 시뮬레이션이 멈춘다.
        ----------------------------------------------------------------------
        report "tb_fifo: PASS (all)";
        sim_done <= true;
        wait;   -- stimulus 프로세스도 영구 정지
    end process;
end architecture;
