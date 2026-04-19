--=============================================================================
-- mux4.vhd — 4-입력 1-출력 멀티플렉서 (MUX, "먹스")
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. "멀티플렉서" 라는 하드웨어 블록이 무엇인지
--   2. generic (파라미터) 을 써서 재사용 가능한 모듈 만들기
--   3. "with-select" (selected signal assignment) 라는 concurrent 구문
--   4. process 를 쓰지 않고도 조합 논리를 쓰는 또 다른 방법
--
-- ─────────────────────────────────────────────────────────────────────────
-- 【MUX 란?】
--   여러 개의 입력 중 "sel" 신호로 하나를 골라 출력으로 내보내는 회로.
--   "디지털 회로판의 스위치" 에 해당. 4:1 MUX 의 동작 표:
--
--     sel | y
--     ----+-----
--     00  | d0
--     01  | d1
--     10  | d2
--     11  | d3
--
--   CPU 내부에서 "레지스터 파일 중 어느 것을 ALU 로 보낼까?" 같은 선택 회로로
--   도처에 등장한다. 게이트 레벨로는 AND/OR 조합으로 구현되지만, FPGA 는
--   LUT(Look-Up Table) 가 기본이라 mux 자체가 1개 LUT 으로 들어가는 경우가 많음.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
-- 산술 연산 없음 → numeric_std 불필요.

entity mux4 is
    -- ─── generic: "컴파일 시 고정되는" 파라미터 ────────────────────────────
    -- generic 은 인스턴스화 시점에 값이 고정된다. 합성된 회로 안엔 변수로 남지
    -- 않고 아예 그 값에 맞는 회로가 만들어진다. C++ 템플릿과 비슷한 개념.
    --
    -- 이 파일의 경우 WIDTH=8 로 인스턴스화하면 "8비트 4:1 MUX",
    -- WIDTH=32 로 인스턴스화하면 "32비트 4:1 MUX" 로 각각 다른 회로가 생긴다.
    generic (
        WIDTH : positive := 8    -- 각 채널의 비트 폭 (기본 8). positive = 1 이상 정수.
    );
    port (
        -- 같은 타입의 port 여러 개는 콤마로 묶어 한 줄에 선언 가능.
        -- d0..d3: 선택 후보 4개.
        d0, d1, d2, d3 : in  std_logic_vector(WIDTH-1 downto 0);
        sel            : in  std_logic_vector(1 downto 0);      -- 2비트 = 4가지 선택
        y              : out std_logic_vector(WIDTH-1 downto 0)
    );
end entity;

architecture rtl of mux4 is
begin
    --------------------------------------------------------------------------
    -- 【selected signal assignment — "with-select"】
    --
    -- 문법:
    --   with <선택 표현식> select
    --       target <= value1 when choice1,
    --                 value2 when choice2,
    --                 ...
    --                 valueN when others;   -- 반드시 마지막에 "others" 필요
    --
    -- 의미: "선택 표현식" 값에 따라 target 에 해당 value 를 연결.
    --       process 문이 아니라 "concurrent assignment" → architecture 의
    --       "begin ... end" 블록 최상위에 위치하며, 매 순간 성립하는 와이어 연결.
    --
    -- 【왜 "when others" 가 필수인가?】
    --   sel 이 std_logic_vector 라서 "00"/"01"/"10"/"11" 이외에도 'X', 'Z' 등이
    --   가능하다. 모든 가능성을 커버해야 하므로 "others" 로 나머지를 몰아넣는다.
    --   여기선 "11" 도 "others" 가 잡아준다 (ASCII 텍스트 순서로 명시 안 해도 OK).
    --
    -- 【process 내 case 와의 차이】
    --   동일한 기능을 process + case 로도 쓸 수 있다. 그러나 단일 target 한 개
    --   에만 대입하는 단순 선택이면 with-select 쪽이 짧고 직관적이다.
    --   여러 신호 동시 갱신이나 내부 variable 이 필요하면 process 가 낫다.
    --
    -- 【하드웨어 매핑】
    --   합성기는 이 구문을 보고 "sel 에 따라 d0/d1/d2/d3 중 하나 선택" 회로를
    --   만든다. FPGA 에서는 LUT 한두 개로 매우 저렴하게 구현된다.
    --------------------------------------------------------------------------
    with sel select
        y <= d0 when "00",
             d1 when "01",
             d2 when "10",
             d3 when others;
end architecture;
