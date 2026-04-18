# Week 2 학습 일지

## 새로 알게 된 것

- **동기 reset** (클럭 에지에서만 reset 인식) vs **비동기 reset** (reset 변화 즉시 인식). 이번 주는 동기로 통일. 타이밍 분석이 단순해지고 FPGA 합성에도 호의적.
- FSM은 보통 **단일 clocked process** + `case state is ...`로 쓴다. 2-process 스타일(next-state 계산 vs register 분리)도 있으나 단순하면 1-process가 읽기 편함.
- Testbench에서 **generic으로 BIT_CLKS를 줄이면** 시뮬 속도를 수십 배 빠르게 할 수 있다. 실제 합성 시엔 기본값(100 MHz / 115.2 kHz)을 쓰면 됨.
- `wait until rising_edge(clk); wait for 1 ns;` 패턴: rising_edge 직후 delta cycle을 모두 처리하고 안정화된 출력값을 읽기 위함.
- **`wait until X='value'`는 EVENT 기반**: 이미 `X='value'`인 상태에서 호출하면 새로운 이벤트가 올 때까지 대기. 이미 참인 경우를 다루려면 `if X /= 'value' then wait until X='value'; end if;` guard 필요.

## 막힌 지점 / 디버깅

### 실제 마주친 이슈

- **UART start bit 길이 문제**: 초안에선 `wait until tx_line='0'`이 IDLE에서 `line_r<='0'` 즉시 드라이브로 인해 이벤트를 놓쳐 행에 걸림 → START 상태에서만 드라이브하게 수정하니 testbench는 통과했지만 start bit가 9 CLK_PER (UART 규격 위반 10% 짧음). 코드리뷰에서 다음 수정 확정:
  - RTL IDLE에 `line_r <= '0';` 복원 (start bit가 같은 클럭에서 즉시 시작)
  - Testbench에 `if tx_line /= '0' then wait until tx_line = '0'; end if;` guard 추가 (이미 참인 경우 skip)
  - 결과: 10 CLK_PER start bit, 256 바이트 exhaustive PASS.

### 자가 체크 (4문항)

**Q1. 동기 reset과 비동기 reset의 차이?**
A1. 동기 reset은 `if rising_edge(clk) then if rst='1' then ...` 형태로 클럭 에지에서만 reset을 샘플한다. 비동기는 `process(clk, rst)` 감도 리스트에 rst를 넣고 즉시 반응. 동기는 타이밍 분석·메타스테이블 회피에 유리, 비동기는 클럭이 없어도 초기화 가능.

**Q2. Moore FSM vs Mealy FSM? UART_TX는?**
A2. Moore는 출력이 현재 상태에만 의존 (클럭 동기), Mealy는 입력+상태에 의존 (조합 경로 존재). UART_TX는 `tx_line`을 상태 기반으로 레지스터(line_r)에 저장하므로 **Moore** 구조. `tx_busy`도 `state=IDLE`에서만 바뀌는 Moore 출력.

**Q3. 왜 CLK_FREQ_HZ·BAUD_RATE을 generic으로 분리했는가?**
A3. 테스트벤치에서 CLK=1 MHz, BAUD=100 kHz로 BIT_CLKS=10을 주면 1 byte=100 cycles=1 μs로 시뮬이 빠름. 상수로 100 MHz/115200을 하드코딩했다면 BIT_CLKS=868이 되어 1 byte=8.68 μs, 256 바이트=2.2 ms 시뮬로 10배 이상 느려짐. 합성 시엔 기본값으로 되돌리면 됨.

**Q4. `wait until tx_line='0'` vs `wait until rising_edge(clk)`의 차이?**
A4. 둘 다 EVENT 기반이지만 조건이 다름. 전자는 `tx_line` 신호에 변화가 생겨 값이 '0'이 될 때 트리거 (level이 아닌 변화 순간). 후자는 `clk`가 '0'→'1'로 상승하는 에지(attribute `'event` 체크)에서 트리거. 두 경우 모두 이미 조건이 참이라도 새 이벤트가 와야 깨어난다.

## 다음 주 예열

- 메모리·FIFO. dual-port RAM 추론 패턴과 synchronous FIFO의 full/empty 플래그 정의 미리 훑기.
