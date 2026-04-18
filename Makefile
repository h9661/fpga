# 모든 주차 폴더에 make test 전파

WEEKS := $(sort $(wildcard [0-9][0-9]_*))

.PHONY: all test clean

all: test

test:
	@set -e; \
	for w in $(WEEKS); do \
		echo ">>> Week: $$w"; \
		$(MAKE) -C $$w test; \
	done; \
	echo "=== ALL WEEKS PASSED ==="

clean:
	@for w in $(WEEKS); do \
		$(MAKE) -C $$w clean; \
	done
