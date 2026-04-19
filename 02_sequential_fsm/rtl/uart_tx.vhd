--=============================================================================
-- uart_tx.vhd — UART 송신기 (8N1 프레임)
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. "유한 상태 기계 (Finite State Machine, FSM)" 의 개념과 VHDL 표현
--   2. enumerated type 으로 상태 선언 (binary/one-hot 인코딩 자동 선택)
--   3. case 문으로 상태별 동작 분기
--   4. 동기 회로에서 "다음 클럭 엣지 값 준비" (pre-drive) 테크닉
--   5. 레지스터 기반 출력과 조합 기반 출력의 차이
--   6. UART 프로토콜의 기본 이해
--
-- ─────────────────────────────────────────────────────────────────────────
-- 【UART 란?】
--   Universal Asynchronous Receiver/Transmitter. 가장 널리 쓰이는 시리얼 통신
--   프로토콜 중 하나. "비동기" 는 송수신 간 공유 클럭이 없다는 뜻 — 대신 미리
--   약속된 BAUD_RATE (초당 전송 비트수) 로 타이밍을 맞춘다.
--
--   8N1 프레임 = 8 데이터 비트, No 패리티, 1 스톱 비트
--   라인(tx_line) 은 평소 '1' 로 유지(idle). 프레임은:
--
--       idle (1)
--         │
--         ▼
--     ┌───────┐  ┌──┬──┬──┬──┬──┬──┬──┬──┐ ┌────────┐
--     │ START │  │D0│D1│D2│D3│D4│D5│D6│D7│ │ STOP   │ → idle (1)
--     │  '0'  │  │  │  │  │  │  │  │  │  │ │  '1'   │
--     └───────┘  └──┴──┴──┴──┴──┴──┴──┴──┘ └────────┘
--        1 bit        8 bit LSB-first        1 bit
--
--   "LSB-first" : UART 표준은 최하위 비트(D0) 부터 전송한다. 사람이 생각하는
--                 2진수 순서(MSB 부터) 와 반대라 실수 포인트.
--
-- 【FSM 이란?】
--   "지금 상태" + "입력" → "다음 상태" + "출력" 을 결정하는 설계 패턴.
--   여기선 IDLE → START → DATA → STOP → IDLE 순환. 각 상태에서 line 값과
--   카운터 관리 방식이 달라진다.
--
-- 【BIT_CLKS 의 의미】
--   한 UART 비트를 얼마나 오래 라인에 유지할지 = 시스템 클럭이 몇 번 도는지.
--   예: 100 MHz clk, 115200 baud → BIT_CLKS = 100_000_000/115_200 ≈ 868
--   → 한 비트마다 868 클럭 동안 라인 값을 붙잡고 있어야 한다.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
-- 정수 카운터만 사용 → numeric_std 불필요.

entity uart_tx is
    generic (
        CLK_FREQ_HZ : positive := 100_000_000;   -- 시스템 클럭 주파수 [Hz]
        BAUD_RATE   : positive := 115_200        -- UART 전송 속도 [bits/sec]
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        tx_data : in  std_logic_vector(7 downto 0);  -- 송신할 한 바이트
        tx_send : in  std_logic;                     -- 1-cycle pulse: "이 바이트 보내라"
        tx_busy : out std_logic;                     -- 송신 중이면 '1'
        tx_line : out std_logic                      -- UART 라인 (idle='1')
    );
end entity;

architecture rtl of uart_tx is
    -- 한 bit 동안 유지할 클럭 수. 정수 나눗셈으로 상수 계산.
    -- 실수 오차가 크면 문제가 되지만 UART 는 2~3% 여유가 있어 정수 근사로 충분.
    constant BIT_CLKS : positive := CLK_FREQ_HZ / BAUD_RATE;

    -- ─── 상태 열거형 ────────────────────────────────────────────────────────
    -- type <이름> is (<값1>, <값2>, ...); 로 사용자 정의 열거형 선언.
    -- 합성 툴이 IDLE/START/DATA/STOP 에 2비트 코드(00/01/10/11) 또는 4비트 one-hot
    -- (0001/0010/0100/1000) 을 자동 할당. 사람은 이름으로 생각하면 된다.
    type state_t is (IDLE, START, DATA, STOP);
    signal state    : state_t := IDLE;

    -- baud_cnt: 현재 bit 안에서 "몇 번째 클럭인가" 를 세는 카운터.
    -- integer range 는 합성 시 최소 비트 폭으로 할당됨.
    signal baud_cnt : integer range 0 to BIT_CLKS-1 := 0;
    signal bit_idx  : integer range 0 to 7 := 0;           -- 현재 전송 중인 데이터 비트
    signal shreg    : std_logic_vector(7 downto 0) := (others => '0'); -- 데이터 래치
    signal line_r   : std_logic := '1';    -- tx_line 출력 레지스터 (idle = '1')
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- 동기 리셋: 모든 상태 초기화, 라인은 idle 로.
                state    <= IDLE;
                baud_cnt <= 0;
                bit_idx  <= 0;
                shreg    <= (others => '0');
                line_r   <= '1';
            else
                case state is
                    ----------------------------------------------------------
                    -- IDLE: 라인 '1' 유지. tx_send 감지 시 송신 시작.
                    ----------------------------------------------------------
                    when IDLE =>
                        line_r   <= '1';   -- 기본: idle 유지
                        baud_cnt <= 0;
                        bit_idx  <= 0;

                        if tx_send = '1' then
                            -- 데이터를 내부 shreg 에 잡아두고 START 상태로 전이.
                            -- 동시에 line_r <= '0' 으로 "다음 클럭 엣지부터 라인이
                            -- 내려가게" 미리 쏟아붓는다 (pre-drive).
                            --
                            -- 왜 pre-drive 인가?
                            --   VHDL signal "<=" 는 "이번 사이클 끝에 반영" 이다.
                            --   따라서 여기서 line_r <= '0' 을 하면 "다음 엣지" 부터
                            --   tx_line='0' 이 보인다. 바로 그 다음 엣지에 state 도
                            --   START 로 전이하므로, START 진입 즉시 start bit 첫
                            --   사이클이 올바르게 '0' 이 되어 있다.
                            shreg  <= tx_data;
                            state  <= START;
                            line_r <= '0';
                        end if;

                    ----------------------------------------------------------
                    -- START: start bit 구간 (BIT_CLKS 동안 라인 '0')
                    ----------------------------------------------------------
                    when START =>
                        line_r <= '0';
                        if baud_cnt = BIT_CLKS-1 then
                            -- BIT_CLKS 만큼 유지 완료 → DATA 로 전이.
                            -- 다음 사이클에 D0 가 라인에 보이도록 shreg(0) 으로 pre-drive.
                            baud_cnt <= 0;
                            state    <= DATA;
                            line_r   <= shreg(0);
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    ----------------------------------------------------------
                    -- DATA: D0 ~ D7 (LSB-first) 를 각 BIT_CLKS 클럭씩 전송
                    --
                    -- 매 사이클 line_r <= shreg(bit_idx) 로 "현재 비트 유지".
                    -- BIT_CLKS-1 에 도달하면 다음 비트로 인덱스 진행하고,
                    -- 라인은 shreg(bit_idx + 1) 로 미리 반영 → 경계 글리치 방지.
                    ----------------------------------------------------------
                    when DATA =>
                        line_r <= shreg(bit_idx);
                        if baud_cnt = BIT_CLKS-1 then
                            baud_cnt <= 0;
                            if bit_idx = 7 then
                                -- 마지막 비트였음 → STOP 로 전이, 라인 '1' pre-drive
                                bit_idx <= 0;
                                state   <= STOP;
                                line_r  <= '1';
                            else
                                bit_idx <= bit_idx + 1;
                                line_r  <= shreg(bit_idx + 1);  -- 다음 비트 미리 반영
                            end if;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    ----------------------------------------------------------
                    -- STOP: stop bit (BIT_CLKS 동안 라인 '1') 이후 IDLE 복귀
                    ----------------------------------------------------------
                    when STOP =>
                        line_r <= '1';
                        if baud_cnt = BIT_CLKS-1 then
                            baud_cnt <= 0;
                            state    <= IDLE;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- 출력 드라이브 (process 밖 concurrent assignment).
    --------------------------------------------------------------------------

    -- tx_line 은 레지스터(line_r) 출력을 그대로 연결 → "레지스터 기반 출력".
    -- 이렇게 하면 글리치 없이 클린한 파형을 보장 (FF 출력은 엣지에서만 바뀜).
    tx_line <= line_r;

    -- tx_busy 는 "IDLE 이 아닐 때" 로부터 조합적으로 파생 → "조합 기반 출력".
    -- state 가 FF 이므로 결과적으로 tx_busy 도 한 엣지 뒤 안정된 값을 갖는다.
    tx_busy <= '0' when state = IDLE else '1';
end architecture;
