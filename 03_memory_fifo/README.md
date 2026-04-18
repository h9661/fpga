# Week 3 — 메모리, Sync FIFO, UART 수신기

## 모듈

| 모듈 | 파일 | 설명 |
|---|---|---|
| `fifo` | `rtl/fifo.vhd` | WIDTH·DEPTH·almost 플래그 threshold 전부 generic. 메모리 추론 (array of std_logic_vector) 패턴. FWFT 스타일 조합 읽기. |
| `uart_rx` | `rtl/uart_rx.vhd` | 8-N-1 UART 수신기 (midpoint 샘플링). rx_valid 1-cycle pulse로 수신 완료 알림. STOP 상태를 sample/emit 단계로 분리해 stop bit 종료 후 pulse. |

## 검증

- `tb_fifo`: 6 시나리오 — fill, drain, overflow, underflow, almost-full/empty, 동시 wr/rd
- `tb_uart_rx`: 내장 `tx_byte` procedure로 0x00~0xFF 256 바이트 송신 → DUT 수신 값 및 rx_valid 1-cycle pulse 타이밍 검증

실행:
```
make test
```

## 배운 것

- VHDL에서 `type ram_t is array ... of std_logic_vector(...)` + `signal ram : ram_t` 패턴이 합성 툴에 **BRAM/LUT-RAM 추론** 신호가 된다
- Sync FIFO의 full/empty 정의: pointer (wr_ptr, rd_ptr) + count. count를 쓰면 단순하고 오류가 적다
- FWFT (First-Word-Fall-Through): `dout <= ram(rd_ptr)`로 head를 항상 조합적으로 노출. `rd_en` pulse는 "이미 읽었으니 진행"의 신호
- UART 수신기의 midpoint 샘플링: start bit 감지 후 HALF_BIT 대기 → 이후 BIT_CLKS마다 data bit 중앙에서 샘플
- 1-cycle pulse 출력 패턴: `valid_r <= '0';`을 process 최상단에 두고 특정 조건에서만 `'1'` 덮어쓰기. latch 추론 없음
- STOP 상태 sample/emit 분리: stop bit 중앙에서 validity를 `stop_ok`에 래치, stop bit 끝난 뒤 valid pulse를 방출. 테스트벤치가 tx_byte 완료 후 poll을 시작할 때 pulse를 놓치지 않음
