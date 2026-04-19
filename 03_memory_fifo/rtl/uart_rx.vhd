--=============================================================================
-- uart_rx.vhd — UART 수신기 (8N1 프레임: 8 data, No parity, 1 stop)
--=============================================================================
-- UART 프레임 구조 (라인은 idle일 때 '1'):
--     START | D0 D1 D2 D3 D4 D5 D6 D7 | STOP
--       0       LSB-first 8비트           1
--   각 bit은 BAUD_RATE 에 맞춰 BIT_CLKS 개의 시스템 클럭 동안 유지된다.
--
-- 샘플링 전략 ("bit 중앙에서 샘플"):
--     1) IDLE 에서 '0' 감지 → START 상태로 진입.
--     2) HALF_BIT 후에도 여전히 '0'이면 실제 start bit (글리치 필터).
--     3) 그 뒤부터 BIT_CLKS 주기로 8개 data bit을 정확히 중앙에서 샘플.
--     4) STOP bit 중앙에서 '1'인지 확인 (stop_ok 래치).
--        stop 윈도우 끝(STOP_FIRE)에서 data/valid를 1-cycle pulse로 발출.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
-- 이 파일은 integer 산술과 std_logic만 쓰므로 numeric_std는 불필요.

entity uart_rx is
    generic (
        -- 언더스코어는 큰 숫자 가독성을 위한 구분자 (값에는 영향 없음).
        CLK_FREQ_HZ : positive := 100_000_000;   -- 시스템 클럭 [Hz]
        BAUD_RATE   : positive := 115_200        -- UART 비트 속도 [bps]
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        serial_in : in  std_logic;                       -- UART RX 라인
        rx_data   : out std_logic_vector(7 downto 0);    -- 수신 완료된 바이트
        rx_valid  : out std_logic                        -- 1-cycle pulse: 새 바이트 유효
    );
end entity;

architecture rtl of uart_rx is
    --------------------------------------------------------------------------
    -- constant: 컴파일 타임에 고정되는 값. generic 으로부터 파생 계산 가능.
    --   합성 툴이 정수 나눗셈도 고정값 기반이면 상수 폴딩으로 처리.
    --------------------------------------------------------------------------
    constant BIT_CLKS  : positive := CLK_FREQ_HZ / BAUD_RATE;   -- 한 bit의 클럭 수
    constant HALF_BIT  : positive := BIT_CLKS / 2;               -- bit 중앙 오프셋
    -- STOP 종료 시점: stop bit의 중앙(BIT_CLKS-1)에서 샘플 → HALF_BIT 더 지나
    -- stop window가 끝난 직후 valid pulse를 한 클럭 쏜다.
    constant STOP_FIRE : positive := BIT_CLKS - 1 + HALF_BIT;

    --------------------------------------------------------------------------
    -- 열거형 타입으로 상태를 선언.
    --   문법: type <이름> is (<식별자>, <식별자>, ...);
    --   합성 툴이 bit 인코딩을 자동 선택 (보통 binary 혹은 one-hot).
    --------------------------------------------------------------------------
    type state_t is (IDLE, START, DATA, STOP);
    signal state    : state_t := IDLE;

    -- 카운터/인덱스는 integer range 로 선언해 필요한 비트만 사용하게 한다.
    -- cnt는 STOP 상태에서 STOP_FIRE 까지 가므로 range 상한을 맞춤.
    signal cnt      : integer range 0 to STOP_FIRE := 0;
    signal bit_idx  : integer range 0 to 7 := 0;

    -- buf: 수신 중인 바이트 조립 버퍼. data_r: 외부로 노출할 완료된 바이트.
    signal buf      : std_logic_vector(7 downto 0) := (others => '0');
    signal data_r   : std_logic_vector(7 downto 0) := (others => '0');
    signal valid_r  : std_logic := '0';
    -- stop bit 중앙 샘플 결과 래치 — stop 윈도우가 끝날 때까지 기억해둬야 한다.
    signal stop_ok  : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            --------------------------------------------------------------------
            -- "기본값-후-오버라이드" 관용구:
            --   프로세스 맨 앞에서 valid_r <= '0' 으로 기본값을 깔아둔다.
            --   아래 case 문 특정 가지에서만 '1'로 다시 대입하면 자연스럽게
            --   "1-cycle pulse"가 만들어진다. (같은 프로세스 내 마지막 대입이 승리)
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
                -- case 문법:
                --   case <expr> is
                --     when <value> => <statements>;
                --     when others  => <statements>;  -- 나머지 모두
                --   end case;
                -- 열거형이면서 모든 값을 열거했다면 "when others"는 생략 가능.
                case state is
                    when IDLE =>
                        -- 유휴: 라인은 '1' 유지. '0'이 보이면 START bit 후보.
                        cnt     <= 0;
                        bit_idx <= 0;
                        stop_ok <= '0';
                        if serial_in = '0' then
                            state <= START;
                        end if;

                    when START =>
                        -- start bit 중앙까지 기다려 재확인 (글리치 거부).
                        if cnt = HALF_BIT - 1 then
                            cnt <= 0;
                            if serial_in = '0' then
                                state <= DATA;      -- 진짜 start bit 확정
                            else
                                state <= IDLE;      -- 노이즈였음, 원복
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    when DATA =>
                        -- START 에서 HALF_BIT 오프셋을 한 번 먹고 들어왔기 때문에,
                        -- 이 상태에서는 BIT_CLKS 주기마다 샘플 포인트가 곧 bit 중앙이 된다.
                        if cnt = BIT_CLKS - 1 then
                            cnt <= 0;
                            buf(bit_idx) <= serial_in;  -- LSB-first 누적
                            if bit_idx = 7 then
                                bit_idx <= 0;
                                state   <= STOP;
                            else
                                bit_idx <= bit_idx + 1;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    when STOP =>
                        if cnt = BIT_CLKS - 1 then
                            -- stop bit 중앙: '1'이면 정상 프레임 (기록만 하고 계속 카운트)
                            stop_ok <= serial_in;
                            cnt <= cnt + 1;
                        elsif cnt = STOP_FIRE then
                            -- stop 윈도우 종료: 이 순간에만 data/valid 방출.
                            cnt <= 0;
                            if stop_ok = '1' then
                                data_r  <= buf;
                                valid_r <= '1';     -- 위 기본값 '0'을 한 사이클만 덮어씀
                            end if;
                            state <= IDLE;
                        else
                            cnt <= cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- 내부 레지스터를 그대로 외부 포트로 연결 (concurrent wire 드라이브).
    rx_data  <= data_r;
    rx_valid <= valid_r;
end architecture;
