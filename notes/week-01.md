# Week 1 학습 일지

## 새로 알게 된 것

- VHDL은 `std_logic_vector` 자체로는 산술 연산이 안 되고 `numeric_std`의 `unsigned`/`signed`로 캐스팅해야 한다.
- process 안의 `variable`은 즉시 업데이트되지만 `signal`은 delta cycle 이후 반영된다. testbench의 `expected(a,b,op)` 호출이 signal 값을 읽을 때 왜 `wait for 1 ns` 뒤여야 하는지와 직결.
- GHDL은 기본적으로 assert가 실패해도 exit code 0을 반환한다. `--assert-level=error` 플래그로 exit code에 반영시킬 수 있다 (Makefile 참고).

## 막힌 지점 / 디버깅

- (실제 작업 중 기록)

## 다음 주 예열

- FSM/순차 회로 진입. clock·reset 처리 패턴 미리 한 번 읽어보기.
