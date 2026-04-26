MODULES := mac

# Phase 2 부터 Python 골든 모델 의존. 레포 루트의 venv 사용.
PYTHON := ../.venv/bin/python

# 골든 벡터 — 스크립트가 변하거나 파일이 없으면 재생성.
DATA_FILES := data/mac_vectors.txt

data:
	mkdir -p data

data/mac_vectors.txt: scripts/gen_mac_vectors.py | data
	$(PYTHON) $< $@

# common Makefile 의 analyze 보다 먼저 데이터 생성.
analyze: $(DATA_FILES)

include ../common/Makefile.common

# data 디렉토리도 함께 정리. clean 은 common 에서 정의되었으므로 prerequisite 만 추가.
.PHONY: clean-data
clean: clean-data
clean-data:
	rm -rf data
