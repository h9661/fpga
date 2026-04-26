--=============================================================================
-- cic_decim.vhd — CIC (Cascaded Integrator-Comb) 데시메이터
--                 R=8 (decimation), M=1 (differential delay), N=3 (stages)
--=============================================================================
-- 【CIC 란?】
--   곱셈기 없이 가산·감산만으로 만드는 매우 효율적인 데시메이터(샘플링율 ↓).
--   구조: 입력단의 N 개 적분기(integrator, fs 에서 동작) → ÷R 다운샘플 →
--         N 개 미분기(comb, fs/R 에서 동작).
--   전달함수 (이상적):
--     H(z) = ((1 - z^-RM)^N) / ((1 - z^-1)^N)   (DC gain = (R·M)^N)
--   본 모듈은 R=8, M=1, N=3 → DC gain = 512 = 2^9.
--
-- 【왜 modular(wrap-around) 산술이 동작하는가】
--   적분기는 무한히 적분하므로 이론상 무한 폭이 필요. 하지만 차분기(comb) 가
--   같은 적분 결과 두 시점의 차이만 사용하므로, 두 시점의 적분 값이 같은 비트
--   폭으로 wrap 한다면 차이는 정확히 복원된다 (modular 산술의 핵심 트릭).
--
-- 【비트 폭 결정】
--   안전 폭 = B_in + N·log2(R·M) = 16 + 3·log2(8) = 16 + 9 = 25 bit.
--   본 RTL 은 단순화·여유 위해 32-bit signed 로 통일.
--
-- 【출력 라운딩】
--   y_raw 의 DC gain 은 512. unit-gain Q1.15 출력으로 환산하려면 ÷512 필요.
--   round-half-up: y_q15 = saturate((y_raw + 256) >> 9, q15 range).
--
-- 【intra-cycle 의미】
--   일반적인 CIC RTL 은 "한 클럭에 입력 한 개, integrator 3단을 sequential
--   하게 통과" 시킨다. VHDL non-blocking 신호 대입만 쓰면 매 단마다 1 cycle
--   지연이 추가돼 의미가 달라지므로, integrator 체인을 process 내부 variable
--   로 sequential 하게 갱신 후 한 번에 register 에 commit. Python 골든도 같은
--   순서로 갱신해 비트 정합 가능.
--
-- 【인터페이스】
--   x_valid='1' 인 cycle 의 x_in 이 한 입력 sample. 매 R-th 입력 후의 cycle 에
--   y_valid='1' 1-cycle pulse, 그때 y_out 가 유효.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.fixed_point_pkg.all;

entity cic_decim is
    generic (
        R : positive := 8;
        N : positive := 3
        -- M=1 hardcoded — comb stage 는 z^-1 단일 지연 가정.
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        x_valid : in  std_logic;
        x_in    : in  q15_t;
        y_valid : out std_logic;
        y_out   : out q15_t
    );
end entity;

architecture rtl of cic_decim is
    constant W      : positive := 32;       -- 내부 폭
    constant SHIFT  : natural  := 9;        -- log2(R^N) = log2(8^3) = 9
    constant ROUND_BIAS : signed(W downto 0) := to_signed(2**(SHIFT-1), W+1);

    -- integrator 상태
    signal i1, i2, i3 : signed(W-1 downto 0) := (others => '0');

    -- comb 단의 prev 레지스터 (decimation 이후 fs/R 클럭에서 갱신)
    signal d_prev_1 : signed(W-1 downto 0) := (others => '0');
    signal d_prev_2 : signed(W-1 downto 0) := (others => '0');
    signal d_prev_3 : signed(W-1 downto 0) := (others => '0');

    signal cnt : integer range 0 to R-1 := 0;

    signal y_r       : q15_t := (others => '0');
    signal y_valid_r : std_logic := '0';
begin
    -- N=3 한정 RTL — generic 으로 다른 값을 넣으면 elaboration 시 즉시 fail.
    assert N = 3
        report "cic_decim: this RTL only implements N=3"
        severity failure;

    pipeline : process(clk)
        variable i1_v, i2_v, i3_v       : signed(W-1 downto 0);
        variable d1_out, d2_out, d3_out : signed(W-1 downto 0);
        variable y_ext, y_rnd           : signed(W downto 0);
        variable y_int                  : integer;
    begin
        if rising_edge(clk) then
            y_valid_r <= '0';
            if rst = '1' then
                i1 <= (others => '0');
                i2 <= (others => '0');
                i3 <= (others => '0');
                d_prev_1 <= (others => '0');
                d_prev_2 <= (others => '0');
                d_prev_3 <= (others => '0');
                cnt <= 0;
                y_r <= (others => '0');
            elsif x_valid = '1' then
                -- ─── 3 integrator (process 내 sequential, variable) ──────
                -- numeric_std signed 가산은 wrap-around 가 기본이라 32-bit
                -- modular 동작이 자연스럽다.
                i1_v := i1 + resize(x_in, W);
                i2_v := i2 + i1_v;
                i3_v := i3 + i2_v;
                i1 <= i1_v;
                i2 <= i2_v;
                i3 <= i3_v;

                if cnt = R-1 then
                    cnt <= 0;

                    -- ─── 3 differentiator (cascade) ──────────────────────
                    -- stage k 입력: 이전 stage 의 출력 (혹은 stage1 의 경우 i3_v)
                    -- prev 레지스터 (decimation 직전 시점의 stage_k 입력 보존)
                    d1_out := i3_v   - d_prev_1;
                    d2_out := d1_out - d_prev_2;
                    d3_out := d2_out - d_prev_3;

                    -- prev 갱신: 이번 결과를 다음 decimation 시점까지 보관
                    d_prev_1 <= i3_v;
                    d_prev_2 <= d1_out;
                    d_prev_3 <= d2_out;

                    -- ─── 출력 라운딩: y_raw / 2^9 → Q1.15 (round-half-up + saturate) ─
                    y_ext := resize(d3_out, W+1);
                    y_rnd := y_ext + ROUND_BIAS;
                    y_int := to_integer(resize(shift_right(y_rnd, SHIFT), 32));
                    if y_int >= 2**15 then
                        y_r <= to_signed(2**15 - 1, 16);
                    elsif y_int < -(2**15) then
                        y_r <= to_signed(-(2**15), 16);
                    else
                        y_r <= to_signed(y_int, 16);
                    end if;
                    y_valid_r <= '1';
                else
                    cnt <= cnt + 1;
                end if;
            end if;
        end if;
    end process;

    y_out   <= y_r;
    y_valid <= y_valid_r;
end architecture;
