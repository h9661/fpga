library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_priority_encoder is
end entity;

architecture sim of tb_priority_encoder is
    signal d     : std_logic_vector(7 downto 0) := (others => '0');
    signal y     : std_logic_vector(2 downto 0);
    signal valid : std_logic;

    -- 기대값: 가장 높은 '1' 비트의 인덱스. 모두 0이면 valid=0.
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
        -- 전 256 조합 순회
        for i in 0 to 255 loop
            d <= std_logic_vector(to_unsigned(i, 8));
            wait for 1 ns;
            expected_of(std_logic_vector(to_unsigned(i, 8)), exp_y, exp_valid);
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
