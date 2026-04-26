--=============================================================================
-- iir_coeffs_pkg.vhd — 2nd-order Butterworth LP biquad 계수 (Q1.15)
--=============================================================================
-- 【설계 근거】
--   scipy.signal.butter(2, 0.3) 의 Q1.15 양자화. cutoff = 0.3·(fs/2).
--   모든 |coef| < 1 이라 Q1.15 그대로 사용 가능 (max |a1|=24504/32768≈0.748).
--
-- 【scipy 약속】
--   a[0]·y[n] + a[1]·y[n-1] + a[2]·y[n-2] = Σ b[k]·x[n-k] (a[0]=1).
--   따라서 본 패키지는 a[1], a[2] 만 보관 (a[0]=1 은 RTL 에서 사용 안 함).
--   recurrence: y[n] = b0·x[n] + b1·x[n-1] + b2·x[n-2] - a1·y[n-1] - a2·y[n-2].
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.fixed_point_pkg.all;

package iir_coeffs_pkg is
    -- butter(2, 0.3) — Q1.15
    constant BIQUAD_LP_B0 : q15_t := to_signed( 4296, 16);
    constant BIQUAD_LP_B1 : q15_t := to_signed( 8592, 16);
    constant BIQUAD_LP_B2 : q15_t := to_signed( 4296, 16);
    constant BIQUAD_LP_A1 : q15_t := to_signed(-24504, 16);
    constant BIQUAD_LP_A2 : q15_t := to_signed( 8920, 16);
end package;
