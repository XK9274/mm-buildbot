# Miyoo I2C Tools

This package builds the upstream `i2c-tools` 4.4 command-line utilities with
the Union Miyoo toolchain. The artifact is a floating tool bundle: copy its
`bin/` directory to the device and invoke the binaries directly. It has no
`launch.sh` and is not an Onion app distribution.

The bundle contains `i2cdetect`, `i2cdump`, `i2cget`, `i2cset`, and
`i2ctransfer`. `i2cset` and write-mode `i2ctransfer` can change hardware
state. Broad scans can also perturb devices on a live bus. Use only deliberate,
reviewed commands while the device is otherwise idle.

For read-only AXP223 inspection on this device, use combined transactions on
bus 1 and address `0x34`, for example:

```sh
./i2ctransfer -y 1 w1@0x34 0xb9 r1
```
