# LAYR

- [Documentation](https://typst.app/project/wdYNALD1vddLwNFxSPIQmw)

## Init Python Env

```sh
uv sync

# Then either activate virtual env
source ./.venv/bin/activate

# Or prefix everything with uv
```

install pre-commit hooks:

```sh
uv run pre-commit install
```

## Run Tests

```sh
uv run pytest
```

openfpg loader for flashing

## How to FPGA (Vivado)

- synth
- reload in synth design
- set up debug -> disconnect all nets
- set up debug -> connect all nets
- generate bitstream
- hardware manager -> program device
