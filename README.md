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
- **Interactive Multi-Touch Touchpad**:
  - Full-screen and inline trackpad controller with smooth cursor acceleration and non-blocking HID report queue.
  - Full multi-touch gesture support: 1-finger tap (left click), double-tap drag (drag & drop/select), 2-finger scroll (wheel), 2-finger tap (right click), 3-finger tap (middle click).
  - Tactile Left, Middle, and Right click buttons with haptic feedback.
  - Dedicated edge scroll strip for instant thumb scrolling.
  - Directional D-pad micro-nudging (1px, 5px, 25px, 100px) and automated pattern diagnostics (circle, square, jiggle).
  - Customizable sensitivity, pointer acceleration curves, natural scrolling, and gesture settings.
- **Clean Lifecycle Management**: Safe activation, teardown, and fallback restoration.

## Requirements

- Rooted Android device with a functional `su` binary.
- Linux kernel with USB Gadget ConfigFS enabled (`/config/usb_gadget` or `/sys/kernel/config/usb_gadget`).
- Device controller (UDC) listed under `/sys/class/udc`.
- USB data cable connected to the target host.

## Upstream & Credits

- Original upstream project: [iodn/gadgetfs](https://github.com/iodn/gadgetfs)
- Licensed under the [GPL-3.0 License](LICENSE).
