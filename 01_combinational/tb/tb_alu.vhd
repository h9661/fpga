--=============================================================================
-- tb_alu.vhd — alu.vhd 전수 검증 (모든 op × 모든 a × 모든 b)
--=============================================================================
-- 3중 for 루프로 op=0..6, a=0..15, b=0..15 전 조합(1,792개) 에 대해
-- DUT 출력과 reference 함수의 기대값을 비교한다.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_alu is
end entity;

architecture sim of tb_alu is
    -- DUT 내부 상수와 동일한 정의를 TB 에도 둔다 (패키지로 공유해도 좋지만 여기선 간단히).
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_SUB : std_logic_vector(2 downto 0) := "001";
    constant OP_AND : std_logic_vector(2 downto 0) := "010";
    constant OP_OR  : std_logic_vector(2 downto 0) := "011";
    constant OP_XOR : std_logic_vector(2 downto 0) := "100";
    constant OP_SHL : std_logic_vector(2 downto 0) := "101";
    constant OP_SHR : std_logic_vector(2 downto 0) := "110";

    -- 자극 신호: 초기값은 (others => '0') 로 모두 0.
    signal a, b  : std_logic_vector(3 downto 0) := (others => '0');
    signal op    : std_logic_vector(2 downto 0) := (others => '0');
    signal y     : std_logic_vector(3 downto 0);

    --------------------------------------------------------------------------
    -- reference 함수: 주어진 (a, b, op) 에 대해 기대 결과를 계산해 반환.
    --   function 문법:
    --     function <이름>(<파라미터 목록>) return <타입> is
    --         <선언부>
    --     begin
    --         return <값>;
    --     end function;
    --   * function 은 side effect 없고 (wait 불가, signal 대입 불가), 값만 반환.
    --   * 파라미터는 기본적으로 constant (in) 모드. signal 을 받으려면 "signal" 키워드 명시.
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
            -- 검증에 쓰이지 않는 others 는 "XXXX" 로 두어 실수로 맞지 않게 한다.
            when others => return "XXXX";
        end case;
    end function;
begin
    -- DUT 인스턴스화. port map 에서 동명 연결은 "x => x" 로 명시.
    dut : entity work.alu
        port map (a => a, b => b, op => op, y => y);

    --------------------------------------------------------------------------
    -- 자극 프로세스: 3중 for 루프로 전수 조사.
    --------------------------------------------------------------------------
    stimulus : process
    begin
        for op_i in 0 to 6 loop
            -- 정수 → 3비트 슬립브이 캐스팅: to_unsigned(정수, 폭) → std_logic_vector(...).
            op <= std_logic_vector(to_unsigned(op_i, 3));
            for i in 0 to 15 loop
                for j in 0 to 15 loop
                    a <= std_logic_vector(to_unsigned(i, 4));
                    b <= std_logic_vector(to_unsigned(j, 4));

                    -- signal 전파를 위해 잠깐 대기 (조합 회로지만 시뮬은 delta 사이클 필요).
                    -- "wait for 1 ns" 는 signal 값이 안정된 뒤에 y 를 읽기 위한 관용구.
                    wait for 1 ns;

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

        report "tb_alu: PASS";
        wait;   -- 프로세스 영구 정지 (clk 없는 TB 라 sim_done 불필요)
    end process;
end architecture;
