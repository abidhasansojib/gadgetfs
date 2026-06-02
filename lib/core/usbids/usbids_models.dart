class UsbVendor {
  final int vid;
  final String name;

  const UsbVendor({required this.vid, required this.name});
}

class UsbProduct {
  final int vid;
  final int pid;
  final String name;

  const UsbProduct({required this.vid, required this.pid, required this.name});
}

class UsbProductHit {
  final int vid;
  final int pid;
  final String vendorName;
  final String productName;

  const UsbProductHit({
    required this.vid,
    required this.pid,
    required this.vendorName,
    required this.productName,
  });
}
