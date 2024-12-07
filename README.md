# Bootable ISO Builder from Dockerfile

This repository is based on the guide ["How to generate a bootable ISO from a Docker image"](https://medium.com/@agustin_29997/how-to-generate-a-bootable-iso-from-a-docker-image-1a323e5a0f43) by Agustin Chiappe Berrini. The guide provides a detailed walkthrough on how to convert a Docker image into a bootable ISO. This repository implements the process outlined in the guide and automates it through a set of Bash scripts.

The goal of this repository is to create a custom bootable Linux ISO from a Dockerfile, which includes building an initramfs and optionally a custom kernel, then packaging everything into an ISO image automatically, using a similar process.

## Requirements

Before running the scripts, ensure that you have the following packages (names based on Debian (6.8.11-1kali2)):

- `docker-ce`: Docker Community Edition for building and running containers.
- `docker-ce-cli`: Docker command-line interface to interact with Docker containers.
- `xorriso`: Tool for creating ISO 9660 filesystem images.
- `bison`: A parser generator, required for building the kernel from scratch.
- `bc`: A command-line calculator, also required for building the kernel.
- `libelf-dev`: Library for handling ELF (Executable and Linkable Format) files, needed for kernel building.
- `qemu-system`: Emulator for testing the bootable ISO in a virtual environment.

## Overview of Scripts

The main script, `build_bootable_iso.sh`, automates the process of converting a Dockerfile into a bootable ISO image. Here's an overview of the other scripts referenced by the main script:

### `build_kernel.sh`
This script is responsible for building the Linux kernel from scratch. If you choose to build a custom kernel (via the `--build-kernel` flag), this script will compile the kernel using the required tools.

### `build_initramfs.sh`
This script takes the provided Dockerfile and builds an initramfs (initial RAM filesystem) from it. The initramfs contains the necessary files to boot the system, including libraries, binaries, and configuration files.

### `test_initramfs_file.sh`
Once the initramfs is built, this script tests it to ensure it is correctly formatted and can be used for booting the system.

### `build_iso.sh`
This script assembles the final bootable ISO by combining the kernel (`bzImage`) and initramfs (`initramfs.cpio.gz`). It can output the ISO to a specified path or use a default location (`bootable.iso`).

## Usage

To use the main script, simply run it with the path to your Dockerfile:

```bash
sudo ./build_bootable_iso.sh <Dockerfile_path> [options]
```

### Options:
- `<Dockerfile_path>`: The path to the Dockerfile you want to use to build the initramfs.
- `-o <ISO_output_path>`: (Optional) The path where the bootable ISO will be saved. Default is `bootable.iso` in the current directory.
- `--build-kernel`: (Optional) Build the kernel from scratch. This requires the necessary dependencies for kernel compilation.
- `-h`, `--help`: Display help information.

### Example:
```bash
sudo ./build_bootable_iso.sh /path/to/Dockerfile -o /path/to/output.iso --build-kernel
```
This will build the kernel, create an initramfs from the Dockerfile, and generate a bootable ISO at `/path/to/output.iso`.

### Issues and Contributions:

If you find any bugs or have suggestions for improvements, feel free to open an issue or submit a pull request. Contributions are always welcome!

- **Issues**: Open a new issue in the [Issues tab](https://github.com/KunoVonHagen/docker-to-iso/issues).
- **Pull Requests**: If you have improvements or fixes, please create a pull request. Make sure to explain the changes clearly.



