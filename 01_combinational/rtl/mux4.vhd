--=============================================================================
-- mux4.vhd — 파라미터라이즈드 4-입력 멀티플렉서
--=============================================================================
-- sel(1:0) 값에 따라 d0..d3 중 하나를 y 로 선택. 순수 조합.
-- WIDTH 는 generic 이라 인스턴스마다 다른 비트 폭의 mux 를 합성할 수 있다.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
-- 이 모듈은 산술 연산이 없어 numeric_std 불필요.

entity mux4 is
    generic (
        WIDTH : positive := 8    -- 각 채널 폭 (기본 8)
    );
    port (
        -- 같은 타입의 여러 port 는 콤마로 묶어 한 줄에 선언 가능.
        d0, d1, d2, d3 : in  std_logic_vector(WIDTH-1 downto 0);
        sel            : in  std_logic_vector(1 downto 0);
        y              : out std_logic_vector(WIDTH-1 downto 0)
    );
end entity;

architecture rtl of mux4 is
begin
    --------------------------------------------------------------------------
    -- selected signal assignment (with-select)
    --   문법:
    --     with <expr> select
    --         target <= value1 when choice1,
    --                   value2 when choice2,
    --                   ...
    --                   valueN when others;   -- 반드시 포함 (std_logic 은 9값이므로)
    --
    --   when others 는 '00'/'01'/'10' 이외의 모든 경우 ('11', 'X', 'Z' 등 포함)에
    --   대응. 여기선 "11 이면 d3" 역할을 겸한다.
    --
    --   with-select 는 하나의 "concurrent assignment" → process 밖에 둘 수 있다.
    --   동일 기능을 process 안 case 문으로도 구현 가능하지만, 단일 와이어 연결엔
    --   이 쪽이 더 간결하다.
    --------------------------------------------------------------------------
    with sel select
        y <= d0 when "00",
             d1 when "01",
             d2 when "10",
             d3 when others;
end architecture;
