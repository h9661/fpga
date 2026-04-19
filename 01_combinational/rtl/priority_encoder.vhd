--=============================================================================
-- priority_encoder.vhd — 8→3 우선순위 인코더
--=============================================================================
-- d(7:0) 에서 '1' 인 비트 중 가장 높은 인덱스를 y(2:0) 로 출력.
-- 하나라도 '1' 이 있으면 valid='1', 전부 '0' 이면 valid='0' (y는 "000").
--
-- 구현 방식:
--   for 루프를 7→0 으로 내려가며 처음 '1' 을 만나면 결과를 저장하고 exit.
--   시뮬레이션 관점에선 순차적 탐색이지만, 합성기는 이를 우선순위 인코더 회로
--   (캐스케이드된 OR/MUX 트리) 로 변환한다.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;    -- to_unsigned 변환용

entity priority_encoder is
    port (
        d     : in  std_logic_vector(7 downto 0);
        y     : out std_logic_vector(2 downto 0);  -- 최상위 '1' 비트의 인덱스
        valid : out std_logic                      -- 하나라도 '1' 이 있으면 1
    );
end entity;

architecture rtl of priority_encoder is
begin
    --------------------------------------------------------------------------
    -- 조합 프로세스. sensitivity list 에 d 만 포함 (다른 입력 없음).
    --------------------------------------------------------------------------
    process(d)
        -- 지역 variable: 즉시 갱신(:=)되므로 루프 내부에서 "발견 후 저장"에 적합.
        -- signal 을 썼다면 delta 사이클 때문에 같은 프로세스 내에선 이전 값이 보일 것.
        variable y_v     : std_logic_vector(2 downto 0);
        variable valid_v : std_logic;
    begin
        -- 기본값: 아무것도 못 찾았을 때의 출력.
        y_v     := (others => '0');
        valid_v := '0';

        -- "for <var> in <범위> loop":
        --   <var> 는 루프 지역 상수 (안에서 대입 불가).
        --   7 downto 0 → 7,6,5,...,0 순서로 순회.
        for i in 7 downto 0 loop
            if d(i) = '1' then
                -- to_unsigned(i, 3): 정수 i 를 3비트 unsigned 로. 이후 slv 로 캐스팅.
                y_v     := std_logic_vector(to_unsigned(i, 3));
                valid_v := '1';
                exit;          -- 가장 높은 '1' 을 찾았으니 바로 탈출
            end if;
        end loop;

        -- 프로세스 끝에서 한 번만 signal 로 반영.
        -- (variable 은 process 밖에서 보이지 않음 → 외부 포트엔 signal 로 전달해야 함)
        y     <= y_v;
        valid <= valid_v;
    end process;
end architecture;
