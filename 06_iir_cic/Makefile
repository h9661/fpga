MODULES := iir_biquad cic_decim

PYTHON := ../.venv/bin/python

DATA_FILES := data/iir_vectors.txt data/cic_vectors.txt

data:
	mkdir -p data

data/iir_vectors.txt: scripts/gen_iir_cic_data.py | data
	$(PYTHON) $< iir $@

data/cic_vectors.txt: scripts/gen_iir_cic_data.py | data
	$(PYTHON) $< cic $@

analyze: $(DATA_FILES)

include ../common/Makefile.common

.PHONY: clean-data
clean: clean-data
clean-data:
	rm -rf data
