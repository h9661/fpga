--=============================================================================
-- fifo.vhd — 파라미터라이즈드 동기 FIFO (First-Word Fall-Through)
--=============================================================================
-- 개요:
--   * 단일 클럭 도메인의 원형 버퍼(circular buffer).
--   * DEPTH 개의 WIDTH-비트 워드를 저장한다.
--   * FWFT(First-Word Fall-Through): dout은 head(가장 먼저 들어온) 데이터를
--     항상 즉시(조합) 보여준다. rd_en 펄스는 "다음 워드로 포인터를 진행"의 의미.
--   * 오버플로/언더플로 보호: 꽉 찼을 때 wr_en은 무시, 비었을 때 rd_en은 무시.
--   * 플래그: full, empty, almost_full, almost_empty.
--
-- 제어 약속:
--   wr_en = 1 사이클 high → 한 워드 저장.
--   rd_en = 1 사이클 high → head 포인터 +1 (dout은 조합이라 다음 클럭에 다음 값).
--   동시 wr_en=rd_en=1 → 쓰기/읽기 모두 수행, count 불변.
--=============================================================================

-- library / use 절: 외부 패키지에서 가져올 기호를 현재 네임스페이스에 노출.
--   ieee.std_logic_1164: std_logic, std_logic_vector, rising_edge(...) 등 정의.
--   ieee.numeric_std   : unsigned/signed 산술 및 to_unsigned/to_integer 변환.
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

-- entity: 외부에서 보이는 "핀(port)" + 컴파일타임 파라미터(generic) 선언.
-- 문법: entity <이름> is ... end entity;  (마지막 세미콜론 필수)
entity fifo is
    generic (
        -- generic = 인스턴스화 시 고정되는 상수. positive 서브타입은 1 이상의 정수만
        -- 허용하므로 DEPTH=0 같은 비정상 입력이 원천 차단된다.
        WIDTH                  : positive := 8;   -- 워드 폭 (비트)
        DEPTH                  : positive := 16;  -- FIFO 슬롯 개수
        ALMOST_FULL_THRESHOLD  : positive := 15;  -- count >= 이 값 → almost_full='1'
        ALMOST_EMPTY_THRESHOLD : positive := 1    -- count <= 이 값 → almost_empty='1'
    );
    port (
        -- port 모드: in(입력), out(출력), inout(양방향), buffer(내부 피드백 허용).
        -- in 포트를 out처럼 쓸 수 없으며, 그 반대도 마찬가지.
        clk          : in  std_logic;
        rst          : in  std_logic;  -- 동기 리셋: clk 엣지에서 샘플됨
        wr_en        : in  std_logic;
        din          : in  std_logic_vector(WIDTH-1 downto 0);
        rd_en        : in  std_logic;
        dout         : out std_logic_vector(WIDTH-1 downto 0);
        full         : out std_logic;
        empty        : out std_logic;
        almost_full  : out std_logic;
        almost_empty : out std_logic;
        -- count는 32비트로 외부 디버깅 편의상 넉넉히 확장.
        -- 내부 cnt(integer) → to_unsigned(cnt,32) → std_logic_vector 변환.
        count        : out std_logic_vector(31 downto 0)
    );
end entity;

-- architecture: entity 내부 구현을 기술. 하나의 entity에 여러 architecture 가능.
architecture rtl of fifo is
    -- ─── 사용자 정의 타입 ──────────────────────────────────────────────────
    -- "type <T> is array (<범위>) of <원소타입>;" 배열 타입 선언.
    -- 이 줄은 타입을 "선언"만 하고, 실제 객체(signal)는 아래에서 만든다.
    type ram_t is array (0 to DEPTH-1) of std_logic_vector(WIDTH-1 downto 0);

    -- ─── 내부 신호 선언 ────────────────────────────────────────────────────
    -- signal: 하드웨어 와이어/레지스터에 대응. 초기값은 ":=" 로 지정.
    -- (others => (others => '0')): 중첩 aggregate — 바깥=배열 모든 원소, 안=모든 비트.
    signal ram : ram_t := (others => (others => '0'));

    -- integer range 제약: 합성 툴이 포인터 비트 폭을 자동 산정한다.
    -- 아래 wr_ptr/rd_ptr은 0..DEPTH-1 범위이므로 ceil(log2 DEPTH) 비트면 충분.
    signal wr_ptr : integer range 0 to DEPTH-1 := 0;  -- 다음 쓸 주소
    signal rd_ptr : integer range 0 to DEPTH-1 := 0;  -- 다음 읽을 주소
    -- cnt 범위는 0..DEPTH (꽉 찼을 때 = DEPTH, 즉 DEPTH+1 가지 상태).
    signal cnt    : integer range 0 to DEPTH   := 0;
begin
    --------------------------------------------------------------------------
    -- 동기 프로세스 (상태 갱신)
    --   * sensitivity list에 clk만 → 순수 동기 회로 (edge-triggered 플립플롭).
    --   * if rising_edge(clk) 블록 안에서만 실제 레지스터 업데이트가 일어난다.
    --   * signal "<=" 대입은 "이번 클럭 사이클 끝에서 반영" 의미이며, 같은 프로세스
    --     안에서 여러 번 대입하면 마지막 대입이 유효하다 (VHDL의 signal 스케줄링).
    --------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- 동기 리셋: 포인터/카운터만 초기화.
                -- (ram 내용은 굳이 초기화하지 않음 — cnt=0이면 쓸모없는 데이터라 OK)
                wr_ptr <= 0;
                rd_ptr <= 0;
                cnt    <= 0;
            else
                -- write 로직: 꽉 차지 않은 경우에만 진행 (overflow 보호).
                -- "/=" 는 "같지 않다" 연산자 (C의 != 에 해당).
                if wr_en = '1' and cnt /= DEPTH then
                    ram(wr_ptr) <= din;                 -- 배열 인덱싱: name(index)
                    -- 원형 버퍼 wrap-around: 끝 도달 시 0으로 되돌린다.
                    if wr_ptr = DEPTH-1 then
                        wr_ptr <= 0;
                    else
                        wr_ptr <= wr_ptr + 1;
                    end if;
                end if;

                -- read 로직: 비어 있지 않은 경우에만 포인터 진행 (underflow 보호).
                -- 실제 데이터 출력은 process 밖의 concurrent 문 "dout <= ram(rd_ptr)"이 담당.
                if rd_en = '1' and cnt /= 0 then
                    if rd_ptr = DEPTH-1 then
                        rd_ptr <= 0;
                    else
                        rd_ptr <= rd_ptr + 1;
                    end if;
                end if;

                -- count 갱신 — 쓰기/읽기 조합에 따라:
                --   동시 wr+rd   → +0 (들어오는 만큼 나감)
                --   wr만 유효    → +1
                --   rd만 유효    → -1
                --   둘 다 무효   → 불변 (else 절 없음, signal이 유지)
                if    wr_en = '1' and cnt /= DEPTH and rd_en = '1' and cnt /= 0 then
                    cnt <= cnt;                         -- 명시적 "변화 없음"
                elsif wr_en = '1' and cnt /= DEPTH then
                    cnt <= cnt + 1;
                elsif rd_en = '1' and cnt /= 0 then
                    cnt <= cnt - 1;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- 조합 출력 (FWFT)
    --   process 밖의 "<=" 는 concurrent assignment → 항상 성립하는 와이어 연결.
    --   dout은 rd_ptr이 가리키는 head 슬롯을 매 순간 그대로 노출한다.
    --------------------------------------------------------------------------
    dout <= ram(rd_ptr);

    --------------------------------------------------------------------------
    -- 상태 플래그 (조건부 concurrent assignment)
    --   문법: target <= value_if_true when condition else value_if_false;
    --   체인 가능: ... when cond1 else ... when cond2 else ...;
    --------------------------------------------------------------------------
    full         <= '1' when cnt = DEPTH else '0';
    empty        <= '1' when cnt = 0 else '0';
    almost_full  <= '1' when cnt >= ALMOST_FULL_THRESHOLD  else '0';
    almost_empty <= '1' when cnt <= ALMOST_EMPTY_THRESHOLD else '0';

    -- integer → std_logic_vector 변환 (2단계 캐스팅):
    --   1) to_unsigned(정수, 폭) : 정수를 지정 폭의 unsigned 벡터로.
    --   2) std_logic_vector(...) : 같은 비트 패턴을 slv 타입으로 재해석.
    count        <= std_logic_vector(to_unsigned(cnt, 32));
end architecture;
