# Week 6 — IIR Biquad + CIC 데시메이터

Phase 2 의 두 번째 DSP 빌딩 블록 모음. 둘 다 Python 동일 산술 reference 와 비트 정합 검증.

## 모듈

| 모듈 | 파일 | 설명 |
|---|---|---|
| `iir_coeffs_pkg` | `rtl/iir_coeffs_pkg.vhd` | `BIQUAD_LP_B0..B2`, `A1..A2` Q1.15 상수. `butter(2, 0.3)` 양자화 |
| `iir_biquad` | `rtl/iir_biquad.vhd` | 2nd-order IIR, Direct Form II Transposed. 상태 s1/s2 = 40-bit Q10.30 |
| `cic_decim` | `rtl/cic_decim.vhd` | CIC R=8, M=1, N=3. 32-bit modular 산술 + 출력 `>> 9` round-half-up |

## 검증

- `tb_iir_biquad`:
  - 5 계수(b0,b1,b2,a1,a2) parity 확인 — Python 출력과 패키지 상수 비교.
  - 64 샘플 (impulse + step + sine + random) 1-cycle 후 y_out 비트 정합.
- `tb_cic_decim`:
  - 헤더 (R, M, N) 가 RTL generic 과 일치하는지 확인.
  - 80 입력 → 10 출력. y_valid='1' 시점 마다 비교.

## 실행
```
make test
```

## 배운 것

### IIR Biquad / DF2T
- **DF2T (Direct Form II Transposed)** 가 IIR 의 표준 구조: 모든 곱셈이 입력 x 또는 출력 y 에만 의존 → 곱셈기 입력 레지스터(retiming) 가 자연스러움. 안정성에서도 DF1·DF2 보다 우수.
- **상태 폭 결정**: 상태 s1/s2 는 누산기 역할이라 단순 Q2.30 으로는 부족. 8 guard bits 더해 40-bit Q10.30. 안정 필터에서 modular wrap 안 일어남.
- **계수 fit**: `butter(2, 0.3)` 의 모든 |coef| < 1 이라 Q1.15 그대로. cutoff 가 더 낮으면 |a1| > 1 이 되어 Q2.14 같은 다른 포맷 필요.

### CIC
- **modular 산술 트릭**: 적분기는 무한 폭이 이상이지만, 동일 폭 wrap-around 두 시점의 차이는 wrap 횟수가 같으므로 정확히 복원. → 곱셈기 없이 가산·감산만으로 N stage 데시메이터 완성.
- **bit growth 공식**: `B_internal ≥ B_in + N·log2(R·M)`. R=8, M=1, N=3 → 16 + 9 = 25 bit 최소. 본 모듈은 32-bit 로 여유.
- **DC gain = (R·M)^N**: R=8, M=1, N=3 → 512. unit-gain Q1.15 출력으로 환산하려면 `>> 9` round-half-up + saturate.
- **process intra-cycle 의미**: 적분기 3단을 한 클럭 안에 cascade 하려면 VHDL 의 non-blocking 신호 대입만으론 매 단마다 1 cycle 지연이 추가됨. process 내부 variable 로 sequential 갱신 후 일괄 commit. Python 골든도 같은 순서로 갱신해야 비트 정합.

### 공통
- `assert N = 3 severity failure` — generic 으로 설계 범위 밖 값이 들어오면 elaboration 시 즉시 차단. design-by-contract 의 가벼운 형태.

## 디렉토리
```
06_iir_cic/
├── Makefile        # 데이터 자동 생성 + GHDL 실행
├── README.md
├── scripts/
│   └── gen_iir_cic_data.py
├── rtl/
│   ├── iir_coeffs_pkg.vhd
│   ├── iir_biquad.vhd
│   └── cic_decim.vhd
├── tb/
│   ├── tb_iir_biquad.vhd
│   └── tb_cic_decim.vhd
└── data/           # gitignored
    ├── iir_vectors.txt
    └── cic_vectors.txt
```

## 범위 밖 (Phase 3 / 8주차)
- Compensation FIR (CIC sinc 응답 평탄화) — Week 5 의 `fir.vhd` 를 generic coef 로 만들고 다른 계수 set 으로 재사용 가능.
- Cascaded biquads (4th-order 이상) — biquad 인스턴스 두 개 cascade.
