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
begin
    tx_busy <= '0';
    tx_line <= '1';
end architecture;
