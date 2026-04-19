--=============================================================================
-- tb_priority_encoder.vhd — priority_encoder.vhd 전 256 입력 조합 검증
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
    -- procedure expected_of: 순수 SW 계산으로 기대값을 out 파라미터에 돌려줌.
    --   function 과의 차이:
    --     * procedure 는 여러 out/inout 파라미터로 "여러 값"을 돌려줄 수 있다.
    --     * function 은 단일 반환값, side effect 없음 (wait/신호 대입 불가).
    --   여기선 exp_y/exp_valid 두 값을 동시에 내보내야 해서 procedure 가 자연스럽다.
    --------------------------------------------------------------------------
    procedure expected_of(d_in : in std_logic_vector(7 downto 0);
                          exp_y : out std_logic_vector(2 downto 0);
                          exp_valid : out std_logic) is
    begin
        exp_valid := '0';
        exp_y := (others => '0');
        for i in 7 downto 0 loop
            if d_in(i) = '1' then
                exp_y := std_logic_vector(to_unsigned(i, 3));
                exp_valid := '1';
                exit;
            end if;
        end loop;
    end procedure;
begin
    dut : entity work.priority_encoder
        port map (d => d, y => y, valid => valid);

    stimulus : process
        variable exp_y : std_logic_vector(2 downto 0);
        variable exp_valid : std_logic;
    begin
        -- 0..255 전 조합 순회 (2^8 가지)
        for i in 0 to 255 loop
            d <= std_logic_vector(to_unsigned(i, 8));
            wait for 1 ns;

            -- procedure 호출: out 파라미터로 variable 전달 → 갱신됨.
            expected_of(std_logic_vector(to_unsigned(i, 8)), exp_y, exp_valid);

            -- "std_logic'image(v)": 'IMAGE 는 enum/스칼라 값을 문자열로 바꾸는 속성.
            -- 예: '1' → "'1'", '0' → "'0'", 'X' → "'X'" 처럼 따옴표 포함 문자열.
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
