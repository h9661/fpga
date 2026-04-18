library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_alu is
end entity;

architecture sim of tb_alu is
    -- ALU operation codes
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";

    signal a, b  : std_logic_vector(3 downto 0) := (others => '0');
    signal op    : std_logic_vector(2 downto 0) := (others => '0');
    signal y     : std_logic_vector(3 downto 0);

    -- 기대값 계산 함수
    function expected(a_in, b_in : std_logic_vector(3 downto 0);
                      op_in : std_logic_vector(2 downto 0))
        return std_logic_vector is
        variable au, bu : unsigned(3 downto 0);
    begin
        au := unsigned(a_in);
        bu := unsigned(b_in);
        case op_in is
            when OP_ADD => return std_logic_vector(au + bu);
            when others => return "XXXX";
        end case;
    end function;
begin
    dut : entity work.alu
        port map (a => a, b => b, op => op, y => y);

    stimulus : process
    begin
        -- ADD: 전 조합(16 x 16 = 256)을 순회
        op <= OP_ADD;
        for i in 0 to 15 loop
            for j in 0 to 15 loop
                a <= std_logic_vector(to_unsigned(i, 4));
                b <= std_logic_vector(to_unsigned(j, 4));
                wait for 1 ns;
                assert y = expected(a, b, op)
                    report "ADD fail: a=" & integer'image(i) &
                           " b=" & integer'image(j) &
                           " got=" & integer'image(to_integer(unsigned(y))) &
                           " expected=" & integer'image(to_integer(unsigned(expected(a,b,op))))
                    severity error;
            end loop;
        end loop;

        report "tb_alu: PASS";
        wait;
    end process;
end architecture;
