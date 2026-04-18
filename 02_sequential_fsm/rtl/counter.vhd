library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
    generic (
        WIDTH : positive := 4
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        en        : in  std_logic;
        q         : out std_logic_vector(WIDTH-1 downto 0);
        saturated : out std_logic
    );
end entity;

architecture rtl of counter is
    constant MAX_VAL : unsigned(WIDTH-1 downto 0) := (others => '1');
    signal cnt : unsigned(WIDTH-1 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt <= (others => '0');
            elsif en = '1' and cnt /= MAX_VAL then
                cnt <= cnt + 1;
            end if;
        end if;
    end process;

    q <= std_logic_vector(cnt);
    saturated <= '1' when cnt = MAX_VAL else '0';
end architecture;
