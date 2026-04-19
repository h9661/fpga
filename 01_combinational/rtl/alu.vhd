--=============================================================================
-- alu.vhd — 4비트 조합 ALU (Arithmetic Logic Unit)
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. "조합 논리(combinational)" vs "순차 논리(sequential)" 의 차이
--   2. std_logic / std_logic_vector / unsigned 타입의 관계와 변환
--   3. entity-architecture 구조 (모듈의 인터페이스와 구현 분리)
--   4. process 문과 sensitivity list
--   5. case-when 구문
--   6. variable 과 signal 의 근본적 차이
--
-- ─────────────────────────────────────────────────────────────────────────
-- 【배경 지식: 조합 논리란?】
--   "조합 논리(combinational)" 는 클럭 없이, 입력이 바뀌면 잠시 후(전파 지연
--   수십 ps~ns) 출력이 입력만의 함수로 결정되는 회로다. 레지스터(기억 소자)
--   가 없으므로 "기억" 하지 않는다. AND/OR 게이트만으로 만드는 진리표 회로가
--   대표적인 예.
--
--   반대로 "순차 논리(sequential)" 는 클럭 엣지마다 상태가 갱신되고 클럭이
--   없으면 값을 유지한다 (플립플롭, 카운터, FIFO 등). 나중에 counter.vhd 에서
--   다룬다.
--
-- 【ALU 란?】
--   CPU 안에서 "계산기" 역할을 하는 조합 블록. op 코드에 따라 입력 a, b 에
--   대한 연산 결과를 y 로 내보낸다. 진짜 CPU 의 ALU 는 32/64비트에 수십 가지
--   연산을 지원하지만, 여기선 학습용으로 4비트 × 7연산만.
--
-- 【op 코드 표】
--   000 ADD : a + b       (덧셈, 4비트 초과 캐리는 버림 → 12+5=17 이지만 결과=1)
--   001 SUB : a - b       (감산, 음수면 2의 보수로 표현)
--   010 AND : a and b     (각 비트별 AND)
--   011 OR  : a or  b     (각 비트별 OR)
--   100 XOR : a xor b     (같으면 0, 다르면 1)
--   101 SHL : a << b[1:0] (왼쪽 논리 시프트, 이동량 = b 의 하위 2비트만)
--   110 SHR : a >> b[1:0] (오른쪽 논리 시프트)
--   others  : 0000        (미정의 코드 → 안전한 기본값)
--=============================================================================

-- ─── library / use 절 ─────────────────────────────────────────────────────
-- VHDL 에서 C 의 #include 에 해당하는 구문.
--   library <lib>;         → 어떤 라이브러리(묶음)를 쓸지 컴파일러에 알림
--   use <lib>.<pkg>.all;   → 그 안의 기호(함수/타입)를 현재 네임스페이스에 공개
--
-- ieee.std_logic_1164: 산업 표준 타입 std_logic/std_logic_vector 정의.
--   std_logic 은 단순한 0/1 만이 아니라 9가지 값을 가진다:
--     '0'/'1'  : 강한 0/1 (정상 논리값)
--     'U'      : 미초기화 (uninitialized) — 시뮬 시작 시 기본값
--     'X'      : 충돌 (두 드라이버가 서로 다른 값 경쟁) — 설계 버그 신호
--     'Z'      : 하이임피던스 (연결 안 됨) — tri-state 버스에서 사용
--     'L'/'H'  : 약한 0/1 (풀다운/풀업 저항 표현)
--     'W'      : 약한 X
--     '-'      : don't care (케이스 최적화 힌트)
--   → 이 9값 체계 덕에 시뮬레이션이 실제 CMOS 동작을 꽤 사실적으로 흉내낸다.
--
-- ieee.numeric_std: "+", "-", 시프트, 정수↔비트벡터 변환 제공.
--   std_logic_vector 자체엔 산술 연산이 정의돼 있지 않다 — 단지 "비트들의 배열"
--   이라 "두 비트 벡터를 더하라" 가 의미적으로 모호하기 때문 (부호 있음/없음?).
--   숫자 의미를 부여하려면 unsigned 나 signed 타입으로 캐스팅해야 한다.
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

-- ─── entity: 모듈의 "외부 인터페이스" 선언 ────────────────────────────────
-- entity 는 C 헤더 파일에 가깝다: "이 모듈은 어떤 핀을 갖고 외부와 어떻게
-- 연결되는지" 만 정의. 실제 동작은 architecture 에서 기술.
--
-- 하드웨어 관점에서 entity = 칩의 "다리(pin) 목록".
entity alu is
    port (
        -- port 선언 문법: <이름> : <방향> <타입>;
        -- 방향(mode):
        --   in     → 이 모듈로 들어오는 신호 (본 모듈 안에선 읽기만 가능)
        --   out    → 이 모듈에서 나가는 신호 (본 모듈 안에선 쓰기만 가능)
        --   inout  → 양방향 (I2C 등 tri-state 버스에서 사용, 드물게)
        --   buffer → 출력이지만 내부에서도 읽을 수 있음 (모던 스타일에선 거의 안 씀)
        a  : in  std_logic_vector(3 downto 0);   -- 입력 A (4비트)
        b  : in  std_logic_vector(3 downto 0);   -- 입력 B (4비트)
        op : in  std_logic_vector(2 downto 0);   -- 연산 코드 (3비트 = 최대 8가지)
        y  : out std_logic_vector(3 downto 0)    -- 결과 (4비트)
    );
    -- 팁: std_logic_vector(3 downto 0) 의 "downto" 는 관습.
    --   downto → 3,2,1,0 순서, MSB..LSB — 일반적 (십진수 읽는 방향과 맞음)
    --   to     → 0,1,2,3 순서, 거의 안 씀, 혼란 방지
end entity;

-- ─── architecture: entity 의 내부 구현 ────────────────────────────────────
-- 하나의 entity 에 여러 architecture 를 두어 "빠른 버전 / 작은 버전" 처럼
-- 바꿔 쓸 수도 있다 (여기선 "rtl" 하나만).
architecture rtl of alu is
    -- ─── constant 선언 ─────────────────────────────────────────────────────
    -- constant = 이름 붙인 불변값. "매직 넘버" 를 없애 가독성 향상.
    -- 문법: constant <이름> : <타입> := <값>;
    -- 주의: signal 은 "<=" 로 대입, variable/constant 는 ":=" 로 대입.
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_SUB : std_logic_vector(2 downto 0) := "001";
    constant OP_AND : std_logic_vector(2 downto 0) := "010";
    constant OP_OR  : std_logic_vector(2 downto 0) := "011";
    constant OP_XOR : std_logic_vector(2 downto 0) := "100";
    constant OP_SHL : std_logic_vector(2 downto 0) := "101";
    constant OP_SHR : std_logic_vector(2 downto 0) := "110";
begin
    --------------------------------------------------------------------------
    -- 【process 문이란?】
    --   여러 개의 signal 대입을 한 블록으로 묶어 기술하는 VHDL 구조.
    --   괄호 안의 "sensitivity list" 에 등록된 신호 중 하나라도 변하면 본문
    --   전체가 재실행된다. 시뮬레이션에선 "이벤트 구동" 방식으로 동작.
    --
    -- 【왜 조합 회로에도 process 를 쓰는가?】
    --   case/if 같은 다중 분기를 읽기 쉽게 쓰려면 process 가 편하다.
    --   단순한 조건부 와이어 한 줄이면 process 밖에서 "when-else" 로도 쓸 수 있다.
    --
    -- 【sensitivity list 의 중요성】
    --   조합 논리는 "입력이 바뀌면 즉시 재계산" 이 원칙 → 입력을 전부 나열해야 한다.
    --   빠뜨리면:
    --     - 시뮬레이션: 빠진 입력이 변해도 본문이 재실행되지 않아 출력이 안 바뀜.
    --     - 합성:       툴은 조합이라고 추론해 회로를 맞게 만듦.
    --     → 시뮬과 실제 하드웨어 동작이 달라지는 찾기 어려운 버그!
    --   VHDL-2008 부터는 "process(all)" 로 자동 나열 가능 (이 프로젝트는 --std=08).
    --
    -- 【조합 process 의 함정: latch 생성】
    --   어떤 분기에서 y 에 대입이 누락되면 합성기는 "이전 값 유지" 로 해석해
    --   latch 라는 작은 기억 소자를 만든다. latch 는 타이밍 검증이 까다롭고
    --   일반적으로 피해야 하므로, 모든 분기에서 반드시 y 를 한 번 이상 대입해야
    --   한다. (이 코드는 when others 로 전부 커버 → 안전.)
    --------------------------------------------------------------------------
    process(a, b, op)
        -- ─── variable 선언 ────────────────────────────────────────────────
        -- variable 은 process/procedure 안에서만 사는 지역 변수. C 의 지역변수와 유사.
        --
        -- signal 과의 핵심 차이:
        --   * 대입:
        --       variable x := ...;   (":=" 즉시 반영, 블로킹)
        --       signal   s <= ...;   ("<=" 는 프로세스 끝/사이클 끝에서 반영, 논블로킹)
        --   * 시야:
        --       variable → 선언된 process 안에서만 보임
        --       signal   → architecture 안 모든 곳에서 보임 (와이어의 VHDL 대응물)
        --   * 하드웨어 매핑:
        --       조합 process 의 variable → "임시 계산 와이어"
        --       signal 은 문맥에 따라 "wire" 또는 "FF(플립플롭)" 로 매핑됨.
        variable au, bu : unsigned(3 downto 0);
    begin
        -- 타입 캐스팅 (std_logic_vector → unsigned):
        -- 두 타입은 비트 패턴이 완전히 동일해 "tag 만 갈아끼우는" 형변환.
        -- 런타임 비용 0. 합성에서 비용도 0 (그냥 같은 와이어).
        au := unsigned(a);
        bu := unsigned(b);

        -- ─── case 문법 ─────────────────────────────────────────────────────
        --   case <expr> is
        --       when <값1> => <문장들>;
        --       when <값2> | <값3> => ...;   -- "|" 로 여러 값 묶기
        --       when others => ...;            -- 나머지 모두
        --   end case;
        -- std_logic_vector 는 9값이 비트마다 있어 조합이 무한대 → when others 필수.
        case op is
            when OP_ADD => y <= std_logic_vector(au + bu);
            -- au + bu: unsigned "+" 는 numeric_std 가 제공. 결과 타입도 unsigned.
            -- y 는 std_logic_vector 이므로 다시 slv 로 캐스팅해 대입해야 타입 일치.

            when OP_SUB => y <= std_logic_vector(au - bu);

            -- 비트 논리 연산은 std_logic_vector 자체에 정의됨 → 캐스팅 불필요.
            when OP_AND => y <= a and b;
            when OP_OR  => y <= a or  b;
            when OP_XOR => y <= a xor b;

            -- ─── 시프트 연산 ────────────────────────────────────────
            -- shift_left(U, n): unsigned U 를 왼쪽으로 n 비트 이동 (오른쪽은 0 채움).
            -- n 은 natural 타입 (0 이상 정수). 그래서 to_integer 로 변환해야 함.
            -- bu(1 downto 0): 하위 2비트만 사용 → 시프트량 0..3 범위로 제한.
            --   (4비트 벡터를 4 이상 시프트하면 결과가 전부 0 이라 의미 없음)
            when OP_SHL => y <= std_logic_vector(shift_left (au, to_integer(bu(1 downto 0))));
            when OP_SHR => y <= std_logic_vector(shift_right(au, to_integer(bu(1 downto 0))));

            -- 정의 안 된 op 코드 → 0. latch 생성 방지 + 안전한 기본값.
            when others => y <= (others => '0');
            -- (others => '0') : aggregate 문법. "나머지 전부 '0' 으로 채우라".
        end case;
    end process;
end architecture;
