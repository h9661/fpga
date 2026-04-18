# Week 1 학습 일지

## 새로 알게 된 것

- VHDL은 `std_logic_vector` 자체로는 산술 연산이 안 되고 `numeric_std`의 `unsigned`/`signed`로 캐스팅해야 한다.
- process 안의 `variable`은 즉시 업데이트되지만 `signal`은 delta cycle 이후 반영된다. testbench의 `expected(a,b,op)` 호출이 signal 값을 읽을 때 왜 `wait for 1 ns` 뒤여야 하는지와 직결.
- GHDL은 기본적으로 assert가 실패해도 exit code 0을 반환한다. `--assert-level=error` 플래그로 exit code에 반영시킬 수 있다 (Makefile 참고).

## 막힌 지점 / 디버깅

### 실제 마주친 이슈
- Task 0: macOS Gatekeeper 격리로 ghdl 실행 불가 → `xattr -dr com.apple.quarantine`으로 격리 속성 해제.
- Task 1: 플랜의 `return (others => 'X');`가 GHDL-2008 unconstrained return type 에러 → `return "XXXX";`로 수정.

### 자가 체크 (4문항)

**Q1. entity/architecture 분리 이유?**
A1. entity는 외부에서 보이는 포트 인터페이스(입출력 핀)만 정의하고, architecture는 실제 동작 구현을 담는다. 이렇게 분리하면 같은 entity에 대해 behavioral/structural 등 여러 architecture를 교체해 가며 재사용할 수 있다.

**Q2. std_logic_vector vs unsigned?**
A2. `std_logic_vector`는 단순한 비트 배열로 산술 연산(+, -, 비교)을 지원하지 않는다. `numeric_std`의 `unsigned`/`signed`는 숫자 해석을 포함하므로 산술 연산이 가능하며, 연산 후 결과를 다시 `std_logic_vector`로 캐스팅해 출력에 연결한다.

**Q3. testbench `wait for 1 ns` 이유?**
A3. VHDL에서 신호(signal) 대입은 즉시 반영되지 않고 delta cycle 이후에 실제 값이 확정된다. `wait for 1 ns`를 넣으면 시뮬레이터가 delta cycle을 모두 처리한 뒤 안정된 값을 읽게 되어, 입력 변경 직후 출력 값을 올바르게 검증할 수 있다.

**Q4. `make test` 실패 시 exit 1?**
A4. GHDL은 기본적으로 `report ... severity failure`가 발생해도 exit code 0을 반환한다. `--assert-level=error` 플래그를 주면 error/failure severity의 assertion 발생 시 exit code 1을 반환하도록 바뀐다. Makefile이 이 플래그를 사용하므로 `make test`가 실패 시 셸 레벨에서 에러를 전파할 수 있다.

## 다음 주 예열

- FSM/순차 회로 진입. clock·reset 처리 패턴 미리 한 번 읽어보기.
