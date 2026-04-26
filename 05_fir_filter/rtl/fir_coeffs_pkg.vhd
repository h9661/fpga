--=============================================================================
-- fir_coeffs_pkg.vhd — 8-tap LP FIR 계수 (Q1.15)
--=============================================================================
-- 【설계 근거】
--   scipy.signal.firwin(8, 0.25, window='hamming') 의 출력에 numpy.round 양자화
--   를 적용한 결과. Hamming window + cutoff 0.25(=fs/4) 인 linear-phase low-pass.
--
-- 【대칭성】
--   linear-phase FIR 은 계수가 중앙 대칭. h(0)=h(7), h(1)=h(6), h(2)=h(5),
--   h(3)=h(4). 이 성질을 이용하면 multiplier 수를 절반(8 → 4) 으로 줄일 수
--   있지만 (대칭 FIR 구조), 본 모듈은 학습용 직접형이라 활용하지 않는다.
--
-- 【ROM 추론】
--   `constant ARRAY := (...)` 패턴 + 인덱스 read 만 사용 → 합성 툴이 LUT-ROM
--   또는 BRAM-init 으로 추론. 따라서 hardware 비용은 reg 가 아닌 lookup table.
--
-- 【Python 동기】
--   같은 firwin 호출이 있는 한 값은 결정적. testbench 가 매 실행마다 Python
--   이 dump 한 값과 비교하여 drift 발생 시 즉시 FAIL.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.fixed_point_pkg.all;

package fir_coeffs_pkg is
    -- 가변 길이 계수 배열 — 추후 다른 필터(Week 6 comp FIR 등) 도 같은 타입 재사용.
    type coef_array_t is array (natural range <>) of q15_t;

    -- 8-tap LP, normalized cutoff 0.25, Hamming window.
    -- scipy.signal.firwin(8, 0.25, window='hamming') → numpy.round → Q1.15.
    -- 대칭: 117, 1248, 5277, 9743, 9743, 5277, 1248, 117.
    constant LP8_COEFS : coef_array_t(0 to 7) := (
        to_signed(  117, 16),
        to_signed( 1248, 16),
        to_signed( 5277, 16),
        to_signed( 9743, 16),
        to_signed( 9743, 16),
        to_signed( 5277, 16),
        to_signed( 1248, 16),
        to_signed(  117, 16)
    );
end package;
