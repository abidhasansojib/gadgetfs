import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/gadget_profile.dart';
import '../../core/storage/providers.dart';
import '../../shared/widgets/section_card.dart';

import '../../core/usbids/usbids_models.dart';
import '../../core/usbids/usbids_providers.dart';
import '../../core/usbids/usbids_repository.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  final String? profileId;
  const ProfileEditScreen({super.key, this.profileId});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

enum _UsbIdentityMode { manual, usbIdsDb }

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  int _step = 0;
  late GadgetProfile _draft;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _vidCtrl = TextEditingController();
  final _pidCtrl = TextEditingController();
  final _manuCtrl = TextEditingController();
  final _prodCtrl = TextEditingController();
  final _snCtrl = TextEditingController();

  bool _loaded = false;

  // DB mode state
  _UsbIdentityMode _mode = _UsbIdentityMode.manual;
  bool _fillStringsFromDb = true;

  UsbVendor? _selectedVendor;
  UsbProduct? _selectedProduct;
  UsbProductHit? _selectedGlobalHit;

  // Track manual edits to strings so we don't stomp unexpectedly
  bool _suppressDirty = false;
  bool _manuDirty = false;
  bool _prodDirty = false;
  String? _lastAutoManu;
  String? _lastAutoProd;

  @override
  void initState() {
    super.initState();

    _manuCtrl.addListener(() {
      if (_loaded && !_suppressDirty) _manuDirty = true;
    });
    _prodCtrl.addListener(() {
      if (_loaded && !_suppressDirty) _prodDirty = true;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _vidCtrl.dispose();
    _pidCtrl.dispose();
    _manuCtrl.dispose();
    _prodCtrl.dispose();
    _snCtrl.dispose();
    super.dispose();
  }

  void _setCtrl(TextEditingController ctrl, String v) {
    _suppressDirty = true;
    ctrl.text = v;
    _suppressDirty = false;
  }

  String _toHex4(int v) => '0x${v.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  int? _parseHex4(String s) {
    final t = s.trim().toLowerCase();
    final cleaned = t.startsWith('0x') ? t.substring(2) : t;
    if (cleaned.isEmpty) return null;
    if (!RegExp(r'^[0-9a-f]{1,4}$').hasMatch(cleaned)) return null;
    return int.tryParse(cleaned, radix: 16);
  }

  Future<void> _loadIfNeeded() async {
    if (_loaded) return;
    _loaded = true;

    final profiles = await ref.read(profilesProvider.notifier).future;
    GadgetProfile profile;

    if (widget.profileId != null) {
      profile = profiles.firstWhere(
        (p) => p.id == widget.profileId,
        orElse: () => GadgetProfile.create(name: 'New Profile', roleType: GadgetRoleType.mouse),
      );
    } else {
      profile = GadgetProfile.create(name: 'New Profile', roleType: GadgetRoleType.mouse);
    }

    _draft = profile;

    _setCtrl(_nameCtrl, profile.name);
    _setCtrl(_descCtrl, profile.description);
    _setCtrl(_vidCtrl, _toHex4(profile.vendorId));
    _setCtrl(_pidCtrl, _toHex4(profile.productId));
    _setCtrl(_manuCtrl, profile.manufacturer);
    _setCtrl(_prodCtrl, profile.product);
    _setCtrl(_snCtrl, profile.serialNumber);

    _manuDirty = false;
    _prodDirty = false;

    if (mounted) setState(() {});
  }

  void _applyDbSelection({
    required int vid,
    required int pid,
    String? vendorName,
    String? productName,
  }) {
    _setCtrl(_vidCtrl, _toHex4(vid));
    _setCtrl(_pidCtrl, _toHex4(pid));

    if (_fillStringsFromDb) {
      // Overwrite only if the user hasn't meaningfully changed it,
      // or if it's empty, or if it still equals last autofill value.
      final currentManu = _manuCtrl.text.trim();
      final currentProd = _prodCtrl.text.trim();

      final canOverwriteManu =
          !_manuDirty || currentManu.isEmpty || (_lastAutoManu != null && currentManu == _lastAutoManu);
      final canOverwriteProd =
          !_prodDirty || currentProd.isEmpty || (_lastAutoProd != null && currentProd == _lastAutoProd);

      _suppressDirty = true;

      if (vendorName != null && vendorName.trim().isNotEmpty && canOverwriteManu) {
        _manuCtrl.text = vendorName.trim();
        _lastAutoManu = vendorName.trim();
      }
      if (productName != null && productName.trim().isNotEmpty && canOverwriteProd) {
        _prodCtrl.text = productName.trim();
        _lastAutoProd = productName.trim();
      }

      _suppressDirty = false;
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }

    final vid = _parseHex4(_vidCtrl.text) ?? 0x1d6b;
    final pid = _parseHex4(_pidCtrl.text) ?? 0x0104;

    final next = _draft.copyWith(
      name: name,
      description: _descCtrl.text.trim(),
      vendorId: vid,
      productId: pid,
      manufacturer: _manuCtrl.text.trim().isEmpty ? 'GadgetFS' : _manuCtrl.text.trim(),
      product: _prodCtrl.text.trim().isEmpty ? 'Gadget' : _prodCtrl.text.trim(),
      serialNumber: _snCtrl.text.trim().isEmpty ? '0001' : _snCtrl.text.trim(),
    );

    await ref.read(profilesProvider.notifier).upsert(next);
    await ref.read(selectedProfileIdProvider.notifier).setSelected(next.id);

    if (context.mounted) {
      context.go('/');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
    }
  }

  Future<UsbVendor?> _pickVendor(BuildContext context) async {
    final repo = ref.read(usbIdsRepositoryProvider);
    return showModalBottomSheet<UsbVendor>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _VendorPickerSheet(repo: repo),
    );
  }

  Future<UsbProduct?> _pickProductForVendor(BuildContext context, int vid, String vendorName) async {
    final repo = ref.read(usbIdsRepositoryProvider);
    return showModalBottomSheet<UsbProduct>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _VendorProductPickerSheet(repo: repo, vid: vid, vendorName: vendorName),
    );
  }

  Future<UsbProductHit?> _pickProductGlobal(BuildContext context) async {
    final repo = ref.read(usbIdsRepositoryProvider);
    return showModalBottomSheet<UsbProductHit>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GlobalProductPickerSheet(repo: repo),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(profilesProvider, (_, __) {});
    _loadIfNeeded();

    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final repo = ref.read(usbIdsRepositoryProvider);

    final vidInt = _parseHex4(_vidCtrl.text);
    final pidInt = _parseHex4(_pidCtrl.text);

    final dbSummary = (vidInt != null && pidInt != null)
        ? 'VID 0x${repo.fmtVidHex(vidInt)}  •  PID 0x${repo.fmtPidHex(pidInt)}'
        : 'VID/PID not set';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profileId == null ? 'New profile' : 'Edit profile'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Stepper(
          currentStep: _step,
          onStepContinue: () {
            if (_step < 2) {
              setState(() => _step++);
            } else {
              _save();
            }
          },
          onStepCancel: () {
            if (_step > 0) {
              setState(() => _step--);
            } else {
              context.pop();
            }
          },
          steps: [
            Step(
              title: const Text('Role'),
              isActive: _step >= 0,
              content: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Choose a gadget role', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _RoleRadio(
                      value: GadgetRoleType.mouse,
                      groupValue: _draft.roleType,
                      title: 'Mouse',
                      subtitle: 'Relative mouse movement + buttons',
                      icon: Icons.mouse_outlined,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(roleType: v)),
                    ),
                    _RoleRadio(
                      value: GadgetRoleType.keyboard,
                      groupValue: _draft.roleType,
                      title: 'Keyboard',
                      subtitle: 'USB HID keyboard (boot protocol)',
                      icon: Icons.keyboard_outlined,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(roleType: v)),
                    ),
                    _RoleRadio(
                      value: GadgetRoleType.composite,
                      groupValue: _draft.roleType,
                      title: 'Composite',
                      subtitle: 'Keyboard + mouse (single USB device)',
                      icon: Icons.usb_outlined,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(roleType: v)),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: _draft.activateOnOpen,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(activateOnOpen: v)),
                      title: const Text('Activate on open'),
                      subtitle: const Text('Attempts to activate this profile when the app opens (default OFF).'),
                    ),
                  ],
                ),
              ),
            ),
            Step(
              title: const Text('Basics'),
              isActive: _step >= 1,
              content: SectionCard(
                child: Column(
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            Step(
              title: const Text('USB identity'),
              isActive: _step >= 2,
              content: Column(
                children: [
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('USB identity source', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        SegmentedButton<_UsbIdentityMode>(
                          segments: const [
                            ButtonSegment(
                              value: _UsbIdentityMode.manual,
                              label: Text('Manual'),
                              icon: Icon(Icons.edit_outlined),
                            ),
                            ButtonSegment(
                              value: _UsbIdentityMode.usbIdsDb,
                              label: Text('USB IDs DB'),
                              icon: Icon(Icons.search_outlined),
                            ),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (s) => setState(() => _mode = s.first),
                        ),
                        const SizedBox(height: 14),

                        if (_mode == _UsbIdentityMode.usbIdsDb) ...[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.info_outline, size: 18),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Search by vendor/product name. When you pick a product, VID/PID are filled automatically.',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Fill Manufacturer/Product strings from DB'),
                                    subtitle: const Text('You can edit them afterwards.'),
                                    value: _fillStringsFromDb,
                                    onChanged: (v) => setState(() => _fillStringsFromDb = v),
                                  ),

                                  const Divider(height: 18),

                                  // Vendor selection
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Vendor'),
                                    subtitle: Text(
                                      _selectedVendor?.name ?? 'Type vendor name and select from DB',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: FilledButton.tonalIcon(
                                      onPressed: () async {
                                        final v = await _pickVendor(context);
                                        if (v == null) return;

                                        setState(() {
                                          _selectedVendor = v;
                                          _selectedProduct = null;
                                          _selectedGlobalHit = null;
                                        });

                                        // Vendor selection alone does not set PID; it sets VID if we want.
                                        _applyDbSelection(
                                          vid: v.vid,
                                          pid: pidInt ?? 0x0104,
                                          vendorName: v.name,
                                          productName: _selectedProduct?.name,
                                        );
                                      },
                                      icon: const Icon(Icons.manage_search),
                                      label: Text(_selectedVendor == null ? 'Find' : 'Change'),
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // Product selection (vendor-scoped)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Product (for vendor)'),
                                    subtitle: Text(
                                      _selectedProduct?.name ??
                                          (_selectedVendor == null
                                              ? 'Select a vendor first'
                                              : 'Pick one of the vendor products'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: FilledButton.tonalIcon(
                                      onPressed: (_selectedVendor == null)
                                          ? null
                                          : () async {
                                              final v = _selectedVendor!;
                                              final p = await _pickProductForVendor(context, v.vid, v.name);
                                              if (p == null) return;

                                              setState(() {
                                                _selectedProduct = p;
                                                _selectedGlobalHit = null;
                                              });

                                              _applyDbSelection(
                                                vid: p.vid,
                                                pid: p.pid,
                                                vendorName: v.name,
                                                productName: p.name,
                                              );
                                            },
                                      icon: const Icon(Icons.manage_search),
                                      label: const Text('Pick'),
                                    ),
                                  ),

                                  const SizedBox(height: 6),

                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () async {
                                        final hit = await _pickProductGlobal(context);
                                        if (hit == null) return;

                                        setState(() {
                                          _selectedGlobalHit = hit;
                                          _selectedVendor = UsbVendor(vid: hit.vid, name: hit.vendorName);
                                          _selectedProduct = UsbProduct(vid: hit.vid, pid: hit.pid, name: hit.productName);
                                        });

                                        _applyDbSelection(
                                          vid: hit.vid,
                                          pid: hit.pid,
                                          vendorName: hit.vendorName,
                                          productName: hit.productName,
                                        );
                                      },
                                      icon: const Icon(Icons.travel_explore),
                                      label: const Text('Or search product by name (any vendor)'),
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  // Show resulting VID/PID (read-only)
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Chip(
                                        avatar: const Icon(Icons.confirmation_number_outlined, size: 18),
                                        label: Text(dbSummary),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          // Switch to manual but keep current values.
                                          setState(() => _mode = _UsbIdentityMode.manual);
                                        },
                                        child: const Text('Edit VID/PID manually'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ] else ...[
                          // Manual mode: direct VID/PID edit
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _vidCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Vendor ID (hex)',
                                    hintText: '0x1D6B',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _pidCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Product ID (hex)',
                                    hintText: '0x0104',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Always editable identity strings
                        TextField(
                          controller: _manuCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Manufacturer',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _prodCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Product',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _snCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Serial number',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Advanced note: Some devices require specific VID/PID values or additional kernel configs. '
                        'If activation fails, review the Logs screen and ensure configfs is available and UDC is detected.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------
// Vendor picker: type vendor name, select vendor
// ---------------------------

class _VendorPickerSheet extends StatefulWidget {
  const _VendorPickerSheet({required this.repo});

  final UsbIdsRepository repo;

  @override
  State<_VendorPickerSheet> createState() => _VendorPickerSheetState();
}

class _VendorPickerSheetState extends State<_VendorPickerSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  Future<List<UsbVendor>>? _future;

  @override
  void initState() {
    super.initState();
    _future = Future.value(const []);
    _ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      final q = _ctrl.text.trim();
      setState(() {
        _future = q.isEmpty ? Future.value(const []) : widget.repo.searchVendors(q);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.55,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Material(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Find vendor', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Type vendor name (or VID)',
                    border: const OutlineInputBorder(),
                    suffixIcon: _ctrl.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _ctrl.clear();
                              setState(() => _future = Future.value(const []));
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<UsbVendor>>(
                  future: _future,
                  builder: (context, snap) {
                    final items = snap.data;
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (items == null || items.isEmpty) {
                      return const Center(child: Text('Type to search vendors.'));
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final v = items[i];
                        final vidHex = widget.repo.fmtVidHex(v.vid);
                        return ListTile(
                          leading: CircleAvatar(child: Text(vidHex.substring(0, 2))),
                          title: Text(v.name),
                          subtitle: Text('VID 0x$vidHex  •  ${v.vid}'),
                          onTap: () => Navigator.pop(context, v),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------
// Product picker scoped to vendor: type product name, pick one -> returns pid
// ---------------------------

class _VendorProductPickerSheet extends StatefulWidget {
  const _VendorProductPickerSheet({
    required this.repo,
    required this.vid,
    required this.vendorName,
  });

  final UsbIdsRepository repo;
  final int vid;
  final String vendorName;

  @override
  State<_VendorProductPickerSheet> createState() => _VendorProductPickerSheetState();
}

class _VendorProductPickerSheetState extends State<_VendorProductPickerSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  Future<List<UsbProduct>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.searchProductsForVendor(vid: widget.vid, query: '');
    _ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      setState(() {
        _future = widget.repo.searchProductsForVendor(vid: widget.vid, query: _ctrl.text.trim());
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final vidHex = widget.repo.fmtVidHex(widget.vid);

    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.55,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Material(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Find product', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    const Icon(Icons.factory_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.vendorName}  •  VID 0x$vidHex',
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Type product name (or PID)',
                    border: const OutlineInputBorder(),
                    suffixIcon: _ctrl.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _ctrl.clear();
                              setState(() => _future = widget.repo.searchProductsForVendor(vid: widget.vid, query: ''));
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<UsbProduct>>(
                  future: _future,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snap.data!;
                    if (items.isEmpty) {
                      return const Center(child: Text('No products found.'));
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final prod = items[i];
                        final pidHex = widget.repo.fmtPidHex(prod.pid);
                        return ListTile(
                          leading: CircleAvatar(child: Text(pidHex.substring(0, 2))),
                          title: Text(prod.name),
                          subtitle: Text('PID 0x$pidHex  •  ${prod.pid}'),
                          onTap: () => Navigator.pop(context, prod),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------
// Global product search: type product name -> select result -> fills vendor+vid/pid
// ---------------------------

class _GlobalProductPickerSheet extends StatefulWidget {
  const _GlobalProductPickerSheet({required this.repo});

  final UsbIdsRepository repo;

  @override
  State<_GlobalProductPickerSheet> createState() => _GlobalProductPickerSheetState();
}

class _GlobalProductPickerSheetState extends State<_GlobalProductPickerSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  Future<List<UsbProductHit>>? _future;

  @override
  void initState() {
    super.initState();
    _future = Future.value(const []);
    _ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      final q = _ctrl.text.trim();
      setState(() {
        _future = q.isEmpty ? Future.value(const []) : widget.repo.searchProductsGlobal(q);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.55,
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Material(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Find product', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Type product name (or VID:PID like 1d6b:0104)',
                    border: const OutlineInputBorder(),
                    suffixIcon: _ctrl.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _ctrl.clear();
                              setState(() => _future = Future.value(const []));
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<UsbProductHit>>(
                  future: _future,
                  builder: (context, snap) {
                    final items = snap.data;
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (items == null || items.isEmpty) {
                      return const Center(child: Text('Type to search products.'));
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final hit = items[i];
                        final vidHex = widget.repo.fmtVidHex(hit.vid);
                        final pidHex = widget.repo.fmtPidHex(hit.pid);
                        return ListTile(
                          leading: const Icon(Icons.usb_outlined),
                          title: Text(hit.productName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${hit.vendorName}  •  VID 0x$vidHex  •  PID 0x$pidHex'),
                          onTap: () => Navigator.pop(context, hit),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoleRadio extends StatelessWidget {
  final GadgetRoleType value;
  final GadgetRoleType groupValue;
  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<GadgetRoleType> onChanged;

  const _RoleRadio({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<GadgetRoleType>(
      value: value,
      groupValue: groupValue,
      onChanged: (v) => v == null ? null : onChanged(v),
      title: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Text(title),
        ],
      ),
      subtitle: Text(subtitle),
    );
  }
}
