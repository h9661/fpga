library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu is
    port (
        a  : in  std_logic_vector(3 downto 0);
        b  : in  std_logic_vector(3 downto 0);
        op : in  std_logic_vector(2 downto 0);
        y  : out std_logic_vector(3 downto 0)
    );
end entity;

architecture rtl of alu is
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_SUB : std_logic_vector(2 downto 0) := "001";
    constant OP_AND : std_logic_vector(2 downto 0) := "010";
    constant OP_OR  : std_logic_vector(2 downto 0) := "011";
    constant OP_XOR : std_logic_vector(2 downto 0) := "100";
    constant OP_SHL : std_logic_vector(2 downto 0) := "101";
    constant OP_SHR : std_logic_vector(2 downto 0) := "110";
begin
    process(a, b, op)
        variable au, bu : unsigned(3 downto 0);
    begin
        au := unsigned(a);
        bu := unsigned(b);
        case op is
            when OP_ADD => y <= std_logic_vector(au + bu);
            when OP_SUB => y <= std_logic_vector(au - bu);
            when OP_AND => y <= a and b;
            when OP_OR  => y <= a or  b;
            when OP_XOR => y <= a xor b;
            when OP_SHL => y <= std_logic_vector(shift_left (au, to_integer(bu(1 downto 0))));
            when OP_SHR => y <= std_logic_vector(shift_right(au, to_integer(bu(1 downto 0))));
            when others => y <= (others => '0');
        end case;
    end process;
end architecture;
