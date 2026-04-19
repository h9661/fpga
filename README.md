# FPGA VHDL DSP 학습 레포

8주 커리큘럼. 설계 문서: [docs/superpowers/specs/2026-04-18-fpga-vhdl-dsp-learning-plan-design.md](docs/superpowers/specs/2026-04-18-fpga-vhdl-dsp-learning-plan-design.md).

## 요구 사항

- GHDL (VHDL-2008 지원 버전)
- Surfer (파형 뷰어, GTKWave 대체)
- GNU Make

macOS:
```
brew install ghdl
brew install --cask surfer
```

설치 없이 쓰려면 https://app.surfer-project.org 에 `.vcd` 파일을 드래그해도 된다.

## 실행

전체 테스트:
```
make test
```

특정 주차 테스트:
```
make -C 01_combinational test
```

파형 보기:
```
make -C 01_combinational wave MODULE=alu
```

## 디렉토리

- `01_combinational/` — Week 1: ALU, mux, encoder
- `common/` — 주차 간 공용 Makefile·VHDL 패키지
- `docs/` — 설계 문서, 구현 계획
