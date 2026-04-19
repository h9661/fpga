--=============================================================================
-- uart_rx.vhd — UART 수신기 (8N1 프레임: 8 data, No parity, 1 stop)
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. "비동기(async)" 시리얼 통신을 어떻게 클럭 영역에서 복원하는가
--   2. 오버샘플링(oversampling) 없이 "비트 중앙 샘플링" 만으로 안정적으로 받기
--   3. FSM 에서 IDLE→START→DATA→STOP 순서로 상태 전이 구성
--   4. "기본값 덮어쓰기" 관용구로 1-cycle pulse 출력 만들기
--   5. case-when 과 상태별 타이머 재사용
--
-- ─────────────────────────────────────────────────────────────────────────
-- 【UART 수신의 어려움】
--   송신측과 수신측은 물리적으로 서로 다른 클럭을 쓴다 (비동기). 그래서
--   수신 측은 다음 두 가지를 해결해야 한다:
--     (a) 프레임 시작점 탐지 — 언제 start bit 가 왔는가?
--     (b) 비트 "한가운데" 에서 샘플 — 엣지 근처에서 샘플하면 글리치/지터에
--         취약. 중앙에서 샘플하는 게 가장 안전하다.
--
-- 【이 구현의 전략: "중앙 샘플링"】
--   1) IDLE 에서 serial_in 이 '0' 으로 내려가는 순간을 감지 → START bit 후보
--   2) HALF_BIT(= BIT_CLKS/2) 만큼 기다렸다가 다시 '0' 인지 재확인 (글리치 필터)
--   3) 이후 BIT_CLKS 주기로 정확히 bit 중앙에서 D0..D7 을 샘플 (LSB-first)
--   4) STOP bit 중앙에서 '1' 인지 확인 → 프레임 정상 여부를 stop_ok 에 래치
--   5) stop bit 윈도우가 끝나는 시점(STOP_FIRE)에 rx_valid 1-cycle pulse 발출
--
-- 【타이밍 요약】
--
--     serial_in:  1111 | 0000000000 | DDDDDDDDDDDDDDD... | 1111111111 | 1111
--                       ↑            ↑                   ↑            ↑
--                       START 감지   여기서부터 D0 중앙    STOP 중앙     여기서 rx_valid pulse
--
--     내부 시간축 (state/cnt):
--       IDLE → START (cnt 0..HALF_BIT-1) → DATA (cnt 0..BIT_CLKS-1, 8회)
--            → STOP (cnt 0..STOP_FIRE) → IDLE
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
-- 정수 산술과 slv 비트 접근만 쓴다 → numeric_std 불필요.

entity uart_rx is
    generic (
        -- 언더스코어는 가독성용 숫자 구분자 (값엔 영향 없음). VHDL-2008 이상 지원.
        CLK_FREQ_HZ : positive := 100_000_000;   -- 시스템 클럭 [Hz]
        BAUD_RATE   : positive := 115_200        -- UART 비트 속도 [bps]
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        serial_in : in  std_logic;                        -- UART RX 라인
        rx_data   : out std_logic_vector(7 downto 0);     -- 수신 완료된 바이트
        rx_valid  : out std_logic                         -- 1-cycle pulse: 새 바이트 유효
    );
end entity;

architecture rtl of uart_rx is
    --------------------------------------------------------------------------
    -- 【파생 상수 (컴파일 타임 계산)】
    --   generic 은 컴파일 시 고정값이므로, 그로부터 유도한 상수도 컴파일 시 확정.
    --   "BIT_CLKS = CLK_FREQ_HZ / BAUD_RATE" 같은 정수 나눗셈도 상수 폴딩 처리.
    --------------------------------------------------------------------------
    constant BIT_CLKS  : positive := CLK_FREQ_HZ / BAUD_RATE;   -- 한 bit = 몇 clk?
    constant HALF_BIT  : positive := BIT_CLKS / 2;               -- bit 중앙 오프셋

    -- STOP 종료 시점의 의미:
    --   stop bit 중앙 = cnt = BIT_CLKS-1 일 때 샘플 (여기서 stop_ok 래치)
    --   stop bit 끝   = 중앙에서 + HALF_BIT 만큼 더 진행 = BIT_CLKS-1 + HALF_BIT
    --   이 시점에 valid pulse 를 쏘면 "다음 프레임 시작 전에" 깨끗하게 완료된다.
    constant STOP_FIRE : positive := BIT_CLKS - 1 + HALF_BIT;

    --------------------------------------------------------------------------
    -- 【enumerated 타입으로 FSM 상태 선언】
    -- 문법: type <이름> is (<값1>, <값2>, ...);
    -- 합성 툴이 bit 인코딩(binary, one-hot 등) 을 자동 선택.
    --------------------------------------------------------------------------
    type state_t is (IDLE, START, DATA, STOP);
    signal state    : state_t := IDLE;

    -- cnt: 현재 bit 안에서 몇 번째 클럭인지 (또는 STOP 에선 windowing 용).
    -- STOP 에서 STOP_FIRE 까지 가므로 range 상한을 맞춰 최소 비트 폭으로.
    signal cnt      : integer range 0 to STOP_FIRE := 0;
    signal bit_idx  : integer range 0 to 7 := 0;   -- 수신 중인 데이터 비트 인덱스

    -- buf: 수신 중인 바이트 조립 버퍼 (LSB-first 로 채움)
    -- data_r: 외부로 노출할 "완료된" 바이트
    signal buf      : std_logic_vector(7 downto 0) := (others => '0');
    signal data_r   : std_logic_vector(7 downto 0) := (others => '0');
    signal valid_r  : std_logic := '0';

    -- stop_ok: stop bit 중앙에서 샘플한 값을 임시 보관 (프레임 정상인지 플래그).
    --          stop 윈도우 끝에서 한번에 valid/data 를 발출하기 위해 필요.
    signal stop_ok  : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            --------------------------------------------------------------------
            -- 【"기본값 + 조건부 오버라이드" 관용구】
            --   프로세스 맨 앞에 valid_r <= '0' 을 두어 "매 클럭 기본 '0'" 으로 깔음.
            --   아래 특정 분기에서만 valid_r <= '1' 로 덮어쓰면, 같은 프로세스의
            --   마지막 대입이 승리 → 자연스럽게 "1-cycle pulse" 가 만들어진다.
            --
            --   이 관용구를 모르면 "valid_r 을 어떻게 다음 클럭에 자동으로 0 으로
            --   되돌리지?" 하고 고민하게 된다. signal 대입 순서의 특성을 이용한
            --   전형적 FPGA 코딩 테크닉.
            --------------------------------------------------------------------
            valid_r <= '0';

            if rst = '1' then
                state   <= IDLE;
                cnt     <= 0;
                bit_idx <= 0;
                buf     <= (others => '0');
                data_r  <= (others => '0');
                stop_ok <= '0';
            else
                case state is
                    ----------------------------------------------------------
                    -- IDLE: 라인은 '1' 이어야 정상. '0' 감지 → START 후보
                    ----------------------------------------------------------
                    when IDLE =>
                        cnt     <= 0;
                        bit_idx <= 0;
                        stop_ok <= '0';
                        if serial_in = '0' then
                            state <= START;
                        end if;

                    ----------------------------------------------------------
                    -- START: HALF_BIT 만큼 센 뒤 재확인 (글리치 필터)
                    --   진짜 start bit 라면 중앙에서도 여전히 '0' 이어야 함.
                    --   이 지점부터 DATA 상태로 넘어가면 cnt 는 0 에서 다시 시작 →
                    --   이후 BIT_CLKS 주기가 곧 D0..D7 의 중앙 타이밍이 된다.
                    ----------------------------------------------------------
                    when START =>
                        if cnt = HALF_BIT - 1 then
                            cnt <= 0;
                            if serial_in = '0' then
                                state <= DATA;            -- 진짜 start bit
                            else
                                state <= IDLE;            -- 노이즈 → 원복
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    ----------------------------------------------------------
                    -- DATA: 매 BIT_CLKS 주기 끝에 비트 중앙 샘플 (LSB-first)
                    --   START 에서 HALF_BIT 오프셋을 먼저 소화했기 때문에, 여기서
                    --   BIT_CLKS-1 시점이 곧 data bit 중앙이다.
                    ----------------------------------------------------------
                    when DATA =>
                        if cnt = BIT_CLKS - 1 then
                            cnt <= 0;
                            buf(bit_idx) <= serial_in;    -- 비트 위치에 샘플 저장
                            if bit_idx = 7 then
                                bit_idx <= 0;
                                state   <= STOP;
                            else
                                bit_idx <= bit_idx + 1;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    ----------------------------------------------------------
                    -- STOP: stop bit 중앙에서 '1' 인지 확인 후 윈도우 끝에서 emit
                    ----------------------------------------------------------
                    when STOP =>
                        if cnt = BIT_CLKS - 1 then
                            -- stop bit 중앙: 결과 래치 (이번엔 state 전이 안 함)
                            stop_ok <= serial_in;
                            cnt <= cnt + 1;
                        elsif cnt = STOP_FIRE then
                            -- stop bit 윈도우 끝: 결과 발출.
                            cnt <= 0;
                            if stop_ok = '1' then
                                data_r  <= buf;
                                valid_r <= '1';   -- 기본값 '0' 을 이 사이클만 덮어쓰기
                            end if;
                            state <= IDLE;
                        else
                            cnt <= cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- 내부 레지스터를 그대로 외부 포트에 연결 (조합 연결, 비용 0).
    rx_data  <= data_r;
    rx_valid <= valid_r;
end architecture;
