library ieee;
use ieee.std_logic_1164.all;
entity uart_tx is
    generic (
        CLK_FREQ_HZ : positive := 100_000_000;
        BAUD_RATE   : positive := 115_200
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        tx_data : in  std_logic_vector(7 downto 0);
        tx_send : in  std_logic;
        tx_busy : out std_logic;
        tx_line : out std_logic
    );
end entity;

architecture rtl of uart_tx is
    constant BIT_CLKS : positive := CLK_FREQ_HZ / BAUD_RATE;

    type state_t is (IDLE, START, DATA, STOP);
    signal state    : state_t := IDLE;

    signal baud_cnt : integer range 0 to BIT_CLKS-1 := 0;
    signal bit_idx  : integer range 0 to 7 := 0;
    signal shreg    : std_logic_vector(7 downto 0) := (others => '0');
    signal line_r   : std_logic := '1';
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
                    when IDLE =>
                        line_r   <= '1';
                        baud_cnt <= 0;
                        bit_idx  <= 0;
                        if tx_send = '1' then
                            shreg  <= tx_data;
                            state  <= START;
                            line_r <= '0';  -- start bit pre-drive: covers first cycle of start bit
                        end if;

                    when START =>
                        line_r <= '0';
                        if baud_cnt = BIT_CLKS-1 then
                            baud_cnt <= 0;
                            state    <= DATA;
                            line_r   <= shreg(0);
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

                    when DATA =>
                        line_r <= shreg(bit_idx);
                        if baud_cnt = BIT_CLKS-1 then
                            baud_cnt <= 0;
                            if bit_idx = 7 then
                                bit_idx <= 0;
                                state   <= STOP;
                                line_r  <= '1';
                            else
                                bit_idx <= bit_idx + 1;
                                line_r  <= shreg(bit_idx + 1);
                            end if;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;

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

    tx_line <= line_r;
    tx_busy <= '0' when state = IDLE else '1';
end architecture;
