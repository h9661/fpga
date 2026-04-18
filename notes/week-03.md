# Week 3 학습 일지

## 새로 알게 된 것

- **메모리 추론**: `type ram_t is array (0 to DEPTH-1) of std_logic_vector(WIDTH-1 downto 0)` 배열을 signal로 선언하면 Xilinx/Intel 툴이 BRAM 또는 LUT-RAM으로 추론한다. 읽기·쓰기 포트가 둘 이상이면 dual-port BRAM으로.
- **Generic 간 의존**: FIFO의 `ALMOST_FULL_THRESHOLD : positive := DEPTH-1`처럼 한 generic의 기본값이 다른 generic을 참조할 수 있다. 사용자가 DEPTH를 바꾸면 threshold 기본값도 자동 추적됨.
- **FWFT FIFO 스타일**: `dout`을 조합적으로 `ram(rd_ptr)`에 연결하면 head가 항상 즉시 보인다. `rd_en` pulse는 "이미 읽었으니 다음으로"라는 의미. 이 모델에서 tb는 `dout` 샘플 → `rd_en` 펄스 순서로 읽어야 한다.
- **1-cycle pulse 패턴**: 출력 신호를 매 cycle `<= '0'`으로 default 덮어쓰기하고, 특정 조건에서만 `<= '1'`. latch 추론 없이 단일 cycle pulse.
- **UART RX midpoint sampling**: start bit 중앙 재확인 후 BIT_CLKS 주기로 data bit 중앙에서 샘플. STOP 상태는 stop bit 샘플(cnt=BIT_CLKS-1)과 valid pulse 방출(cnt=STOP_FIRE=BIT_CLKS-1+HALF_BIT)을 분리해, testbench의 `tx_byte` procedure가 반환한 직후 poll할 때 pulse를 확실히 잡을 수 있게 한다.

## 막힌 지점 / 디버깅

### 실제 마주친 이슈

- **UART RX 타이밍**: 초안 RTL은 STOP 상태에서 cnt=BIT_CLKS-1에 즉시 `valid_r<='1'`을 냈다. 그러나 `tx_byte` procedure가 stop bit 끝에서 반환하고 tb가 그 시점부터 poll 시작하면 pulse를 이미 놓친 뒤였다. 해결: STOP 상태를 sample 단계(stop_ok 래치)와 emit 단계(valid_r pulse at STOP_FIRE)로 분리해 tx_byte 종료 직후에 pulse가 뜨도록 맞춤. 5ns 정도 마진이지만 BIT_CLKS에 선형 비례하므로 실제 합성(BIT_CLKS=868)에서는 충분.

### 자가 체크 (Phase 1 마감)

**Q1. FIFO의 `count` 신호를 두는 이유? pointer 두 개(wr_ptr, rd_ptr)만으로 full/empty를 구분할 수 없는 이유?**
A1. wr_ptr == rd_ptr인 상태가 "비어 있음"과 "가득 참" 둘 다를 의미할 수 있기 때문. 순환 큐는 한 칸을 항상 비워 두거나 (usable depth가 DEPTH-1로 줄어듦), 별도의 count나 "generation bit"를 두어 두 상태를 구분해야 한다. count는 가장 단순하고 오류 적은 해결책.

**Q2. `type ram_t is array ... of std_logic_vector`가 BRAM으로 추론되는 조건?**
A2. (a) 배열이 signal이고 클럭드 프로세스 안에서 `ram(wr_ptr) <= din` 형태로 쓰여지고 (b) 읽기·쓰기 포트 수가 FPGA 타깃 BRAM 구조(보통 2)와 맞고 (c) 크기가 LUT-RAM보다 BRAM이 유리한 수준이면 자동 추론. Xilinx는 대략 128 bit 이상, Intel은 유사한 heuristic. 더 명확히 하려면 `(* ram_style = "block" *)` 같은 attribute를 붙인다.

**Q3. BIT_CLKS가 홀수(예: 11)면 `HALF_BIT = BIT_CLKS/2 = 5`가 되어 midpoint가 실제 중심에서 0.5 cycle 비껴간다.** 한 bit 내에서는 허용 오차(대략 25%)에 비해 훨씬 작은 오차라 문제없지만, 8개 데이터 bit를 샘플하면서 누적될 수 있다. 실무에서는 보통 BIT_CLKS가 충분히 크므로(10 이상) 0.5 cycle shift는 무시 가능. 더 엄격히 하려면 HALF_BIT 대신 `(BIT_CLKS-1)/2`나 rounding-up 중 프로토콜 쪽 관례에 맞춘다.

**Q4. Phase 1에서 배운 세 가지 검증 패턴.**
A4.
- **Exhaustive input (조합회로)**: ALU·mux·priority encoder는 입력 조합 전수를 루프로 돌림. 상태 공간이 작을 때 최강.
- **TDD stub→fail→pass (순차회로)**: 실패하는 testbench 먼저, 빈 stub RTL로 FAIL 확인, 그 다음 구현으로 PASS. 테스트가 실제로 구현 결함을 잡는지 검증하는 메타-검증.
- **Loopback 시뮬 (프로토콜)**: UART TX의 tb는 시뮬 내 RX procedure로 받고, UART RX의 tb는 시뮬 내 TX procedure로 보냄. 두 방향이 서로의 golden model이 되어 상호 검증.

## Phase 2 진입 준비

- Python scipy/numpy 설치 확인 (Week 5 FIR 계수 생성에 필요)
- `common/fixed_point_pkg` 작성할 위치 확인 — 이미 `common/` 디렉토리 존재
- Q-format(Q1.15, Q2.14) 배경 읽기 — Meyer-Baese 해당 장
