--=============================================================================
-- tb_mux4.vhd — mux4.vhd 4가지 sel 값에 대한 경로 확인
--=============================================================================

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
    -- generic map 으로 WIDTH 를 8 로 고정해 DUT 인스턴스화.
    dut : entity work.mux4
        generic map (WIDTH => 8)
        port map (d0 => d0, d1 => d1, d2 => d2, d3 => d3, sel => sel, y => y);

    stimulus : process
        -- 지역 variable: case 안에서 즉시 계산된 기대값을 보관.
        variable exp : std_logic_vector(7 downto 0);
    begin
        --------------------------------------------------------------------
        -- 고정된 4가지 값으로 채널을 구분한다.
        --   x"A0" : 16진수 문자열 리터럴 (std_logic_vector 로 해석됨, 8비트 → "10100000")
        --   기타 표기: b"10100000" (바이너리), o"240" (8진수) 도 가능.
        --------------------------------------------------------------------
        d0 <= x"A0";
        d1 <= x"B1";
        d2 <= x"C2";
        d3 <= x"D3";

        -- sel 을 0,1,2,3 순회하며 예상 채널과 비교.
        for s in 0 to 3 loop
            sel <= std_logic_vector(to_unsigned(s, 2));
            wait for 1 ns;   -- 조합 전파 대기

            case s is
                when 0 => exp := x"A0";
                when 1 => exp := x"B1";
                when 2 => exp := x"C2";
                when 3 => exp := x"D3";
                -- integer 범위가 0..3 이어도 when others 가 필요 (VHDL 엄격성).
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
