--=============================================================================
-- fixed_point_pkg.vhd — Q1.15 고정소수점 도구 패키지
--=============================================================================
-- 【이 패키지에서 다루는 것】
--   1. Q-format 의 의미와 표현 폭
--   2. real(부동소수) ↔ Q1.15(정수) 변환
--   3. Q1.15 × Q1.15 = Q2.30 곱셈
--   4. Q2.30 → Q1.15 라운딩 + 포화(saturate)
--
-- 【Q-format 이란?】
--   "정수 레지스터인데, 그 값을 2^F 로 나눈 실수로 해석하자" 는 약속.
--   하드웨어는 정수 산술만 하고, 의미만 사람이 정한다.
--
--     Q1.15  : 16-bit signed, 1 sign + 15 frac. 표현 범위 [-1.0, +1.0)
--                 예) 0x4000 = 16384 → 16384 / 2^15 ≈ 0.5
--                     0x8000 = -32768 → -1.0
--     Q2.30  : 32-bit signed, Q1.15 × Q1.15 의 자연스러운 결과 폭.
--                 부호 비트가 사실상 2개(상위 2 bit)인 것처럼 보이지만,
--                 정상 범위 안에서는 둘이 같은 값이므로 정보 손실 없음.
--                 다시 Q1.15 로 돌리려면 shift_right 15 + saturate.
--
-- 【왜 라운딩이 중요한가】
--   Q2.30 → Q1.15 변환은 하위 15-bit 를 버려야 한다. 그냥 truncate 하면
--   결과가 항상 -∞ 방향으로 편향된다 (예: -0.5 ulp 가 -1 ulp 로 내려감).
--   → "0.5 ulp(=2^14) 더한 뒤 truncate" 가 round-half-up 이며 통상의 DSP
--   라이브러리(scipy 등) 와 호환된다.
--
-- 【bit-exact 검증과 라운딩 모드】
--   VHDL `integer(real)` 캐스트는 IEEE round-to-nearest-ties-to-even 이다.
--   numpy.round 의 기본도 banker's rounding(=ties-to-even).
--   양쪽이 일치하므로 to_q15 변환은 비트 정합. testbench 가 LSB 단위로 비교 가능.
--   → 한 LSB 라도 어긋나면 라운딩 모드 mismatch 의심부터 한다.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

package fixed_point_pkg is
    -- 소수부(fraction) 비트 수. Q-format 이름의 두 번째 숫자.
    constant Q15_FRAC_BITS  : natural := 15;
    constant Q230_FRAC_BITS : natural := 30;

    -- subtype: 같은 비트 폭 signed 에 의미 있는 별칭을 붙인다. 합성·시뮬은
    -- 동일하지만 코드 가독성이 크게 좋아진다.
    subtype q15_t  is signed(15 downto 0);   -- Q1.15
    subtype q230_t is signed(31 downto 0);   -- Q2.30 (Q1.15 × Q1.15 곱셈 결과 폭)

    -- ─── 변환 함수 ───────────────────────────────────────────────────────
    -- to_q15: real(부동소수) → Q1.15. 범위 밖은 saturate.
    function to_q15(x : real) return q15_t;

    -- q15_to_real / q230_to_real: 디버그·assert 용. 시뮬레이션에서만 의미 있음
    -- (real 은 합성 불가). 정수 → 실수 변환에 비용은 없다 (시뮬 전용).
    function q15_to_real(x : q15_t)  return real;
    function q230_to_real(x : q230_t) return real;

    -- ─── 산술 ────────────────────────────────────────────────────────────
    -- Q1.15 × Q1.15 = Q2.30. numeric_std 의 signed 곱셈 그대로 wrapping.
    function q15_mul(a, b : q15_t) return q230_t;

    -- Q2.30 → Q1.15. 하위 15-bit 를 round-half-up 으로 라운딩 후 saturate.
    function q230_round_to_q15(x : q230_t) return q15_t;
end package;

package body fixed_point_pkg is

    -- to_q15: real → Q1.15
    --   1) x * 2^15 로 스케일 (소수부를 정수 자리로 끌어올림)
    --   2) integer() 캐스트 → ties-to-even 라운딩
    --   3) Q1.15 표현 범위 [-2^15, 2^15-1] 안으로 saturate
    function to_q15(x : real) return q15_t is
        constant SCALE : real := 2.0 ** Q15_FRAC_BITS;
        variable n     : integer;
    begin
        n := integer(x * SCALE);
        if n >= 2**15 then
            -- 양쪽 끝 saturate. 2^15 은 32768, q15 의 표현 한계는 32767.
            return to_signed(2**15 - 1, 16);
        elsif n < -(2**15) then
            return to_signed(-(2**15), 16);
        else
            return to_signed(n, 16);
        end if;
    end function;

    function q15_to_real(x : q15_t) return real is
    begin
        return real(to_integer(x)) / (2.0 ** Q15_FRAC_BITS);
    end function;

    function q230_to_real(x : q230_t) return real is
    begin
        return real(to_integer(x)) / (2.0 ** Q230_FRAC_BITS);
    end function;

    function q15_mul(a, b : q15_t) return q230_t is
    begin
        -- numeric_std: signed(M) * signed(N) → signed(M+N)
        --   16 + 16 = 32 → q230_t.
        -- 곱셈 자체엔 saturate 가 필요 없다. 두 입력이 [-1, 1) 범위면 결과
        -- 는 (-1, 1] 안이라 절대로 Q2.30 표현 범위를 넘지 않는다.
        return a * b;
    end function;

    -- Q2.30 → Q1.15: 정수 환산 = (x + 2^14) >> 15, 그 후 saturate.
    --   "+ 2^14"  : round-half-up 을 위한 0.5 ulp.
    --   ">> 15"   : 소수부 15 bit 만큼 잘라낸다.
    function q230_round_to_q15(x : q230_t) return q15_t is
        variable rounded : signed(31 downto 0);
        variable shifted : integer;
    begin
        if x >= 0 then
            rounded := x + to_signed(2**14, 32);
        else
            -- 음수일 땐 -0.5 ulp 더해 round-toward-zero halves 가 아닌
            -- round-away-from-zero halves 를 만든다 (대칭성).
            rounded := x - to_signed(2**14, 32);
        end if;
        shifted := to_integer(shift_right(rounded, 15));
        if shifted >= 2**15 then
            return to_signed(2**15 - 1, 16);
        elsif shifted < -(2**15) then
            return to_signed(-(2**15), 16);
        else
            return to_signed(shifted, 16);
        end if;
    end function;

end package body;
