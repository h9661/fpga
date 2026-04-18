# FPGA(VHDL) DSP 학습 계획 — 설계 문서

- **작성일:** 2026-04-18
- **학습자 배경:** 디지털 논리 회로 기초 보유 (AND/OR, FF, 카운터 등), HDL은 처음
- **목표 도메인:** DSP / 통신 신호처리
- **HDL:** VHDL (VHDL-2008)
- **하드웨어:** 시뮬레이션 전용 (실물 보드 미사용)
- **기간:** 8주, 주 15시간 (≈ 120시간)

## 1. 학습 목표와 성공 기준

### 최종 목표 (8주 종료 시점)

- VHDL로 **FIR 필터**와 **BPSK 변조기/복조기**를 직접 설계한다.
- 자체 작성한 테스트벤치로 **파형 확인이 아닌 수치 기반 자동 검증**까지 완료한다.
- 과정에서 다음 역량을 실무 수준으로 체화한다: FSM 설계, 파이프라이닝, 고정소수점 산술, self-checking testbench 작성.

### 최종 산출물 (레포에 남는 것)

1. 주차별 실습 코드 — 조합회로, FSM, FIFO/RAM, DSP IP
2. 각 모듈마다 self-checking testbench — PASS/FAIL 자동 출력
3. 메인 프로젝트 2종:
   - `05_fir_filter/` — 8-tap FIR, Python 기준값과 비트 정합
   - `07_bpsk_modem/` — BPSK 변조·복조, BER=0 검증
4. 주당 학습 일지 — `notes/week-NN.md`

### 의도적으로 포함하지 않는 것 (YAGNI)

- 실물 보드 배포 / 합성 후 타이밍 분석 — 시뮬레이션 전용 목표
- UVM / OSVVM — 8주 범위 밖
- CPU / RISC-V 설계 — 목표 도메인 아님
- Verilog / SystemVerilog — VHDL 집중

### 중간 체크포인트

- **3주차 말:** Phase 1 회고. 문법과 testbench 작성이 막힘 없이 되는지 자가 평가. 막히면 4주차 진입 전 1~2일 보강.
- **6주차 말:** DSP 블록들이 Python 기준값과 비트 단위로 정합되는지 확인. 안 되면 7주차 보류하고 수치 오차 원인 디버깅.

## 2. 툴체인

### 핵심 3종 (macOS 기준)

| 툴 | 역할 | 설치 |
|---|---|---|
| **GHDL** | VHDL-2008 컴파일러·시뮬레이터 | `brew install ghdl` |
| **GTKWave** | 파형 뷰어 (`.vcd`/`.ghw`) | `brew install gtkwave` |
| **Make** | 빌드·시뮬레이션 자동화 | macOS 기본 포함 |

### 보조 (필요 시 도입)

- **VUnit** — 파이썬 기반 VHDL 검증 프레임워크. 4주차 이후 testbench가 복잡해지면 도입 검토.
- **Python (NumPy, scipy)** — 골든 모델 생성 필수.

### 선택 근거

상용 툴(ModelSim/Questa)은 학습 단계에 불필요하고 macOS 지원도 빈약하다. GHDL + GTKWave는 VHDL-2008 기준 업계 호환이며 전부 오픈소스라 재현성이 높다. Makefile 한 장으로 "이 코드를 어떻게 검증했는가"를 설명할 수 있다는 점이 면접·과제 제출 측면에서도 유리하다.

## 3. 레포 구조

```
fpga/
├── 01_combinational/        # 1주차: ALU, mux, encoder
├── 02_sequential_fsm/       # 2주차: UART TX, FSM
├── 03_memory_fifo/          # 3주차: FIFO, UART RX
├── 04_fixed_point/          # 4주차: fixed_point_pkg, MAC
├── 05_fir_filter/           # 5주차: 8-tap FIR (메인 산출물)
├── 06_iir_cic/              # 6주차: CIC 데시메이터
├── 07_bpsk_modem/           # 7주차: BPSK modem (메인 산출물)
├── 08_polish_portfolio/     # 8주차: 리팩토링·README 보강
├── common/                  # 공용 패키지 (fixed_point_pkg 등)
├── notes/                   # 주차별 학습 일지
├── docs/superpowers/specs/  # 본 설계 문서
└── Makefile                 # 루트에서 make test 한 번에 전체 실행
```

각 주차 폴더 내부 구조는 통일한다:

```
NN_topic/
├── rtl/           # 설계 VHDL
├── tb/            # 테스트벤치
├── Makefile       # 해당 주차 빌드 규칙
└── README.md      # 설계 의도·검증 방법·결과 스크린샷
```

## 4. 주 단위 커리큘럼

### Phase 1 — VHDL 기초 체화 (1~3주차, ≈ 45h)

**1주차 — 조합 논리와 VHDL 기본 문법**
- 개념 (3~5h): entity/architecture, `std_logic`/`std_logic_vector`, concurrent signal assignment, process, 조합 회로 기술 스타일.
- 실습 (10~12h): 4-bit ALU (ADD/SUB/AND/OR/XOR/SHL/SHR), 4-to-1 mux tree, 8-to-3 priority encoder.
- 검증 산출물: `tb_alu.vhd` — 모든 op를 루프로 자동 검증하며 `assert`로 PASS/FAIL 출력.

**2주차 — 순차 회로, FSM, 간단한 송신기**
- 개념: process + sensitivity list, 동기/비동기 reset, D-FF, 카운터, Moore/Mealy FSM.
- 실습: UART 송신기 (8-N-1, 115200 baud @ 100 MHz clock).
- 검증: `tb_uart_tx.vhd` — start/stop 비트 타이밍과 데이터 순서를 자동 검증.

**3주차 — 메모리와 FIFO, 파라미터화**
- 개념: `signal` vs `variable`, generics, 메모리 추론(dual-port RAM), synchronous FIFO.
- 실습: 파라미터화된 sync FIFO (`DEPTH`, `WIDTH` generic), UART 수신기.
- 검증: `tb_fifo.vhd` — overflow, underflow, almost-full/empty 경계 검증.

**체크포인트 (3주차 말):** 문법·testbench 작성이 손에 익었는지 자가 평가. 막힘이 있으면 Phase 2 진입 전 1~2일 보강.

### Phase 2 — DSP 코어 (4~6주차, ≈ 45h)

**4주차 — 고정소수점과 파이프라이닝**
- 개념: Q-format (Q1.15, Q2.14), 오버플로우·라운딩 전략, 파이프라인 스테이지 균형.
- 실습: `fixed_point_pkg` 공용 패키지 (in `common/`), 3-stage 파이프라인 MAC 유닛.
- 검증: NumPy로 기준값 계산 → 허용 오차 내 비교하는 testbench.

**5주차 — FIR 필터 (메인 산출물 1)**
- 개념: 직접형 FIR, 대칭형 FIR, 계수 대칭성 활용, ROM 기반 계수 저장.
- 실습: 8-tap low-pass FIR. 계수는 `scripts/gen_fir_coeffs.py`에서 scipy로 생성해 `coeffs.mem`으로 저장.
- 검증: Python에서 `scipy.signal.lfilter`로 동일 입력을 필터링한 결과와 **비트 정합 비교**.

**6주차 — IIR과 CIC 데시메이터**
- 개념: IIR biquad, CIC 데시메이터 (R, M, N 파라미터), compensation FIR.
- 실습: CIC 데시메이터 (R=8, M=1, N=3) + compensation FIR.
- 검증: 임펄스·사인파 입력에 대한 출력을 이론 주파수 응답과 대조.

**체크포인트 (6주차 말):** DSP 블록이 Python 기준값과 비트 단위 정합되는지 확인. 안 되면 7주차 보류하고 수치 오차 원인부터 추적.

### Phase 3 — 통신 시스템 통합 (7~8주차, ≈ 30h)

**7주차 — BPSK 변조기/복조기 (메인 산출물 2)**
- 개념: BPSK 이론, NCO (Numerically Controlled Oscillator), matched filter, 심볼 타이밍 복구.
- 실습: BPSK 변조기 + 복조기 (이상 채널, AWGN 없음).
- 검증: 송신 비트열 = 수신 비트열 비트정합 testbench, BER=0 확인.

**8주차 — 포트폴리오 정리**
- 개념: 코드 리뷰, 문서화 우선순위.
- 실습: `05_fir_filter`, `07_bpsk_modem` README 작성 (설계 근거, 검증 결과 로그, 보조 설명용 파형 스크린샷 포함), 구조 리팩토링.
- 검증: 루트에서 `make test` 한 번에 모든 주차 testbench 통과.

## 5. 검증 전략

### 원칙

1. **Self-checking testbench만 인정.** 사람이 파형을 눈으로 확인하는 방식은 검증으로 치지 않는다. `assert` 또는 PASS/FAIL 출력이 반드시 있어야 한다.
2. **Golden model은 Python으로.** DSP 블록은 NumPy/scipy로 기준값을 생성해 `.mem`/`.txt`로 덤프하고, VHDL testbench가 읽어서 비교한다.
3. **파형은 디버깅용**, 검증은 `assert`로. GTKWave는 "왜 틀렸지?"를 볼 때만 연다.

### 각 testbench 필수 요소

- 리셋 시퀀스
- 정상 케이스 (typical)
- 경계 케이스 (min/max, overflow)
- 랜덤 입력 (최소 100회, VHDL `uniform` 사용)
- 종료 시 PASS/FAIL 요약 출력

### 루트 Makefile

- `make test` — 전 주차 testbench 실행. 하나라도 FAIL이면 `exit 1`.
- `make wave WEEK=05` — 해당 주차의 파형을 GTKWave로 연다.
- `make clean` — 산출 바이너리 제거.

## 6. 참고 자료

### 주 교재 (1권만)

- Peter Ashenden, *The Designer's Guide to VHDL* (3rd ed.) — 문법 참고서로 사용, 통독하지 않는다.

### DSP 레퍼런스

- Uwe Meyer-Baese, *Digital Signal Processing with FPGAs* — 5주차부터 해당 장만 발췌.
- Richard Lyons, *Understanding Digital Signal Processing* — BPSK/modem 이론 배경.

### 무료 온라인

- VHDLwhiz (vhdlwhiz.com) — 패턴별 짧은 튜토리얼.
- ZipCPU 블로그 (zipcpu.com) — Verilog 중심이지만 검증 방법론은 언어 무관.

### 8주 이후

- HackerRank FPGA, ASIC Digital Design 문제집 — 면접·취업 대비.

## 7. 위험과 대응

| 위험 | 대응 |
|---|---|
| DSP 수학이 막혀 5주차에서 멈춤 | Richard Lyons 책 1~4장을 3주차 말 자투리 시간에 미리 읽기 |
| 고정소수점에서 Python과 비트 정합이 안 됨 | 4주차에 `fixed_point_pkg`의 라운딩 규칙을 scipy의 `numpy.round` 반올림 모드와 맞추는 테스트를 먼저 작성 |
| 8주 내 BPSK까지 못 감 | 7주차 BPSK를 이상 채널 한정으로만 구현하고, AWGN·타이밍 오프셋은 8주 이후 과제로 넘김 |
| VHDL 문법 세부가 자꾸 걸림 | 통독 대신 "막힐 때만 Ashenden 색인에서 찾기". 시간 쓰면 곧바로 실습으로 복귀 |

## 8. 다음 단계

본 설계 문서 승인 후 `writing-plans` skill로 넘어가, 1주차 실습부터 순서대로 수행 가능한 구체적 구현 계획을 작성한다.
