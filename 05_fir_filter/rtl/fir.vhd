--=============================================================================
-- fir.vhd — 8-tap 직접형(direct form) Low-Pass FIR 필터
--=============================================================================
-- 【수식】
--   y[n] = Σ_{k=0}^{N-1} h[k] · x[n-k]    (N=8)
--
-- 【블록 다이어그램】
--   x_in ──┬───── × h[0] ──┐
--          │                │
--   [s0] ─x_dly(0)── × h[1]─┤
--          │                │
--   [s1] ─x_dly(1)── × h[2]─┤
--          │              ...   ──── adder tree ──── round → Q1.15 → y_out
--          │                │                              ↑
--   [s6] ─x_dly(6)── × h[7]─┘                              registered
--
-- 【지연선 (shift register)】
--   x_dly(0) = x[n-1] (직전 샘플), x_dly(6) = x[n-7] (가장 오래된).
--   매 valid 입력마다 `x_dly(0) <= x_in; x_dly(i) <= x_dly(i-1)`.
--
-- 【latency / throughput】
--   - latency  : 1 cycle (조합 누산 → 등록된 출력)
--   - throughput : 1 sample/cycle 연속 입력 가능
--   직접형은 8 multiplier + 8-input adder tree 가 한 cycle 안에 끝나야 하므로
--   fmax 가 낮을 수 있다 (transposed form / pipelined adder tree 가 fmax 측면
--   에서 더 우수). 본 모듈은 학습용이라 가독성 우선.
--
-- 【bit-exact 검증】
--   같은 Q1.15 계수와 same `(acc + 2^14) >> 15` rounding (acc_q30_round_to_q15)
--   을 Python 도 사용 → testbench 의 Q1.15 출력이 한 LSB도 어긋나면 FAIL.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.fixed_point_pkg.all;
    use work.fir_coeffs_pkg.all;

entity fir is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        x_valid  : in  std_logic;
        x_in     : in  q15_t;
        y_valid  : out std_logic;
        y_out    : out q15_t
    );
end entity;

architecture rtl of fir is
    constant N_TAPS : natural := LP8_COEFS'length;

    -- 지연선: x[n-1] .. x[n-7] (N_TAPS-1 = 7 elements)
    type delay_line_t is array (0 to N_TAPS-2) of q15_t;
    signal x_dly : delay_line_t := (others => (others => '0'));

    -- 누산기 폭: Q1.15 × Q1.15 = 32-bit Q2.30. N_TAPS = 8 일 때 합의 |max| ≤
    -- 8 × max|h|·max|x| 인데, |h| ≈ 0.3, |x| ≤ 1 에서 |sum| ≤ 8 × 0.3 = 2.4.
    -- 안전 마진 위해 40-bit (8 guard bits) 사용.
    signal y_r       : q15_t := (others => '0');
    signal y_valid_r : std_logic := '0';
begin
    pipeline : process(clk)
        variable acc : signed(39 downto 0);
    begin
        if rising_edge(clk) then
            -- default: out_valid 1-cycle pulse only
            y_valid_r <= '0';
            if rst = '1' then
                x_dly <= (others => (others => '0'));
                y_r <= (others => '0');
            elsif x_valid = '1' then
                -- 1) 누산: 첫 항 h[0]·x_in + 나머지 h[k]·x_dly(k-1)
                acc := resize(q15_mul(x_in, LP8_COEFS(0)), 40);
                for k in 1 to N_TAPS-1 loop
                    acc := acc + resize(q15_mul(x_dly(k-1), LP8_COEFS(k)), 40);
                end loop;

                -- 2) Q?.30 acc → Q1.15 round-half-up + saturate
                y_r       <= acc_q30_round_to_q15(acc);
                y_valid_r <= '1';

                -- 3) 지연선 shift (가장 새로운 x_in 이 x_dly(0) 으로)
                x_dly(0) <= x_in;
                for i in 1 to N_TAPS-2 loop
                    x_dly(i) <= x_dly(i-1);
                end loop;
            end if;
        end if;
    end process;

    y_out   <= y_r;
    y_valid <= y_valid_r;
end architecture;
