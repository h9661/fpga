--=============================================================================
-- fifo.vhd — 파라미터라이즈드 동기 FIFO (First-Word Fall-Through)
--=============================================================================
-- 【이 파일에서 배우는 것】
--   1. "FIFO(First-In-First-Out)" 메모리 블록의 개념과 용도
--   2. VHDL 로 "배열 타입" 선언하고 메모리처럼 다루기
--   3. "원형 버퍼(circular buffer)" 구현 — 쓰기/읽기 포인터 wrap-around
--   4. FWFT(First-Word Fall-Through) 모드의 의미
--   5. 오버플로/언더플로 보호 로직
--   6. count 를 이용한 상태 플래그 (full / empty / almost_full / almost_empty)
--   7. concurrent when-else 로 조합 출력 만들기
--
-- ─────────────────────────────────────────────────────────────────────────
-- 【FIFO 란?】
--   "먼저 넣은 데이터가 먼저 나오는" 큐 자료구조의 하드웨어 버전.
--   대표적 용도:
--     * 생산자(producer) 와 소비자(consumer) 의 속도 차이 완화 (버퍼링)
--     * 클럭 도메인 크로싱 (비동기 FIFO — 여기선 동기만 다룸)
--     * 스트리밍 데이터 일시 저장 (UART, 이더넷, 오디오 등)
--
--   소프트웨어 관점에선 배열과 두 포인터로 구현하는 원형 버퍼와 동일.
--
-- 【이 구현의 특성】
--   * 단일 클럭 도메인 (synchronous FIFO) — 쓰기/읽기 모두 같은 clk 기준.
--   * 파라미터:
--       WIDTH = 워드(저장 단위) 비트 폭
--       DEPTH = 저장 가능한 워드 개수
--   * FWFT(First-Word Fall-Through):
--       dout 은 "현재 head(가장 먼저 들어온 워드)" 를 항상 조합적으로 즉시 노출.
--       rd_en 펄스는 "읽고 포인터를 전진" 의 의미가 된다.
--       일반 FIFO(비-FWFT) 는 rd_en 한 클럭 뒤에 dout 이 유효 → FWFT 는 소비자 측
--       로직이 간단해지는 장점.
--   * 보호:
--       꽉 차 있을 때 wr_en → 무시 (오버플로 시 데이터 보존)
--       비어 있을 때 rd_en → 무시 (언더플로 시 포인터 고정)
--
-- 【동시 wr_en=rd_en 처리 규약】
--   동시에 쓰기와 읽기가 들어오면: write도 수행, read도 수행, count 불변.
--   흐름이 계속 유지되는 "통과" 동작 (선입력과 선출력이 동시 진행).
--=============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity fifo is
    generic (
        WIDTH                  : positive := 8;   -- 워드 폭 (비트)
        DEPTH                  : positive := 16;  -- FIFO 슬롯 개수
        ALMOST_FULL_THRESHOLD  : positive := 15;  -- count >= 이 값 → almost_full='1'
        ALMOST_EMPTY_THRESHOLD : positive := 1    -- count <= 이 값 → almost_empty='1'
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;   -- 동기 리셋
        wr_en        : in  std_logic;   -- 1 사이클 high → 한 워드 저장
        din          : in  std_logic_vector(WIDTH-1 downto 0);
        rd_en        : in  std_logic;   -- 1 사이클 high → head 포인터 +1
        dout         : out std_logic_vector(WIDTH-1 downto 0);  -- head 데이터 (조합 출력)
        full         : out std_logic;
        empty        : out std_logic;
        almost_full  : out std_logic;
        almost_empty : out std_logic;
        count        : out std_logic_vector(31 downto 0)        -- 디버깅용 32비트 노출
    );
end entity;

architecture rtl of fifo is
    --------------------------------------------------------------------------
    -- 【사용자 정의 배열 타입】
    --   문법: type <타입명> is array (<인덱스 범위>) of <원소 타입>;
    --   여기선 "DEPTH 개 슬롯, 각 슬롯은 WIDTH 비트 슬립브이" 배열 타입 선언.
    --
    --   VHDL 에서 배열 signal 은 합성기가 문맥을 보고
    --     - 작은 배열 → 개별 FF 로 (LUT 기반 분산 RAM)
    --     - 큰 배열   → BRAM/SRAM 블록 메모리 로
    --   자동 매핑한다. 메모리 추론(memory inference) 이라 부름.
    --------------------------------------------------------------------------
    type ram_t is array (0 to DEPTH-1) of std_logic_vector(WIDTH-1 downto 0);

    -- 초기값: 중첩 aggregate.
    --   외부 (others => ...) : 배열의 모든 원소에 대해
    --   내부 (others => '0') : 각 원소의 모든 비트를 '0' 으로
    signal ram : ram_t := (others => (others => '0'));

    -- ─── 포인터/카운터 ─────────────────────────────────────────────────────
    -- integer range 제약 → 합성기가 필요한 최소 비트 수만 할당.
    -- DEPTH=16 이면 포인터는 4비트, cnt 는 5비트 (0..16 → 17가지 → 5비트).
    signal wr_ptr : integer range 0 to DEPTH-1 := 0;  -- 다음 쓸 위치
    signal rd_ptr : integer range 0 to DEPTH-1 := 0;  -- 다음 읽을 위치 (head)
    signal cnt    : integer range 0 to DEPTH   := 0;  -- 현재 저장된 워드 수
begin
    --------------------------------------------------------------------------
    -- 【동기 프로세스: 쓰기/읽기/카운트 갱신】
    --
    --   clk 상승 엣지에서만 상태 변경 → 전형적인 동기 설계.
    --   if rst='1' 블록에서 모든 상태를 동시에 초기화 (동기 리셋).
    --
    --   process 안에서 여러 signal "<=" 대입은 "이 프로세스가 끝나는 시점" 에
    --   일괄 반영된다. 그래서 같은 프로세스 안에서 wr_ptr 을 대입하고 바로
    --   아래 조건에서 wr_ptr 을 읽어도, 읽히는 값은 "이전 값" (업데이트 전).
    --   → 실제 상태 전이는 "클럭 엣지 순간에 한 번에 일어난다" 와 일치.
    --------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- 동기 리셋: 포인터/카운터 모두 0. ram 내용은 굳이 안 지워도 됨
                -- (cnt=0 이면 어차피 아무도 참조하지 않는 쓰레기 데이터라서).
                wr_ptr <= 0;
                rd_ptr <= 0;
                cnt    <= 0;
            else
                ------------------------------------------------------------
                -- write 로직: 꽉 차지 않았을 때만 ram(wr_ptr) <= din 하고
                --            wr_ptr 을 다음 위치로 이동 (원형 wrap-around).
                ------------------------------------------------------------
                if wr_en = '1' and cnt /= DEPTH then
                    -- 배열 인덱싱: name(index). 이 한 줄이 "메모리에 쓰기" 에 해당.
                    ram(wr_ptr) <= din;

                    -- 원형 버퍼 wrap-around:
                    -- 마지막 슬롯까지 쓴 다음엔 0번 슬롯으로 되돌린다.
                    -- (modulo 연산을 직접 쓸 수도 있지만 if 로 명시적으로 표현)
                    if wr_ptr = DEPTH-1 then
                        wr_ptr <= 0;
                    else
                        wr_ptr <= wr_ptr + 1;
                    end if;
                end if;

                ------------------------------------------------------------
                -- read 로직: 비어있지 않을 때 rd_ptr 을 전진.
                --
                -- "데이터가 실제로 나가는 동작" 은 process 밖의 concurrent
                -- "dout <= ram(rd_ptr)" 이 담당한다 (FWFT — 조합적 노출).
                -- 이 블록은 포인터만 움직인다.
                ------------------------------------------------------------
                if rd_en = '1' and cnt /= 0 then
                    if rd_ptr = DEPTH-1 then
                        rd_ptr <= 0;
                    else
                        rd_ptr <= rd_ptr + 1;
                    end if;
                end if;

                ------------------------------------------------------------
                -- count 갱신 — 쓰기/읽기 유효성 조합에 따라 다음과 같다:
                --   동시 wr+rd 모두 유효 → +0 (입출 같음)
                --   wr 만 유효          → +1
                --   rd 만 유효          → -1
                --   둘 다 무효          → 불변 (else 없음 → 유지)
                ------------------------------------------------------------
                if    wr_en = '1' and cnt /= DEPTH and rd_en = '1' and cnt /= 0 then
                    cnt <= cnt;                     -- 명시적 "그대로"
                elsif wr_en = '1' and cnt /= DEPTH then
                    cnt <= cnt + 1;
                elsif rd_en = '1' and cnt /= 0 then
                    cnt <= cnt - 1;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- 【조합 출력 — FWFT 의 핵심】
    --
    --   process 밖의 "<=" 는 concurrent assignment → 항상 성립하는 와이어 연결.
    --   dout 은 "rd_ptr 이 가리키는 슬롯의 현재 값" 을 매 순간 즉시 보여준다.
    --
    --   이게 "First-Word Fall-Through" — 소비자는 rd_en 을 올리기 전에 이미
    --   dout 에서 head 워드를 볼 수 있다. rd_en 펄스는 "이걸 읽었으니 다음으로
    --   넘어가 주세요" 의 의미.
    --
    --   비-FWFT(표준) FIFO 는 rd_en → 한 클럭 뒤 dout 유효 이므로 소비자 쪽
    --   상태머신이 한 단계 더 필요해진다.
    --------------------------------------------------------------------------
    dout <= ram(rd_ptr);

    --------------------------------------------------------------------------
    -- 【상태 플래그 — 조건부 concurrent assignment】
    --
    -- 문법:
    --   target <= <값A> when <조건> else <값B>;
    --   (체이닝도 가능: ... when c1 else ... when c2 else ...;)
    --
    -- 여기서는 cnt 를 읽어 full/empty 등 4가지 플래그를 즉시 계산.
    -- cnt 가 FF 이므로 플래그들도 결과적으로 한 엣지 뒤 안정된 값을 갖는다.
    --------------------------------------------------------------------------
    full         <= '1' when cnt = DEPTH else '0';
    empty        <= '1' when cnt = 0 else '0';
    almost_full  <= '1' when cnt >= ALMOST_FULL_THRESHOLD  else '0';
    almost_empty <= '1' when cnt <= ALMOST_EMPTY_THRESHOLD else '0';

    --------------------------------------------------------------------------
    -- integer → std_logic_vector 변환 (2단계):
    --   1) to_unsigned(정수, 폭) : 정수를 해당 폭의 unsigned 벡터로
    --   2) std_logic_vector(...) : 같은 비트 패턴을 slv 로 재해석
    -- 32비트로 넉넉히 노출 → 외부 디버거/ILA 에서 바로 읽기 편하다.
    --------------------------------------------------------------------------
    count        <= std_logic_vector(to_unsigned(cnt, 32));
end architecture;
