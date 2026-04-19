--=============================================================================
-- counter.vhd — 파라미터라이즈드 포화(saturating) 상향 카운터
--=============================================================================
-- 동작:
--   * rst=1 (동기) → q=0
--   * en =1 이고 q < MAX → q <- q + 1
--   * q = MAX (전 비트 '1') → saturated='1', 더 이상 증가하지 않음 (wrap 금지)
--
-- 포화 카운터는 오버플로로 인한 wrap-around 를 방지해야 할 때 유용하다
-- (예: 이벤트 카운트 상한, WDT 의 경계 검출 등).
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;     -- unsigned "+", 비교

entity counter is
    generic (
        WIDTH : positive := 4     -- 카운터 비트 폭 (기본 4 → 최대값 15)
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;   -- 동기 리셋
        en        : in  std_logic;   -- 인에이블
        q         : out std_logic_vector(WIDTH-1 downto 0);
        saturated : out std_logic    -- q 가 최대값일 때 '1'
    );
end entity;

architecture rtl of counter is
    -- MAX_VAL = "111...1" (unsigned 로 해석하면 2^WIDTH - 1).
    -- (others => '1') aggregate 는 모든 비트를 '1' 로 채우라는 뜻.
    constant MAX_VAL : unsigned(WIDTH-1 downto 0) := (others => '1');

    -- 내부 카운트는 unsigned 로 보관해 "+" 연산을 바로 쓸 수 있게 한다.
    signal cnt : unsigned(WIDTH-1 downto 0) := (others => '0');
begin
    --------------------------------------------------------------------------
    -- 동기 프로세스: clk 의 rising edge 에서만 상태가 변한다.
    --------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt <= (others => '0');                -- 동기 리셋
            elsif en = '1' and cnt /= MAX_VAL then
                -- en 이 걸려있고 아직 포화 전 → 1 증가.
                -- unsigned 타입이라 "+1" 이 그대로 사용 가능.
                cnt <= cnt + 1;
            end if;
            -- else 없음 → cnt 불변 (signal 의 기본 동작: 대입 없으면 유지)
        end if;
    end process;

    -- 외부로는 slv 로 노출 (typed wire 연결).
    q <= std_logic_vector(cnt);

    -- 조건부 concurrent assignment: "when ... else"
    -- cnt = MAX_VAL 을 조합으로 감지해 saturated 를 즉시 반영.
    saturated <= '1' when cnt = MAX_VAL else '0';
end architecture;
