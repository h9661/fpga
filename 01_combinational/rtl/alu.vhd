--=============================================================================
-- alu.vhd — 4비트 조합 ALU (7가지 연산)
--=============================================================================
-- op(2:0) 코드로 a, b 두 입력에 대한 연산을 선택해 y 에 내보낸다.
-- 완전 조합(combinational) 회로 → 레지스터 없음, clk 도 없음.
-- 입력이 바뀌면 결과가 전파 지연 이후에 즉시 갱신된다.
--
-- 지원 연산:
--   000 ADD : a + b                    (덧셈, 캐리 버림)
--   001 SUB : a - b                    (감산, 보로우 버림)
--   010 AND : a and b                  (비트별 AND)
--   011 OR  : a or  b                  (비트별 OR)
--   100 XOR : a xor b                  (비트별 XOR)
--   101 SHL : a << b[1:0]              (좌측 논리 시프트, 시프트량은 b의 하위 2비트)
--   110 SHR : a >> b[1:0]              (우측 논리 시프트)
--   others  : 0000                     (미정의 코드에 대한 안전한 기본값)
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;   -- std_logic / std_logic_vector / and/or/xor 등
    use ieee.numeric_std.all;       -- unsigned, "+", "-", shift_left/right, to_integer

entity alu is
    port (
        a  : in  std_logic_vector(3 downto 0);
        b  : in  std_logic_vector(3 downto 0);
        op : in  std_logic_vector(2 downto 0);
        y  : out std_logic_vector(3 downto 0)
    );
end entity;

architecture rtl of alu is
    -- constant: 이름 붙은 비트 패턴. 가독성과 오타 방지를 위해 도입.
    -- ":=" 로 한 번 초기화, 이후 변경 불가 (const).
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_SUB : std_logic_vector(2 downto 0) := "001";
    constant OP_AND : std_logic_vector(2 downto 0) := "010";
    constant OP_OR  : std_logic_vector(2 downto 0) := "011";
    constant OP_XOR : std_logic_vector(2 downto 0) := "100";
    constant OP_SHL : std_logic_vector(2 downto 0) := "101";
    constant OP_SHR : std_logic_vector(2 downto 0) := "110";
begin
    --------------------------------------------------------------------------
    -- 조합 프로세스
    --   sensitivity list 에 "영향을 주는 모든 입력" (a, b, op)을 나열 → 이 중 하나라도
    --   바뀌면 프로세스가 다시 실행된다. 하나라도 빠뜨리면 시뮬-합성 불일치(latch/버그)
    --   가 생길 수 있음. VHDL-2008 에선 "process(all)" 로 자동화 가능.
    --
    --   process 내부에서 "y <= ..." 여러 번 대입해도 마지막 대입만 살아남는다
    --   (signal semantics). 또한 clk 가 없고 clock edge 가 없으므로 합성 결과는
    --   플립플롭 없는 순수 조합 논리가 된다.
    --------------------------------------------------------------------------
    process(a, b, op)
        -- variable: 프로세스 지역. ":=" 로 즉시 반영(블로킹 대입).
        -- signal 과 달리 delta 사이클 지연이 없어 같은 프로세스 안에서 "일시 계산"에 유용.
        variable au, bu : unsigned(3 downto 0);
    begin
        -- std_logic_vector → unsigned 형변환 (비트 패턴 그대로 해석만 바꿈)
        au := unsigned(a);
        bu := unsigned(b);

        case op is
            -- case when: 좌변(op) 이 각 when 값과 일치할 때 해당 문장 실행.
            -- 열거형이 아닌 경우 반드시 others 가 필요 — std_logic_vector 는 'X','Z' 등
            -- 메타 값을 포함해 9가지 값/비트 조합이 가능하므로 전부 커버 불가.
            when OP_ADD => y <= std_logic_vector(au + bu);
            when OP_SUB => y <= std_logic_vector(au - bu);

            -- 비트별 논리 연산은 std_logic_vector 에도 바로 정의되어 있어 캐스팅 불필요.
            when OP_AND => y <= a and b;
            when OP_OR  => y <= a or  b;
            when OP_XOR => y <= a xor b;

            -- shift_left/right 는 numeric_std 가 제공. 시프트 양은 natural 인자.
            -- bu(1 downto 0) 만 사용 → 0..3 범위로 제한 (4비트 폭 대비 합리적).
            when OP_SHL => y <= std_logic_vector(shift_left (au, to_integer(bu(1 downto 0))));
            when OP_SHR => y <= std_logic_vector(shift_right(au, to_integer(bu(1 downto 0))));

            -- 정의되지 않은 op 코드 → 안전한 기본값 (latch 생성 방지 목적도 겸함).
            when others => y <= (others => '0');
        end case;
    end process;
end architecture;
