# Week 1 — 조합 논리와 VHDL 기본 문법

## 모듈

| 모듈 | 파일 | 설명 |
|---|---|---|
| `alu` | `rtl/alu.vhd` | 4-bit ALU (ADD/SUB/AND/OR/XOR/SHL/SHR) |
| `mux4` | `rtl/mux4.vhd` | 파라미터화된 4-to-1 mux |
| `priority_encoder` | `rtl/priority_encoder.vhd` | 8-to-3 priority encoder (valid 플래그 포함) |

## 검증

모든 모듈은 exhaustive testbench로 검증된다:
- ALU: 7 op × 16 × 16 = 1,792 케이스
- mux4: 4 케이스 (sel 값 전부)
- priority_encoder: 256 케이스 (8-bit 입력 전부)

실행:
```
make test
```

파형:
```
make wave MODULE=alu
```

## 배운 것

- `entity` / `architecture` / `generic` / `port`
- `std_logic_vector` ↔ `unsigned`/`signed` 변환 (numeric_std)
- 조합 회로 기술 2가지: selected signal assignment (`with-select`) vs process + case
- `assert ... severity error` + GHDL `--assert-level=error`로 testbench 실패를 exit code에 반영
