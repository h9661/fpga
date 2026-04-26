MODULES := fir

PYTHON := ../.venv/bin/python

DATA_FILES := data/fir_vectors.txt

data:
	mkdir -p data

data/fir_vectors.txt: scripts/gen_fir_data.py | data
	$(PYTHON) $< $@

analyze: $(DATA_FILES)

include ../common/Makefile.common

.PHONY: clean-data
clean: clean-data
clean-data:
	rm -rf data
