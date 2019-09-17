# Support for Digilent Cora Z7-10

The board
[Digilent Cora Z7-10](https://store.digilentinc.com/cora-z7-zynq-7000-single-core-and-dual-core-options-for-arm-fpga-soc-development/)
is based on the chip XC7Z010-1CLG400C. So it is similar to
[Digilent Zybo Z7-10](https://store.digilentinc.com/zybo-z7-zynq-7000-arm-fpga-soc-development-board/).

Hence, the support for Cora Z7-10 has been produced from the support for Zybo.
There have been solved the following problems.

## Cora Z7-10 and Zybo differ in the on-board hardware they have.

So it was necessary to replace *.xdc files.

## The program `platform/axi/processimage` won't run on Cora Z7-10

For some reason `processimage` as provided in the repository won't run on
Cora Z7-10. But it runs if recompiled with `arm-linux-gnueabihf-gcc`:

    arm-linux-gnueabihf-gcc -std=c99  ../axi/processimage.c -o processimage

## The driver `/dev/xdevcfg` is broken

Strictly speaking, this is not a problem with Rigel! This is a problem related
to the pre-build image of Petalinux 2017.4 provided by

<https://github.com/Digilent/Petalinux-Cora-Z7-10>

It seems that this distribution contains the Linux kernel 2017.3, in which
the dirver `/dev/xdevcfg` doesn't work.

So I followed the advice
<https://forum.digilentinc.com/topic/8796-devxdevcfg-broken-for-pre-built-artyz7-20-petalinux-images/>
and replaced the kernel by specifying for "Remote linux-kernel"

* **git URL:** `git://github.com/xilinx/linux-xlnx.git;protocol=https`
* **git TAG/Commit ID:** `xilinx-v2017.4`

Then I rebuilt the project (according to the instructions in Digilent/Petalinux-Cora-Z7-10/README.md).

Now `/dev/xdevcfg` works as expected.

## Specifying a static IP-address

Run

    config-petalinux

Select

    Subsystem AUTO Hardware Settings --> Ethernet Settings

and specify

    (192.168.1.10) Static IP address
    (255.255.255.0) Static IP netmask
    (192.168.1.1) Static IP gateway

Run

    petalinux-build

## Generating a persistent ssh key



* Create a petalinux application `modify-rootfs` with template `install`.

        petalinux-create -t apps --template install --name modify-rootfs

* Copy the file `dropbear_rsa_host_key` into the folder
 `project-spec/meta-user/recipes-apps/modify-rootfs/files/`.

* Edit the file `modify-rootfs.bb`:

```
#
# This file is the modify-rootfs recipe.
#

SUMMARY = "Simple modify-rootfs application"
SECTION = "PETALINUX/apps"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

#SRC_URI = "file://modify-rootfs \
#	"
SRC_URI = "file://dropbear_rsa_host_key \
	"

S = "${WORKDIR}"

do_install() {
    install -d ${D}/etc ${D}/etc/dropbear 
    install -m 0755 ${S}/dropbear_rsa_host_key ${D}/etc/dropbear
}
```

Enable the application by running

    petalinux-config -c rootfs

And then
```
petalinux-build -c modify-rootfs
petalinux-build
```

You may test the result with QEmu:

    petalinux-boot --qemu --image images/linux/zImage

