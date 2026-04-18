# Week 2 — 순차 회로, FSM, UART 송신기

## 모듈

| 모듈 | 파일 | 설명 |
|---|---|---|
| `counter` | `rtl/counter.vhd` | WIDTH-파라미터화 saturating up-counter (동기 reset, en) |
| `uart_tx` | `rtl/uart_tx.vhd` | 8-N-1 UART 송신기 (Moore FSM: IDLE→START→DATA→STOP) |

## 검증

- `tb_counter`: 리셋·en=0 유지·카운트 0→15·포화·재-리셋 시나리오
- `tb_uart_tx`: CLK=1 MHz, BAUD=100 kHz (시뮬 가속) 설정으로 0x00~0xFF 256 바이트 back-to-back 송신, 시뮬 내 UART 수신 procedure로 검증

실행:
```
make test
```

## 배운 것

- `rising_edge(clk)` + 동기 reset 패턴 (비동기 reset 아님)
- `signal` vs `variable`: 클럭드 프로세스 내 `<=`는 이벤트 큐에 등록, 실제 반영은 다음 delta
- FSM 기술 스타일: 단일 `process(clk)` + `case state`
- Generic을 활용한 clock frequency·baud rate 파라미터화 → 시뮬 속도 자유 조절
- `wait until tx_line='0'`는 level이 아닌 EVENT를 기다리므로, 이미 조건이 참인 경우 guard(`if ... then wait until ...`)가 필요
