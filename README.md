# FPGA VHDL DSP 학습 레포

8주 커리큘럼. 설계 문서: [docs/superpowers/specs/2026-04-18-fpga-vhdl-dsp-learning-plan-design.md](docs/superpowers/specs/2026-04-18-fpga-vhdl-dsp-learning-plan-design.md).

## 진행 현황 (2026-04-26)

- **Phase 1** (Week 1~3) — VHDL 기초 체화. 7 testbenches PASS.
- **Phase 2** (Week 4~6) — DSP 코어. 4 testbenches PASS, 모두 Python 골든과 비트 정합.
- **Phase 3** (Week 7~8) — BPSK 모뎀 + 포트폴리오. 미진행.

루트 `make test` 한 번에 11 testbenches 모두 PASS.

## 요구 사항

- GHDL (VHDL-2008 지원 버전)
- Surfer (파형 뷰어, GTKWave 대체)
- GNU Make
- Python 3 + NumPy + scipy (Phase 2 골든 모델용)

macOS:
```
brew install ghdl
brew install --cask surfer
python3 -m venv .venv && .venv/bin/pip install numpy scipy
```

설치 없이 쓰려면 https://app.surfer-project.org 에 `.vcd` 파일을 드래그해도 된다.

## 실행

전체 테스트:
```
make test
```

특정 주차 테스트:
```
make -C 04_fixed_point test
```

파형 보기:
```
make -C 04_fixed_point wave MODULE=mac
```

## 디렉토리

- `01_combinational/` — Week 1: ALU, mux4, priority_encoder
- `02_sequential_fsm/` — Week 2: counter, UART TX
- `03_memory_fifo/` — Week 3: parameterized FIFO, UART RX
- `04_fixed_point/` — Week 4: 3-stage pipelined MAC
- `05_fir_filter/` — Week 5: 8-tap LP FIR (Phase 2 메인 산출물 1)
- `06_iir_cic/` — Week 6: IIR biquad (DF2T) + CIC decimator (R=8,M=1,N=3)
- `common/` — 주차 간 공용 Makefile + 공용 VHDL 패키지 (`fixed_point_pkg`)
- `docs/` — 설계 문서, 구현 계획
- `.venv/` (gitignored) — Python golden 모델용 가상환경
