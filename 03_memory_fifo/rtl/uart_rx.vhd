library ieee;
use ieee.std_logic_1164.all;

entity uart_rx is
    generic (
        CLK_FREQ_HZ : positive := 100_000_000;
        BAUD_RATE   : positive := 115_200
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        serial_in : in  std_logic;
        rx_data   : out std_logic_vector(7 downto 0);
        rx_valid  : out std_logic
    );
end entity;

architecture rtl of uart_rx is
    constant BIT_CLKS  : positive := CLK_FREQ_HZ / BAUD_RATE;
    constant HALF_BIT  : positive := BIT_CLKS / 2;
    -- STOP state: sample at midpoint (BIT_CLKS-1), then assert valid at
    -- BIT_CLKS-1+HALF_BIT so that the pulse appears after the stop bit ends.
    constant STOP_FIRE : positive := BIT_CLKS - 1 + HALF_BIT;

    type state_t is (IDLE, START, DATA, STOP);
    signal state    : state_t := IDLE;

    -- cnt must reach STOP_FIRE = BIT_CLKS-1+HALF_BIT
    signal cnt      : integer range 0 to STOP_FIRE := 0;
    signal bit_idx  : integer range 0 to 7 := 0;
    signal buf      : std_logic_vector(7 downto 0) := (others => '0');
    signal data_r   : std_logic_vector(7 downto 0) := (others => '0');
    signal valid_r  : std_logic := '0';
    signal stop_ok  : std_logic := '0';  -- latches stop-bit validity
begin
    process(clk)
    begin
        if rising_edge(clk) then
            valid_r <= '0';  -- default: 1-cycle pulse only
            if rst = '1' then
                state   <= IDLE;
                cnt     <= 0;
                bit_idx <= 0;
                buf     <= (others => '0');
                data_r  <= (others => '0');
                stop_ok <= '0';
            else
                case state is
                    when IDLE =>
                        cnt     <= 0;
                        bit_idx <= 0;
                        stop_ok <= '0';
                        if serial_in = '0' then
                            state <= START;
                        end if;

                    when START =>
                        if cnt = HALF_BIT - 1 then
                            cnt <= 0;
                            if serial_in = '0' then
                                state <= DATA;
                            else
                                state <= IDLE;  -- glitch rejection
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;

                    when DATA =>
                        if cnt = BIT_CLKS - 1 then
                            cnt <= 0;
                            buf(bit_idx) <= serial_in;
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
                            -- midpoint of stop bit: sample and latch validity
                            stop_ok <= serial_in;
                            cnt <= cnt + 1;
                        elsif cnt = STOP_FIRE then
                            -- end of stop bit window: emit valid pulse and return
                            cnt <= 0;
                            if stop_ok = '1' then
                                data_r  <= buf;
                                valid_r <= '1';
                            end if;
                            state <= IDLE;
                        else
                            cnt <= cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    rx_data  <= data_r;
    rx_valid <= valid_r;
end architecture;
