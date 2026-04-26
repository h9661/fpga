--=============================================================================
-- iir_biquad.vhd — 2nd-order IIR Biquad (Direct Form II Transposed)
--=============================================================================
-- 【DF2T 구조】
--   v       = b0·x + s1                       — 출력 전 누산
--   y       = round(v) → Q1.15
--   s1_next = b1·x + s2 - a1·y                — 다음 cycle 의 s1
--   s2_next = b2·x      - a2·y
--
-- 【왜 DF2T 인가】
--   - 직접형 II (DF2) 와 비교해 "내부 노드의 dynamic range" 가 줄어든다.
--   - 합성-friendly: 모든 곱셈이 입력 x 또는 출력 y 에만 의존 → 곱셈기 입력
--     지연 (multiplier 입력 레지스터) 추가가 자연스럽다.
--   - 안정 + linear-phase 가 아닌 IIR 에선 사실상 표준.
--
-- 【비트 폭】
--   - x, y, coef : Q1.15 (16-bit signed)
--   - product    : Q2.30 (32-bit signed) = q15_mul(coef, x_or_y)
--   - state s1, s2 : 40-bit signed (Q10.30) — 8 guard bits 확보로 modular
--                    wrap 안에서 stable filter 의 변동 절대 안 넘어감.
--   - 내부 sum 들 : 결합 회로에서 Q?.30 으로 만들고, 40-bit signed 에 저장.
--
-- 【bit-exact 검증】
--   Python 측이 동일 식 + 40-bit modular wrap. 한 LSB 라도 어긋나면 FAIL.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.fixed_point_pkg.all;
    use work.iir_coeffs_pkg.all;

entity iir_biquad is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        x_valid : in  std_logic;
        x_in    : in  q15_t;
        y_valid : out std_logic;
        y_out   : out q15_t
    );
end entity;

architecture rtl of iir_biquad is
    -- 상태 레지스터 — 40-bit Q10.30
    signal s1 : signed(39 downto 0) := (others => '0');
    signal s2 : signed(39 downto 0) := (others => '0');

    signal y_r       : q15_t := (others => '0');
    signal y_valid_r : std_logic := '0';
begin
    process(clk)
        variable v       : signed(39 downto 0);
        variable s1_next : signed(39 downto 0);
        variable s2_next : signed(39 downto 0);
        variable y_v     : q15_t;
    begin
        if rising_edge(clk) then
            y_valid_r <= '0';
            if rst = '1' then
                s1 <= (others => '0');
                s2 <= (others => '0');
                y_r <= (others => '0');
            elsif x_valid = '1' then
                -- v = b0·x + s1 (Q?.30)
                v := s1 + resize(q15_mul(BIQUAD_LP_B0, x_in), 40);

                -- 출력 라운딩
                y_v := acc_q30_round_to_q15(v);
                y_r       <= y_v;
                y_valid_r <= '1';

                -- 상태 업데이트
                --   s1_next = b1·x + s2 - a1·y
                --   s2_next = b2·x      - a2·y
                s1_next := s2
                         + resize(q15_mul(BIQUAD_LP_B1, x_in), 40)
                         - resize(q15_mul(BIQUAD_LP_A1, y_v),  40);
                s2_next := resize(q15_mul(BIQUAD_LP_B2, x_in), 40)
                         - resize(q15_mul(BIQUAD_LP_A2, y_v),  40);

                s1 <= s1_next;
                s2 <= s2_next;
            end if;
        end if;
    end process;

    y_out   <= y_r;
    y_valid <= y_valid_r;
end architecture;
