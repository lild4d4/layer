WORK_DIR=$(shell pwd)
TOP=controller
TAG=controller-run

PDK_ROOT ?= $(WORK_DIR)/../../pdk
PDK = ihp-sg13g2

.PHONY: librelane
librelane:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag $(TAG) --overwrite config.yaml
	cp -r runs/$(TAG)/final final

.PHONY: view-results
view-results:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --last-run --flow OpenInOpenROAD config.yaml