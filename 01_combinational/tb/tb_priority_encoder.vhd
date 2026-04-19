--=============================================================================
-- tb_priority_encoder.vhd — priority_encoder.vhd 전 256 입력 검증
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. procedure 문법 (function 과 비교)
--   2. out 파라미터로 여러 값 돌려받기
--   3. std_logic'image 같은 타입 속성 사용법
--   4. 작은 입력 공간에 대한 "전수 테스트(exhaustive test)"
--
-- 【이 TB 의 전략】
--   8비트 입력 d 의 가능한 256 조합 전부에 대해 DUT 출력 (y, valid) 이
--   reference procedure 계산값과 일치하는지 확인.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_priority_encoder is
end entity;

architecture sim of tb_priority_encoder is
    signal d     : std_logic_vector(7 downto 0) := (others => '0');
    signal y     : std_logic_vector(2 downto 0);
    signal valid : std_logic;

    --------------------------------------------------------------------------
    -- 【procedure 란?】
    --   function 과 비슷하나 "반환값" 이 없다. 대신 out/inout 파라미터로 여러
    --   값을 돌려줄 수 있다. side effect 가 허용되어 signal 대입이나 wait 도
    --   가능 (조건: 그 procedure 를 부르는 context 가 그것을 허용해야 함).
    --
    -- 【function 과의 비교】
    --                 | function        | procedure
    --   반환값        | 단일 return     | 없음 (out 파라미터 사용)
    --   side effect   | 불가 (순수)     | 가능 (wait, signal 대입 등)
    --   호출 문법     | expr 자리에     | 한 줄 statement 로
    --   전형적 쓰임   | 기대값 계산     | 자극 인가, 헬퍼 루틴
    --
    -- 여기선 exp_y 와 exp_valid 두 값을 동시에 내보내야 해서 procedure 가
    -- 자연스럽다. function 이라면 레코드 타입을 만들어 묶어 반환해야 할 것.
    --------------------------------------------------------------------------
    procedure expected_of(d_in : in std_logic_vector(7 downto 0);
                          exp_y : out std_logic_vector(2 downto 0);
                          exp_valid : out std_logic) is
    begin
        -- 기본값 먼저 (못 찾은 경우).
        exp_valid := '0';
        exp_y := (others => '0');

        -- 7→0 순회하며 처음 '1' 을 만나면 저장 후 탈출.
        -- DUT 와 동일한 로직이지만 독립적으로 재작성 → 검증의 의미.
        for i in 7 downto 0 loop
            if d_in(i) = '1' then
                exp_y := std_logic_vector(to_unsigned(i, 3));
                exp_valid := '1';
                exit;
            end if;
        end loop;
    end procedure;
begin
    -- DUT 인스턴스화.
    dut : entity work.priority_encoder
        port map (d => d, y => y, valid => valid);

    stimulus : process
        variable exp_y : std_logic_vector(2 downto 0);
        variable exp_valid : std_logic;
    begin
        -- 0..255 전 조합 순회 (2^8 = 256 가지).
        for i in 0 to 255 loop
            d <= std_logic_vector(to_unsigned(i, 8));
            wait for 1 ns;   -- 조합 회로 전파 대기

            -- procedure 호출: out 파라미터로 variable 을 넘기면 호출 후 갱신됨.
            -- (procedure 안에서 ":=" 로 대입한 값이 바로 복사됨)
            expected_of(std_logic_vector(to_unsigned(i, 8)), exp_y, exp_valid);

            --------------------------------------------------------------
            -- 【 'image 속성 】
            --   VHDL 속성(attribute) 은 "타입/신호에 대한 메타 정보" 를 얻는 기능.
            --   문법: <타입 또는 객체>'<속성이름>[(인자)]
            --
            --   std_logic'image(v): std_logic 값 v 를 문자열로 변환.
            --     예: '1' → "'1'" (따옴표 포함 3자 문자열)
            --         '0' → "'0'"
            --         'X' → "'X'"
            --   integer'image(v): 정수를 십진 문자열로. 예: 42 → "42"
            --
            --   다른 유용한 속성:
            --     <signal>'length  : 벡터 길이
            --     <signal>'range   : 인덱스 범위 (예: "7 downto 0")
            --     <signal>'high/'low : 최대/최소 인덱스
            --------------------------------------------------------------
            assert y = exp_y and valid = exp_valid
                report "priority_encoder fail: d=" & integer'image(i) &
                       " got_y=" & integer'image(to_integer(unsigned(y))) &
                       " got_valid=" & std_logic'image(valid) &
                       " exp_y=" & integer'image(to_integer(unsigned(exp_y))) &
                       " exp_valid=" & std_logic'image(exp_valid)
                severity error;
        end loop;

        report "tb_priority_encoder: PASS";
        wait;
    end process;
end architecture;
