# mobile-nixos-flake

this is confirmed to work with [binfmt](https://nixos.wiki/wiki/NixOS_on_ARM#Compiling_through_binfmt_QEMU) compilation.

## build full-disk-image

```
$ nix build .#pinephone-disk-image
```

## build and flash full-disk-image

Preconditions:
- Tow-Boot installed
- Booted into usb-storage-mode

```
$ nix run .#flash-pinephone
```

## build boot-partition

```
$ nix build .#pinephone-boot-partition
```

## build and flash boot-partition

Preconditions:
- Tow-Boot installed
- Booted into usb-storage-mode

```
$ nix run .#flash-pinephone-boot
```

## build and run vm

```
$ nix build .#pinephone-vm && ./result -smp 2
```
