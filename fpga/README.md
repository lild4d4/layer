# Installation

The fpga process is based on [f4pga](https://f4pga-examples.readthedocs.io/en/latest/getting.html#getting)

```sh
export F4PGA_INSTALL_DIR=~/opt/f4pga
export FPGA_FAM=xc7

export F4PGA_PACKAGES='install-xc7 xc7a50t_test xc7a100t_test xc7a200t_test xc7z010_test'

mkdir -p $F4PGA_INSTALL_DIR/$FPGA_FAM

export F4PGA_TIMESTAMP='20220920-124259'
export F4PGA_HASH='007d1c1'

for PKG in $F4PGA_PACKAGES; do
  wget -qO- https://storage.googleapis.com/symbiflow-arch-defs/artifacts/prod/foss-fpga-tools/symbiflow-arch-defs/continuous/install/${F4PGA_TIMESTAMP}/symbiflow-arch-defs-${PKG}-${F4PGA_HASH}.tar.xz | tar -xJC $F4PGA_INSTALL_DIR/${FPGA_FAM}
done
```

```sh
conda env create -f environment.yaml

conda activate xc7
```


```sh
make
make download
```