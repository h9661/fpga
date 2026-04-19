--=============================================================================
-- tb_alu.vhd — alu.vhd 전수 검증 테스트벤치
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. 테스트벤치(testbench, "TB") 의 개념과 왜 필요한가
--   2. port 없는 entity 가 무엇을 의미하는가
--   3. function 정의 문법 (return 값 있는 subprogram)
--   4. 3중 for 루프로 "전수 조사" 검증하기
--   5. assert / report / severity 를 쓴 자동 검증
--
-- ─────────────────────────────────────────────────────────────────────────
-- 【테스트벤치란?】
--   DUT(Device Under Test, 검증 대상 모듈) 에 자극(stimulus) 을 인가하고
--   결과가 기대대로인지 확인하는 "시뮬레이션 전용" VHDL 파일.
--   TB 자체는 합성 대상이 아니므로 "wait for 1 ns" 같은 물리 시간 구문,
--   파일 I/O 등 비합성 구문을 마음껏 써도 된다.
--
--   소프트웨어의 "단위 테스트" 에 해당. DUT 를 입출력만으로 블랙박스 취급한다.
--
-- 【이 TB 의 전략】
--   3중 for 루프로 op = 0..6, a = 0..15, b = 0..15 전 조합(7 × 16 × 16 = 1,792 개)
--   을 한 번씩 인가하고, "reference function" 으로 계산한 기대값과 DUT 출력을
--   매번 비교한다. 조합 회로의 장점: 4비트 작으니 전수 검사 가능!
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

-- ─── port 없는 entity ──────────────────────────────────────────────────────
-- TB 는 시뮬레이션의 "최상위(top)" 로 단독 실행된다. 외부와 연결할 핀이 없으므로
-- port 절이 비어 있다. ("port 절을 생략" 가능 — entity 헤더만 남는 모양)
entity tb_alu is
end entity;

architecture sim of tb_alu is
    -- DUT 내부 상수와 동일한 정의를 TB 에도 둔다.
    -- (실무에선 두 곳에 중복을 두지 않게 package 로 공유하지만 여기선 간단히.)
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_SUB : std_logic_vector(2 downto 0) := "001";
    constant OP_AND : std_logic_vector(2 downto 0) := "010";
    constant OP_OR  : std_logic_vector(2 downto 0) := "011";
    constant OP_XOR : std_logic_vector(2 downto 0) := "100";
    constant OP_SHL : std_logic_vector(2 downto 0) := "101";
    constant OP_SHR : std_logic_vector(2 downto 0) := "110";

    -- 자극 신호: DUT 의 port 와 이름/타입/폭을 맞춰 선언.
    -- 초기값 (others => '0'): "모든 비트 '0' 으로 초기화" aggregate.
    signal a, b  : std_logic_vector(3 downto 0) := (others => '0');
    signal op    : std_logic_vector(2 downto 0) := (others => '0');
    signal y     : std_logic_vector(3 downto 0);

    --------------------------------------------------------------------------
    -- 【function 이란?】
    --   입력을 받아 값 하나를 반환하는 "순수 함수". 수학 함수와 동일 개념.
    --
    --   문법:
    --     function <이름>(<파라미터 목록>) return <타입> is
    --         <선언부 (variable 등)>
    --     begin
    --         ...
    --         return <값>;
    --     end function;
    --
    --   제약:
    --     * side effect 없음 (signal 대입 불가, wait 불가) → "순수" 함수.
    --     * 파라미터는 기본이 constant (in). signal 받으려면 "signal" 키워드 명시.
    --
    -- 【procedure 와의 차이】
    --   * function : 값 1개 반환. 조합 계산용.
    --   * procedure: 반환값 없음. out/inout 파라미터로 여러 값을 돌려줄 수 있고,
    --               wait 도 쓸 수 있어 자극 생성에 적합.
    --
    -- 【reference function 의 역할】
    --   DUT 의 구현과 독립적인 "기대값 계산기". DUT 가 이 함수와 결과가 같으면
    --   정답으로 본다. TB 에서 버그가 같은 방식으로 복제되면 의미가 없으므로
    --   실무에선 "수식 수준의 간단한 참조 구현" 을 두고 대조한다.
    --------------------------------------------------------------------------
    function expected(a_in, b_in : std_logic_vector(3 downto 0);
                      op_in : std_logic_vector(2 downto 0))
        return std_logic_vector is
        variable au, bu : unsigned(3 downto 0);
    begin
        au := unsigned(a_in);
        bu := unsigned(b_in);
        case op_in is
            when OP_ADD => return std_logic_vector(au + bu);
            when OP_SUB => return std_logic_vector(au - bu);
            when OP_AND => return a_in and b_in;
            when OP_OR  => return a_in or  b_in;
            when OP_XOR => return a_in xor b_in;
            when OP_SHL => return std_logic_vector(shift_left (au, to_integer(bu(1 downto 0))));
            when OP_SHR => return std_logic_vector(shift_right(au, to_integer(bu(1 downto 0))));
            -- 검증 안 쓰는 case 는 의도적으로 "XXXX" 반환 → 실수로 맞지 않게 함.
            when others => return "XXXX";
        end case;
    end function;
begin
    -- ─── DUT 인스턴스화 ───────────────────────────────────────────────────
    -- 문법: <label> : entity <library>.<entity> [generic map(...)] [port map(...)];
    -- work 은 "현재 컴파일 중인 라이브러리" 의 논리적 기본 이름.
    -- 동명 연결을 "x => x" 로 명시해야 가독성이 좋다 (위치 기반 연결은 버그 온상).
    dut : entity work.alu
        port map (a => a, b => b, op => op, y => y);

    --------------------------------------------------------------------------
    -- 자극 프로세스: 3중 for 루프로 전수 조사.
    --------------------------------------------------------------------------
    stimulus : process
    begin
        for op_i in 0 to 6 loop
            -- 정수 → 3비트 slv: to_unsigned(정수, 폭) → std_logic_vector(...).
            op <= std_logic_vector(to_unsigned(op_i, 3));
            for i in 0 to 15 loop
                for j in 0 to 15 loop
                    a <= std_logic_vector(to_unsigned(i, 4));
                    b <= std_logic_vector(to_unsigned(j, 4));

                    -- 【wait for 1 ns 관용구】
                    -- signal "<=" 는 즉시 반영되지 않고 "delta 사이클" 이라는
                    -- 무한소 시간 뒤에 반영된다. 조합 회로라도 시뮬 단계에서는
                    -- 이 delta 가 쌓여 실제로 값이 퍼지기까지 시간이 필요.
                    -- "wait for 1 ns" 를 넣어 실제 시간이 1 ns 흐르게 하면
                    -- 그동안 모든 delta 가 처리되어 y 가 안정된 값을 갖는다.
                    wait for 1 ns;

                    -- 【assert 문】
                    --   assert <조건> report <메시지> severity <수준>;
                    --   조건이 false 일 때만 메시지 출력, severity 에 따라 시뮬 동작 결정.
                    --   severity 수준:
                    --     note     → 단순 정보 (계속 진행)
                    --     warning  → 경고 (계속 진행)
                    --     error    → 오류 (보통 계속 진행하지만 옵션으로 중단 가능)
                    --     failure  → 치명 (시뮬레이션 즉시 중단)
                    --   "&" 는 문자열/벡터 연결 연산자.
                    --   <타입>'image(v) 는 값을 문자열로 바꿔주는 속성.
                    assert y = expected(a, b, op)
                        report "op=" & integer'image(op_i) &
                               " a=" & integer'image(i) &
                               " b=" & integer'image(j) &
                               " got=" & integer'image(to_integer(unsigned(y))) &
                               " expected=" & integer'image(to_integer(unsigned(expected(a,b,op))))
                        severity error;
                end loop;
            end loop;
        end loop;

        -- 모든 케이스 통과 → 성공 메시지 (severity 기본값 note).
        report "tb_alu: PASS";
        wait;   -- 프로세스 영구 정지. 시뮬레이터는 "더 할 일 없음" 으로 종료.
    end process;
end architecture;
