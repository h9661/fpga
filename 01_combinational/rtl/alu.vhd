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
begin
    process(a, b, op)
        variable au, bu : unsigned(3 downto 0);
    begin
        au := unsigned(a);
        bu := unsigned(b);
        case op is
            when OP_ADD => y <= std_logic_vector(au + bu);
            when others => y <= (others => '0');
        end case;
    end process;
end architecture;
