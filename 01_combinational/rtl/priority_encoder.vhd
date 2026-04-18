library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity priority_encoder is
    port (
        d     : in  std_logic_vector(7 downto 0);
        y     : out std_logic_vector(2 downto 0);
        valid : out std_logic
    );
end entity;

architecture rtl of priority_encoder is
begin
    process(d)
        variable y_v     : std_logic_vector(2 downto 0);
        variable valid_v : std_logic;
    begin
        y_v     := (others => '0');
        valid_v := '0';
        for i in 7 downto 0 loop
            if d(i) = '1' then
                y_v     := std_logic_vector(to_unsigned(i, 3));
                valid_v := '1';
                exit;
            end if;
        end loop;
        y     <= y_v;
        valid <= valid_v;
    end process;
end architecture;
