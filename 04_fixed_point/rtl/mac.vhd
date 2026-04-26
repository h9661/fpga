--=============================================================================
-- mac.vhd — 3-스테이지 파이프라인 Multiply-Accumulate
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. 파이프라이닝 — latency 와 throughput 의 분리
--   2. 공용 패키지(`fixed_point_pkg`) 의 use
--   3. 동기 clear 와 (선택적) async/sync reset 의 차이
--   4. 누산기 폭 결정 — 곱셈 후 폭 + guard bits
--
-- 【파이프라인 구조】
--                in_valid
--                a_in, b_in
--                   │
--                   ▼  ┌──────────────────────┐
--             stage 1  │  a_s1, b_s1, v_s1     │  (입력 레지스터)
--                   │  └──────────────────────┘
--                   ▼  ┌──────────────────────┐
--             stage 2  │ p_s2 = a_s1 × b_s1, v│  (곱셈 결과 레지스터, Q2.30)
--                   │  └──────────────────────┘
--                   ▼  ┌──────────────────────┐
--             stage 3  │ acc ← acc + p_s2     │  (누산 레지스터, 40-bit)
--                      └──────────────────────┘
--                          │
--                          ▼ acc_out (always present), out_valid (1-cycle pulse)
--
-- 【latency vs throughput】
--   - latency      : 한 입력이 결과에 반영되기까지 걸리는 cycle 수 = 3
--   - throughput   : 매 cycle 마다 새 입력 1개 처리 가능 = 1 sample / cycle
--   파이프라이닝의 가치는 throughput 을 유지하면서 critical path (조합 길이)
--   를 짧게 잘라 fmax(클럭 속도) 를 끌어올리는 데 있다.
--
-- 【누산 폭 40-bit 의 근거】
--   Q1.15 × Q1.15 = Q2.30 (32-bit signed). 매번 |값| < 1 로 가정해도 N 회 누적
--   시 |sum| ≤ N. 8 bit guard 면 2^8 = 256 회까지 안전. FIR 8-tap 등 작은
--   필터엔 충분. 더 길어지면 ACC_WIDTH generic 으로 빼는 것이 정석.
--
-- 【clr 의미】
--   clr 가 '1' 인 클럭 엣지에서 acc <= 0. 파이프라인 상의 in-flight 곱
--   (stage 1, stage 2 의 데이터) 은 이후 cycle 에 자연스럽게 누산기로
--   흘러들어가므로, 의도와 무관한 잔상이 남고 싶지 않다면 clr 직전에 in_valid
--   를 N(파이프라인 깊이) cycle 동안 0으로 두어 비우는 게 안전하다.
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.fixed_point_pkg.all;

entity mac is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;       -- 동기 reset (전체 파이프라인 zero)
        clr       : in  std_logic;       -- 동기 누산 clear (acc → 0, 파이프 데이터는 유지)
        in_valid  : in  std_logic;
        a_in      : in  q15_t;
        b_in      : in  q15_t;
        acc_out   : out signed(39 downto 0);
        out_valid : out std_logic        -- 입력 후 3 cycle 지점에 1-cycle pulse
    );
end entity;

architecture rtl of mac is
    -- Stage 1: 입력 레지스터
    signal a_s1, b_s1 : q15_t     := (others => '0');
    signal v_s1       : std_logic := '0';

    -- Stage 2: 곱셈 결과 레지스터 (Q2.30)
    signal p_s2       : q230_t    := (others => '0');
    signal v_s2       : std_logic := '0';

    -- Stage 3: 누산 레지스터 (40-bit signed, 약 8 guard bits 확보)
    signal acc_r      : signed(39 downto 0) := (others => '0');
    signal v_s3       : std_logic           := '0';
begin
    -- 단일 process 로 세 stage 모두 기술. 합성 툴은 각 비반응 신호를 plain D-FF
    -- 로 추론한다. process 내부 순서는 시뮬레이션 의미에 영향 없음 (signal
    -- 대입은 동시) 이지만 코드 가독성은 stage 흐름 순서로 두는 것이 좋다.
    pipeline : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                a_s1  <= (others => '0');
                b_s1  <= (others => '0');
                v_s1  <= '0';
                p_s2  <= (others => '0');
                v_s2  <= '0';
                acc_r <= (others => '0');
                v_s3  <= '0';
            else
                -- ─── Stage 1: 입력 latch ─────────────────────────────────
                a_s1 <= a_in;
                b_s1 <= b_in;
                v_s1 <= in_valid;

                -- ─── Stage 2: 곱셈 (조합) → 결과만 register ───────────────
                -- q15_mul 은 패키지에서 정의된 헬퍼. 본질은 a_s1 * b_s1.
                p_s2 <= q15_mul(a_s1, b_s1);
                v_s2 <= v_s1;

                -- ─── Stage 3: 누산 + 동기 clear ────────────────────────────
                if clr = '1' then
                    acc_r <= (others => '0');
                elsif v_s2 = '1' then
                    -- resize: 32-bit Q2.30 → 40-bit signed (sign-extend).
                    -- 더하기 자체는 numeric_std signed wrap-add 로, guard bit
                    -- 폭 안에서 overflow 없이 쌓인다.
                    acc_r <= acc_r + resize(p_s2, 40);
                end if;
                v_s3 <= v_s2;
            end if;
        end if;
    end process;

    acc_out   <= acc_r;
    out_valid <= v_s3;
end architecture;
