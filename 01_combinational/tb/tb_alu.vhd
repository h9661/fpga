library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_alu is
end entity;

architecture sim of tb_alu is
    -- ALU operation codes
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_SUB : std_logic_vector(2 downto 0) := "001";
    constant OP_AND : std_logic_vector(2 downto 0) := "010";
    constant OP_OR  : std_logic_vector(2 downto 0) := "011";
    constant OP_XOR : std_logic_vector(2 downto 0) := "100";
    constant OP_SHL : std_logic_vector(2 downto 0) := "101";  -- a << b[1:0]
    constant OP_SHR : std_logic_vector(2 downto 0) := "110";  -- a >> b[1:0]

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
            when OP_SUB => return std_logic_vector(au - bu);
            when OP_AND => return a_in and b_in;
            when OP_OR  => return a_in or  b_in;
            when OP_XOR => return a_in xor b_in;
            when OP_SHL => return std_logic_vector(shift_left (au, to_integer(bu(1 downto 0))));
            when OP_SHR => return std_logic_vector(shift_right(au, to_integer(bu(1 downto 0))));
            when others => return "XXXX";
        end case;
    end function;
begin
    dut : entity work.alu
        port map (a => a, b => b, op => op, y => y);

    stimulus : process
    begin
        for op_i in 0 to 6 loop
            op <= std_logic_vector(to_unsigned(op_i, 3));
            for i in 0 to 15 loop
                for j in 0 to 15 loop
                    a <= std_logic_vector(to_unsigned(i, 4));
                    b <= std_logic_vector(to_unsigned(j, 4));
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
        wait;
    end process;
end architecture;
