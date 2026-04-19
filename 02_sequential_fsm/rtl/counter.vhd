--=============================================================================
-- counter.vhd — 파라미터라이즈드 포화(saturating) 상향 카운터
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. "순차 논리(sequential)" 란? 플립플롭(FF) 과 클럭의 역할
--   2. "rising_edge(clk)" 관용구로 동기 회로 기술하기
--   3. 동기 리셋(synchronous reset) 패턴
--   4. signal 의 "대입 없으면 유지" 라는 기본 동작 (→ 기억 회로 유도)
--   5. unsigned 타입을 써서 "+1" 을 직접 사용하기
--   6. when-else 조건부 concurrent assignment
--
-- ─────────────────────────────────────────────────────────────────────────
-- 【플립플롭(FF)과 클럭】
--   FF(Flip-Flop) 은 "1비트를 기억하는 회로" 로, 클럭 엣지(보통 상승 엣지) 가
--   오는 순간에 입력값을 샘플해 저장한다. 그 다음 엣지까지는 값이 그대로 유지됨.
--
--   "클럭(clock)" 은 일정한 주기로 0/1 을 토글하는 신호. 현대 디지털 칩의
--   거의 모든 상태 변화는 "클럭 엣지" 라는 이산적인 순간에만 일어난다. 이것이
--   동기식 설계(synchronous design) 의 핵심.
--
-- 【rising_edge(clk)】
--   VHDL 표준 함수. "clk 가 방금 '0'→'1' 로 바뀌었는가?" 를 반환.
--   "if rising_edge(clk) then ... end if;" 블록 안의 signal 대입은 합성기가
--   "이 signal 을 FF 로 만들고 clk 상승 엣지에 샘플" 로 해석한다.
--
-- 【왜 signal 이 "기억" 하게 되는가?】
--   process 안에서 어떤 signal 에 대입하지 않는 경로가 있으면 그 경로에선
--   "이전 값을 유지" 가 된다. if rising_edge(clk) 블록 안에 있으면 "엣지에서만
--   갱신, 그 외엔 유지" → 이것이 곧 FF 의 동작. VHDL 이 굳이 "이건 FF" 라고
--   쓰지 않아도, 합성기가 문맥상 자동 추론해준다.
--
-- 【포화 카운터의 의미】
--   일반 카운터는 최대값(2^WIDTH - 1) 이후 0 으로 wrap-around. 포화 카운터는
--   최대값에서 멈춘다. 오버플로 wrap 을 막아야 하는 곳(이벤트 카운트 상한,
--   워치독 타이머 등) 에서 유용.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;     -- unsigned, "+", 비교 연산자

entity counter is
    generic (
        WIDTH : positive := 4     -- 카운터 비트 폭 (기본 4 → 최대값 15)
    );
    port (
        clk       : in  std_logic;   -- 시스템 클럭 (이 입력의 상승엣지에 상태 갱신)
        rst       : in  std_logic;   -- 동기 리셋 ('1' 이면 다음 엣지에서 0 으로 초기화)
        en        : in  std_logic;   -- 인에이블 ('1' 일 때만 카운트 증가)
        q         : out std_logic_vector(WIDTH-1 downto 0);  -- 현재 카운트 값
        saturated : out std_logic    -- q = 최대값일 때 '1'
    );
end entity;

architecture rtl of counter is
    -- (others => '1') : "모든 비트 '1'" → unsigned 로 해석하면 2^WIDTH - 1.
    -- 예: WIDTH=4 면 MAX_VAL = "1111" = 15.
    constant MAX_VAL : unsigned(WIDTH-1 downto 0) := (others => '1');

    -- 내부 카운트는 unsigned 로 보관 → "+1" 이 바로 가능.
    -- signal 이므로 합성기가 context(아래 process 에서 clk 엣지에만 갱신) 를 보고
    -- 이것을 "WIDTH 개의 FF" 로 만든다.
    signal cnt : unsigned(WIDTH-1 downto 0) := (others => '0');
begin
    --------------------------------------------------------------------------
    -- 동기 프로세스: clk 의 상승 엣지에서만 상태가 변한다.
    --
    -- 【동기 vs 비동기 리셋】
    --   동기(synchronous)     : rst 판정은 clk 엣지에서만. 이 코드가 바로 이 패턴.
    --                           타이밍 분석이 단순하고 대부분의 ASIC/FPGA 권장.
    --   비동기(asynchronous) : rst 가 '1' 이 되는 순간 즉시 반영. process 문이
    --                           sensitivity list 에 rst 도 포함하는 형태.
    --                           예시 (여기선 안 씀):
    --                             process(clk, rst) is
    --                             begin
    --                                 if rst = '1' then cnt <= 0;
    --                                 elsif rising_edge(clk) then ...
    --                             end process;
    --
    --   학습 단계에선 동기 리셋만 일관되게 쓰자. 덜 헷갈리고 버그도 적다.
    --------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt <= (others => '0');             -- 동기 리셋: cnt 를 0 으로
            elsif en = '1' and cnt /= MAX_VAL then
                -- en 이 켜져 있고 아직 포화 전이면 1 증가.
                -- unsigned + 정수는 numeric_std 가 정의 → 캐스팅 없이 가능.
                -- "/=" 는 "같지 않다" (C 의 != 에 해당).
                cnt <= cnt + 1;
            end if;
            -- else 절이 없음 → cnt 에 아무 대입도 일어나지 않으면 이전 값 유지.
            --                 이게 곧 FF 의 "엣지 외엔 값 유지" 동작과 일치.
        end if;
    end process;

    --------------------------------------------------------------------------
    -- 외부로 내보내는 신호 — process 밖의 concurrent assignment 두 줄.
    --------------------------------------------------------------------------

    -- unsigned → std_logic_vector 변환 (비트 패턴 그대로, tag 만 변경).
    q <= std_logic_vector(cnt);

    -- 【when-else 조건부 concurrent assignment】
    --   target <= <값A> when <조건> else <값B>;
    --   <조건> 이 참이면 A, 아니면 B.
    --
    --   여기선 "cnt 가 MAX_VAL 이면 '1', 아니면 '0'" 을 항상 조합적으로 반영.
    --   포화 상태는 cnt 만 보면 알 수 있어 FF 는 불필요 → 조합 논리로 충분.
    --
    --   process 안에서 대입했다면 합성기가 "이 saturated 도 FF 로 만들까?"
    --   고민할 수 있었다. 명확히 조합으로 빼두면 의도가 분명해진다.
    saturated <= '1' when cnt = MAX_VAL else '0';
end architecture;
