library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_mux4 is
end entity;

architecture sim of tb_mux4 is
    signal d0, d1, d2, d3 : std_logic_vector(7 downto 0) := (others => '0');
    signal sel            : std_logic_vector(1 downto 0) := "00";
    signal y              : std_logic_vector(7 downto 0);
begin
    dut : entity work.mux4
        generic map (WIDTH => 8)
        port map (d0 => d0, d1 => d1, d2 => d2, d3 => d3, sel => sel, y => y);

    stimulus : process
        variable exp : std_logic_vector(7 downto 0);
    begin
        -- 고정 값으로 4개 채널 구분
        d0 <= x"A0";
        d1 <= x"B1";
        d2 <= x"C2";
        d3 <= x"D3";

        for s in 0 to 3 loop
            sel <= std_logic_vector(to_unsigned(s, 2));
            wait for 1 ns;
            case s is
                when 0 => exp := x"A0";
                when 1 => exp := x"B1";
                when 2 => exp := x"C2";
                when 3 => exp := x"D3";
                when others => exp := (others => 'X');
            end case;
            assert y = exp
                report "mux4 fail: sel=" & integer'image(s) &
                       " got=" & integer'image(to_integer(unsigned(y)))
                severity error;
        end loop;

        report "tb_mux4: PASS";
        wait;
    end process;
end architecture;
