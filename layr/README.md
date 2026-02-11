# My-First-Chip-2026

## Setup

### With VSCode devcontainer

#### Dependencies

1. Docker desktop
2. X11 server (for visual tools)

#### Intructions

1. Open this repo in VSCode and then with ```CTRL+SHIFT+P``` open the Command Pallete
![alt text](artifacts/image.png)

2. Once inside the devcontainer you start the librelane nix shell with this command:

```
nix-shell librelane/
```

if you have a error ```... is not owned by current user``` then run this comand first:
```
git config --global --add safe.directory /workspaces/My-First-Chip-DYC26/librelane

```

3. After several minutes everyting is going to be installed and you can run the smoke-test:

```
librelane --smoke-test
```

### With nix shell (locally)

Follow this instructions: [librelane instalation](https://librelane.readthedocs.io/en/stable/installation/nix_installation/index.html)

## Running the examples

### Example 1: Librelane classic flow

1. To run the flow

```
cd examples/librelane-classic
make librelane
```

2. To view the results

```
make view-results
```

### Example 2: Librelane chip flow

1. To run the flow

```
cd examples/librelane-chip
make librelane
```

2. To view the results

```
make view-results
```
