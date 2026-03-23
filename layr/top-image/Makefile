export IMAGE_PATH=qr.png
export CELLNAME=rickroll
export GDS_PATH=gds/rickroll.gds

export PDK_ROOT=../pdk
export PDK=ihp-sg13g2

export CHIP_GDS=../layr/Chip/runs/top-run_to_sealring/63-klayout-sealring/top.gds
export CHIP_GDS_WITH_LOGO=../layr/Chip/runs/top-run_to_sealring/63-klayout-sealring/top.gds

.PHONY: img2gds
img2gds:
	python scripts/img2gds.py --cellname $(CELLNAME) --invert --layer 134 --scale 0.3 --pixel-size 2 $(IMAGE_PATH) $(GDS_PATH)

.PHONY: drc
drc:
	python $(PDK_ROOT)/$(PDK)/libs.tech/klayout/tech/drc/run_drc.py --run_dir drc/ --no_density --path $(GDS_PATH)

.PHONY: klayout
klayout:
	KLAYOUT_HOME=$(PDK_ROOT)/$(PDK)/libs.tech/klayout/ klayout -e $(GDS_PATH)

.PHONY: insert_img
insert_img:
	python scripts/insert_img.py $(CHIP_GDS) $(GDS_PATH) $(CHIP_GDS_WITH_LOGO) 450 450 $(CELLNAME)

.PHONY: klayout-final
klayout-final:
	KLAYOUT_HOME=$(PDK_ROOT)/$(PDK)/libs.tech/klayout/ klayout -e $(CHIP_GDS_WITH_LOGO)
