--=============================================================================
-- tb_mux4.vhd — mux4.vhd 4가지 sel 경로 검증
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. generic 을 지정해 DUT 인스턴스화하기
--   2. 16진수 리터럴 x"A0" 표기법
--   3. 짧은 TB 의 기본 구조 (stimulus 한 개 프로세스로 끝냄)
--
-- 【이 TB 의 전략】
--   4개 채널(d0..d3) 에 구분 가능한 고정값 (0xA0, 0xB1, 0xC2, 0xD3) 을 넣고,
--   sel 을 0→1→2→3 순서로 돌리며 y 가 해당 채널 값과 같은지 확인.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity tb_mux4 is
end entity;

architecture sim of tb_mux4 is
    -- DUT 의 port 에 연결될 신호들.
    signal d0, d1, d2, d3 : std_logic_vector(7 downto 0) := (others => '0');
    signal sel            : std_logic_vector(1 downto 0) := "00";
    signal y              : std_logic_vector(7 downto 0);
begin
    -- ─── DUT 인스턴스화 ───────────────────────────────────────────────────
    -- generic map 으로 WIDTH=8 고정 (기본값과 같지만 명시적으로 지정해 연습).
    -- port map 에서 d0=>d0 처럼 "<형식 파라미터>=>실 신호" 로 매핑.
    dut : entity work.mux4
        generic map (WIDTH => 8)
        port map (d0 => d0, d1 => d1, d2 => d2, d3 => d3, sel => sel, y => y);

    stimulus : process
        -- case 안에서 즉시 계산된 기대값을 보관할 지역 변수.
        variable exp : std_logic_vector(7 downto 0);
    begin
        --------------------------------------------------------------------
        -- 【16진수 / 2진수 / 8진수 리터럴】
        --   x"A0" → 16진수 문자열. 8비트 슬립브이로 해석되면 "10100000".
        --   b"10100000" → 2진수
        --   o"240"      → 8진수
        --
        --   비트 폭은 리터럴이 문맥에 맞게 자동 결정 (x"A0" 은 기본 8비트).
        --   "11111111" 처럼 따옴표만 쓰면 2진 문자열로 해석됨.
        --------------------------------------------------------------------
        d0 <= x"A0";
        d1 <= x"B1";
        d2 <= x"C2";
        d3 <= x"D3";

        -- sel 을 0,1,2,3 순회하며 예상 채널과 비교.
        for s in 0 to 3 loop
            sel <= std_logic_vector(to_unsigned(s, 2));
            wait for 1 ns;   -- 조합 전파를 위한 짧은 대기 (delta 처리)

            -- 기대값 계산: s 값에 따라 어느 채널이 나와야 하는지 결정.
            case s is
                when 0 => exp := x"A0";
                when 1 => exp := x"B1";
                when 2 => exp := x"C2";
                when 3 => exp := x"D3";
                -- integer 범위 0..3 이어도 "when others" 는 VHDL 엄격성 때문에 필수.
                -- 도달할 일 없지만 실수로 왔을 때 'X' 로 표시 (실패 유도).
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
