WORK_DIR=$(shell pwd)
TOP=top
TAG=top-run

PDK_ROOT ?= $(WORK_DIR)/../../pdk
PDK = ihp-sg13g2

.PHONY: librelane
librelane:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag $(TAG) --overwrite config.yaml

.PHONY: librelane-to-sealring
librelane-to-sealring:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag $(TAG)_to_sealring --to KLayout.SealRing  --overwrite config.yaml

.PHONY: view-results
view-results:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --last-run --flow OpenInOpenROAD config.yaml

.PHONY: librelane-from-sealring
librelane-from-sealring:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag $(TAG)_from_sealring --with-initial-state runs/$(TAG)_to_sealring/63-klayout-sealring/state_out.json --from Magic.Filler --overwrite config.yaml

.PHONY: view-results-klayout
view-results-klayout:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --last-run --flow OpenInKlayout config.yaml

.PHONY: magic
magic:
	magic -T /Users/janschaible/git/layer/layr/pdk/ihp-sg13g2/libs.tech/magic/ihp-sg13g2.tech runs/top-run/final/gds/top.gds