library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo is
    generic (
        WIDTH                  : positive := 8;
        DEPTH                  : positive := 16;
        ALMOST_FULL_THRESHOLD  : positive := 15;
        ALMOST_EMPTY_THRESHOLD : positive := 1
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        wr_en        : in  std_logic;
        din          : in  std_logic_vector(WIDTH-1 downto 0);
        rd_en        : in  std_logic;
        dout         : out std_logic_vector(WIDTH-1 downto 0);
        full         : out std_logic;
        empty        : out std_logic;
        almost_full  : out std_logic;
        almost_empty : out std_logic;
        count        : out std_logic_vector(31 downto 0)
    );
end entity;

architecture rtl of fifo is
    type ram_t is array (0 to DEPTH-1) of std_logic_vector(WIDTH-1 downto 0);
    signal ram : ram_t := (others => (others => '0'));

    signal wr_ptr : integer range 0 to DEPTH-1 := 0;
    signal rd_ptr : integer range 0 to DEPTH-1 := 0;
    signal cnt    : integer range 0 to DEPTH   := 0;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                wr_ptr <= 0;
                rd_ptr <= 0;
                cnt    <= 0;
            else
                -- write (block if full)
                if wr_en = '1' and cnt /= DEPTH then
                    ram(wr_ptr) <= din;
                    if wr_ptr = DEPTH-1 then
                        wr_ptr <= 0;
                    else
                        wr_ptr <= wr_ptr + 1;
                    end if;
                end if;

                -- read (block if empty)
                if rd_en = '1' and cnt /= 0 then
                    if rd_ptr = DEPTH-1 then
                        rd_ptr <= 0;
                    else
                        rd_ptr <= rd_ptr + 1;
                    end if;
                end if;

                -- count: concurrent wr+rd → no change; one-sided → ±1
                if    wr_en = '1' and cnt /= DEPTH and rd_en = '1' and cnt /= 0 then
                    cnt <= cnt;
                elsif wr_en = '1' and cnt /= DEPTH then
                    cnt <= cnt + 1;
                elsif rd_en = '1' and cnt /= 0 then
                    cnt <= cnt - 1;
                end if;
            end if;
        end if;
    end process;

    -- combinational read: dout는 항상 head를 즉시 출력 (FWFT)
    dout <= ram(rd_ptr);

    full         <= '1' when cnt = DEPTH else '0';
    empty        <= '1' when cnt = 0 else '0';
    almost_full  <= '1' when cnt >= ALMOST_FULL_THRESHOLD  else '0';
    almost_empty <= '1' when cnt <= ALMOST_EMPTY_THRESHOLD else '0';
    count        <= std_logic_vector(to_unsigned(cnt, 32));
end architecture;
