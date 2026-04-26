# Week 4 — 고정소수점 + 3-스테이지 파이프라인 MAC

Phase 2 시작. 본 주차부터 **Python(NumPy) 골든 모델**과 비트 정합 비교한다.

## 모듈
| 모듈 | 파일 | 설명 |
|---|---|---|
| `fixed_point_pkg` | `../common/fixed_point_pkg.vhd` | Q1.15 ↔ real, Q2.30 곱셈, round-half-up + saturate |
| `mac` | `rtl/mac.vhd` | 3-stage 파이프라인 (input reg → mul reg → acc reg). 3-cycle latency, 1 sample/cycle throughput |

## 검증
- `tb_mac`:
  - 시나리오 A — 16 샘플 연속 push, 마지막 acc 비교.
  - 시나리오 B — 매 샘플 격리 push, 매 부분 누산 acc[i] 정합.
- 골든 벡터: `scripts/gen_mac_vectors.py` 가 NumPy seed=20260426 으로 [-0.3, 0.3] 균등 분포 16 샘플을 만들어 Q1.15 양자화 + Q2.30 곱 + 누적해 `data/mac_vectors.txt` 로 dump.

## 실행
```
make test
```
`make` 가 자동으로 `../.venv/bin/python` 으로 골든 벡터를 생성한 뒤 GHDL 시뮬을 돌린다.

## 배운 것
- **Q-format = 약속**: 정수 레지스터 + "이 값을 2^F 로 나눈 실수로 해석한다" 는 사람 약속. 하드웨어 비용 0.
- **곱셈 후 폭 증가**: Q1.15 × Q1.15 = Q2.30 (32-bit signed). `numeric_std signed * signed` 가 자동으로 폭을 늘려준다.
- **파이프라이닝**: latency(3 cycle) ↑, throughput(1 sample/cycle) 그대로. 가치는 fmax 향상.
- **Bit-exact 검증의 필수 조건**: 양자화 라운딩 모드 일치. VHDL `integer(real)` = numpy.round = round-half-to-even. 한 LSB 차이 = 라운딩 mismatch 의 신호.
- **textio file path**: GHDL 은 `ghdl -r` 호출 시 cwd 기준 상대경로. Makefile 이 항상 주차 폴더에서 실행하므로 `data/foo.txt` 로 충분.

## 디렉토리
```
04_fixed_point/
├── Makefile        # 데이터 자동 생성 + GHDL 실행
├── README.md
├── scripts/
│   └── gen_mac_vectors.py
├── rtl/
│   └── mac.vhd
├── tb/
│   └── tb_mac.vhd
└── data/           # gitignored, make 가 생성
    └── mac_vectors.txt
```
