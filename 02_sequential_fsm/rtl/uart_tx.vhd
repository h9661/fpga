--=============================================================================
-- uart_tx.vhd — UART 송신기 (8N1 프레임)
--=============================================================================
-- 프레임 구조 (라인은 idle 일 때 '1' 유지):
--     START | D0 D1 D2 D3 D4 D5 D6 D7 | STOP
--       0        LSB-first 8비트          1
--   각 bit 은 BIT_CLKS 개의 시스템 클럭 동안 유지된다.
--
-- 제어 약속:
--   tx_send = 1 사이클 high → tx_data 를 잡아서 송신 시작.
--   tx_busy = 송신 중 동안 '1'. IDLE 로 돌아오면 '0'.
--
-- 핵심 포인트:
--   IDLE 에서 tx_send 감지 시 즉시 shreg 에 데이터를 실어두고 line_r <= '0' 로
--   start bit 의 첫 사이클을 미리 구동. 다음 클럭에 state = START 로 이어진다.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
-- 정수 카운터만 사용 → numeric_std 불필요.

entity uart_tx is
    generic (
        CLK_FREQ_HZ : positive := 100_000_000;
        BAUD_RATE   : positive := 115_200
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        tx_data : in  std_logic_vector(7 downto 0);  -- 송신할 바이트
        tx_send : in  std_logic;                     -- 1-cycle pulse: 송신 요청
        tx_busy : out std_logic;                     -- 송신 중 '1'
        tx_line : out std_logic                      -- UART TX 라인 (idle=1)
    );
end entity;

architecture rtl of uart_tx is
    -- 한 bit 동안 유지할 클럭 수.
    constant BIT_CLKS : positive := CLK_FREQ_HZ / BAUD_RATE;

    -- 상태 열거형: VHDL 합성 툴이 인코딩을 자동 선택.
    type state_t is (IDLE, START, DATA, STOP);
    signal state    : state_t := IDLE;

    -- baud_cnt 는 0..BIT_CLKS-1 주기 → range 로 비트 폭 최소화.
    signal baud_cnt : integer range 0 to BIT_CLKS-1 := 0;
    signal bit_idx  : integer range 0 to 7 := 0;
    signal shreg    : std_logic_vector(7 downto 0) := (others => '0'); -- 데이터 래치
    signal line_r   : std_logic := '1';    -- 라인 출력 레지스터 (idle='1')
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state    <= IDLE;
                baud_cnt <= 0;
                bit_idx  <= 0;
                shreg    <= (others => '0');
                line_r   <= '1';
            else
                case state is
                    ----------------------------------------------------------
                    -- IDLE: 라인 idle. tx_send 감지 시 시작 전환.
                    ----------------------------------------------------------
                    when IDLE =>
                        line_r   <= '1';   -- 기본: idle 유지
                        baud_cnt <= 0;
                        bit_idx  <= 0;
                        if tx_send = '1' then
                            -- 데이터 샘플 + 상태 전이 + start bit 첫 사이클 pre-drive.
                            -- (이 사이클부터 line_r='0' 로 내려 start bit 시작)
                            shreg  <= tx_data;
                            state  <= START;
                            line_r <= '0';
                        end if;

                    ----------------------------------------------------------
                    -- START: start bit 구간 (BIT_CLKS 클럭 동안 line_r='0')
                    ----------------------------------------------------------
                    when START =>
                        line_r <= '0';
                        if baud_cnt = BIT_CLKS-1 then
                            baud_cnt <= 0;
                            state    <= DATA;
                            line_r   <= shreg(0);   -- 다음 사이클부터 D0 로 전환 준비
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    ----------------------------------------------------------
                    -- DATA: D0..D7 (LSB-first) 를 각 BIT_CLKS 클럭씩 전송
                    --
                    -- 라인 업데이트 타이밍 주의:
                    --   매 사이클 line_r <= shreg(bit_idx) 로 "현재 비트"를 유지.
                    --   BIT_CLKS-1 사이클에서 다음 비트로 진행할 때는 bit_idx+1 을
                    --   미리 읽어 line_r 을 한 클럭 앞서 갱신 → 경계에서 글리치 방지.
                    ----------------------------------------------------------
                    when DATA =>
                        line_r <= shreg(bit_idx);
                        if baud_cnt = BIT_CLKS-1 then
                            baud_cnt <= 0;
                            if bit_idx = 7 then
                                bit_idx <= 0;
                                state   <= STOP;
                                line_r  <= '1';   -- STOP bit 진입 pre-drive
                            else
                                bit_idx <= bit_idx + 1;
                                line_r  <= shreg(bit_idx + 1);   -- 다음 비트 선반영
                            end if;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    ----------------------------------------------------------
                    -- STOP: stop bit (BIT_CLKS 클럭 동안 line_r='1'). 이후 IDLE 복귀.
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

    -- 출력 드라이브.
    tx_line <= line_r;
    -- tx_busy 는 state 로부터 조합적으로 파생 (state=IDLE 아닐 때 '1').
    tx_busy <= '0' when state = IDLE else '1';
end architecture;
