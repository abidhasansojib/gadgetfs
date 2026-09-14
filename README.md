# GadgetFS

An open-source ConfigFS USB gadget manager for rooted Android devices to configure and activate USB HID gadget roles.

> [!NOTE]
> **Fork Notice**: This repository is a fork of the original [iodn/gadgetfs](https://github.com/iodn/gadgetfs).
> It includes custom adaptations for devices where `/dev/hidg0` is reserved, remapping the HID keyboard to `/dev/hidg1` and mouse to `/dev/hidg2`, along with automatic node permission handling (`chmod 666`).

## Features

- **ConfigFS Gadget Provisioning**: Dynamically provision USB HID devices directly on Android.
- **Role Profiles**: Configure Keyboard, Mouse, or Composite (Keyboard + Mouse) profiles.
- **Custom Hardware Mapping**:
  - **Composite**: Keyboard on `/dev/hidg1`, Mouse on `/dev/hidg2`
  - **Single Role**: Keyboard or Mouse on `/dev/hidg1`
  - Automatic `chmod 666 /dev/hidg*` node permission configuration.
- **Descriptor Customization**: Customize VID/PID, product strings, manufacturer, and power attributes.
- **Diagnostics & Testing**: Quick tests for keyboard keys, mouse movement, and status verification.
- **Clean Lifecycle Management**: Safe activation, teardown, and fallback restoration.

## Requirements

- Rooted Android device with a functional `su` binary.
- Linux kernel with USB Gadget ConfigFS enabled (`/config/usb_gadget` or `/sys/kernel/config/usb_gadget`).
- Device controller (UDC) listed under `/sys/class/udc`.
- USB data cable connected to the target host.

## Upstream & Credits

- Original upstream project: [iodn/gadgetfs](https://github.com/iodn/gadgetfs)
- Licensed under the [GPL-3.0 License](LICENSE).
