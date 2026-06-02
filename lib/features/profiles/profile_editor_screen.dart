import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/gadget_profile.dart';
import '../../core/models/role_type.dart';
import '../../core/providers/profiles_providers.dart';

import '../../core/usbids/usbids_models.dart';
import '../../core/usbids/usbids_providers.dart';
import '../../core/usbids/usbids_repository.dart';

class ProfileEditorScreen extends ConsumerStatefulWidget {
  const ProfileEditorScreen.create({super.key})
      : mode = _EditorMode.create,
        profileId = null;

  const ProfileEditorScreen.edit({super.key, required this.profileId})
      : mode = _EditorMode.edit;

  final _EditorMode mode;
  final String? profileId;

  @override
  ConsumerState<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

enum _EditorMode { create, edit }

enum UsbIdentitySource { manual, usbIdsDb }

class _ProfileEditorScreenState extends ConsumerState<ProfileEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;

  late String _id;

  String _name = '';
  String _description = '';
  RoleType _roleType = RoleType.mouse;

  String _vendorIdHex = '1D6B';
  String _productIdHex = '0104';

  String _manufacturer = 'KaijinLab';
  String _product = 'GadgetFS';
  String _serial = '0001';

  bool _activateOnOpen = false;
  bool _loaded = false;

  UsbIdentitySource _usbSource = UsbIdentitySource.manual;
  bool _autoFillStringsFromDb = true;

  UsbVendor? _selectedVendor;
  UsbProduct? _selectedProduct;
  UsbProductHit? _selectedGlobalHit;

  bool _manuDirty = false;
  bool _prodDirty = false;
  String? _lastAutoManu;
  String? _lastAutoProd;

  int _stringsRevision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;

    final profiles = ref.read(profilesControllerProvider);

    if (widget.mode == _EditorMode.edit) {
      final p = profiles.firstWhere((e) => e.id == widget.profileId);

      _id = p.id;
      _name = p.name;
      _description = p.description;
      _roleType = p.roleType;

      _vendorIdHex = p.vendorId.toRadixString(16).padLeft(4, '0').toUpperCase();
      _productIdHex = p.productId.toRadixString(16).padLeft(4, '0').toUpperCase();

      _manufacturer = p.manufacturer;
      _product = p.product;
      _serial = p.serialNumber;

      _activateOnOpen = p.activateOnOpen;

      _usbSource = UsbIdentitySource.manual;
    } else {
      _id = const Uuid().v4();
      final p = GadgetProfile.defaults(id: _id);

      _name = p.name;
      _description = p.description;
      _roleType = p.roleType;

      _vendorIdHex = p.vendorId.toRadixString(16).padLeft(4, '0').toUpperCase();
      _productIdHex = p.productId.toRadixString(16).padLeft(4, '0').toUpperCase();

      _manufacturer = p.manufacturer;
      _product = p.product;
      _serial = p.serialNumber;

      _activateOnOpen = p.activateOnOpen;

      _usbSource = UsbIdentitySource.manual;
    }

    _loaded = true;
  }

  int _parseHex(String s) {
    final cleaned = s.trim().toLowerCase().replaceAll('0x', '');
    return int.parse(cleaned, radix: 16);
  }

  bool _isHexUpTo4(String s) {
    final t = s.trim().replaceAll('0x', '');
    return RegExp(r'^[0-9a-fA-F]{1,4}$').hasMatch(t);
  }

  void _applyDbSelection({
    required int vid,
    required int pid,
    String? vendorName,
    String? productName,
  }) {
    final repo = ref.read(usbIdsRepositoryProvider);

    setState(() {
      _vendorIdHex = repo.fmtVidHex(vid);
      _productIdHex = repo.fmtPidHex(pid);

      if (vendorName != null) {
        _selectedVendor = UsbVendor(vid: vid, name: vendorName);
      }
      if (productName != null) {
        _selectedProduct = UsbProduct(vid: vid, pid: pid, name: productName);
      }
    });

    if (_usbSource == UsbIdentitySource.usbIdsDb && _autoFillStringsFromDb) {
      final vName = vendorName?.trim();
      final pName = productName?.trim();

      final currentManu = _manufacturer.trim();
      final currentProd = _product.trim();

      final canOverwriteManu =
          !_manuDirty || currentManu.isEmpty || (_lastAutoManu != null && currentManu == _lastAutoManu);
      final canOverwriteProd =
          !_prodDirty || currentProd.isEmpty || (_lastAutoProd != null && currentProd == _lastAutoProd);

      bool changed = false;

      if (vName != null && vName.isNotEmpty && canOverwriteManu) {
        _manufacturer = vName;
        _lastAutoManu = vName;
        changed = true;
      }
      if (pName != null && pName.isNotEmpty && canOverwriteProd) {
        _product = pName;
        _lastAutoProd = pName;
        changed = true;
      }

      if (changed) {
        setState(() => _stringsRevision++);
      }
    }
  }

  Future<void> _save() async {
    if (_usbSource == UsbIdentitySource.usbIdsDb) {
      final hasPicked = _selectedGlobalHit != null || _selectedProduct != null;
      if (!hasPicked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a product from the USB IDs DB (or switch to Manual).')),
        );
        return;
      }
    }

    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final profile = GadgetProfile(
      id: _id,
      name: _name.trim(),
      description: _description.trim(),
      roleType: _roleType,
      vendorId: _parseHex(_vendorIdHex),
      productId: _parseHex(_productIdHex),
      manufacturer: _manufacturer.trim(),
      product: _product.trim(),
      serialNumber: _serial.trim(),
      activateOnOpen: _activateOnOpen,
    );

    await ref.read(profilesControllerProvider.notifier).upsert(profile);
    await ref.read(selectedProfileIdProvider.notifier).set(profile.id);

    if (!mounted) return;
    context.pop();
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
    final title = widget.mode == _EditorMode.edit ? 'Edit profile' : 'Create profile';
    final repo = ref.read(usbIdsRepositoryProvider);

    final vidOk = _isHexUpTo4(_vendorIdHex);
    final pidOk = _isHexUpTo4(_productIdHex);
    final vidInt = vidOk ? _parseHex(_vendorIdHex) : null;
    final pidInt = pidOk ? _parseHex(_productIdHex) : null;

    final dbSummary = (vidInt != null && pidInt != null)
        ? 'VID 0x${repo.fmtVidHex(vidInt)}  •  PID 0x${repo.fmtPidHex(pidInt)}'
        : 'VID/PID not set';

    final vendorLabel = _selectedVendor?.name ?? 'Type vendor name and select';
    final productLabel = _selectedProduct?.name ?? 'Pick a product for the vendor';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _step,
          onStepCancel: _step == 0 ? null : () => setState(() => _step -= 1),
          onStepContinue: () {
            if (_step < 2) {
              setState(() => _step += 1);
            } else {
              _save();
            }
          },
          controlsBuilder: (context, details) {
            final isLast = _step == 2;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  FilledButton(
                    onPressed: details.onStepContinue,
                    child: Text(isLast ? 'Save' : 'Continue'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Back'),
                  ),
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Basics'),
              isActive: _step >= 0,
              content: Column(
                children: [
                  TextFormField(
                    initialValue: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                    onSaved: (v) => _name = v ?? '',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: _description,
                    decoration: const InputDecoration(labelText: 'Description (optional)'),
                    maxLines: 2,
                    onSaved: (v) => _description = v ?? '',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<RoleType>(
                    value: _roleType,
                    decoration: const InputDecoration(labelText: 'Role type'),
                    items: RoleType.values
                        .map((e) => DropdownMenuItem<RoleType>(
                              value: e,
                              child: Text(e.label),
                            ))
                        .toList(growable: false),
                    onChanged: (v) => setState(() {
                      _roleType = v ?? RoleType.mouse;
                      if (_product.trim().isEmpty || _product == 'Gadget') {
                        _product = _roleType.label;
                        _stringsRevision++;
                      }
                    }),
                    onSaved: (v) => _roleType = v ?? _roleType,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Activate on open'),
                    subtitle: const Text('When enabled, the app will attempt to activate this profile when it starts.'),
                    value: _activateOnOpen,
                    onChanged: (v) => setState(() => _activateOnOpen = v),
                  ),
                ],
              ),
            ),
            Step(
              title: const Text('USB identity'),
              isActive: _step >= 1,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose how you want to define the USB identity.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<UsbIdentitySource>(
                    segments: const [
                      ButtonSegment(
                        value: UsbIdentitySource.manual,
                        label: Text('Manual'),
                        icon: Icon(Icons.edit_outlined),
                      ),
                      ButtonSegment(
                        value: UsbIdentitySource.usbIdsDb,
                        label: Text('USB IDs DB'),
                        icon: Icon(Icons.search_outlined),
                      ),
                    ],
                    selected: {_usbSource},
                    onSelectionChanged: (s) {
                      setState(() => _usbSource = s.first);
                    },
                  ),
                  const SizedBox(height: 14),

                  if (_usbSource == UsbIdentitySource.usbIdsDb) ...[
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
                                    'Search by vendor/product name. Picking a product fills VID/PID automatically.',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Fill Manufacturer/Product strings from DB'),
                              subtitle: const Text('You can edit them afterwards.'),
                              value: _autoFillStringsFromDb,
                              onChanged: (v) => setState(() => _autoFillStringsFromDb = v),
                            ),
                            const Divider(height: 18),

                            // Vendor selection
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Vendor'),
                              subtitle: Text(
                                vendorLabel,
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

                                  // Vendor selection alone sets VID, keeps PID as-is (until product is chosen).
                                  final keepPid = pidInt ?? 0x0104;
                                  _applyDbSelection(
                                    vid: v.vid,
                                    pid: keepPid,
                                    vendorName: v.name,
                                    productName: _selectedProduct?.name,
                                  );
                                },
                                icon: const Icon(Icons.manage_search),
                                label: Text(_selectedVendor == null ? 'Find' : 'Change'),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Product selection (scoped to vendor)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Product (for vendor)'),
                              subtitle: Text(
                                _selectedVendor == null
                                    ? 'Select a vendor first'
                                    : productLabel,
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

                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  avatar: const Icon(Icons.confirmation_number_outlined, size: 18),
                                  label: Text(dbSummary),
                                ),
                                TextButton(
                                  onPressed: () => setState(() => _usbSource = UsbIdentitySource.manual),
                                  child: const Text('Edit VID/PID manually'),
                                ),
                                if (_selectedVendor != null || _selectedProduct != null || _selectedGlobalHit != null)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _selectedVendor = null;
                                        _selectedProduct = null;
                                        _selectedGlobalHit = null;
                                      });
                                    },
                                    child: const Text('Clear selection'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    // Manual mode: keep your original VID/PID fields
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: _vendorIdHex,
                            decoration: const InputDecoration(
                              labelText: 'Vendor ID (hex)',
                              prefixText: '0x',
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'Required';
                              if (!RegExp(r'^[0-9a-fA-F]{1,4}$').hasMatch(t.replaceAll('0x', ''))) {
                                return 'Hex up to 4 chars';
                              }
                              return null;
                            },
                            onChanged: (v) {
                              _vendorIdHex = v.trim().toUpperCase();
                            },
                            onSaved: (v) => _vendorIdHex = (v ?? '').trim().toUpperCase(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: _productIdHex,
                            decoration: const InputDecoration(
                              labelText: 'Product ID (hex)',
                              prefixText: '0x',
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'Required';
                              if (!RegExp(r'^[0-9a-fA-F]{1,4}$').hasMatch(t.replaceAll('0x', ''))) {
                                return 'Hex up to 4 chars';
                              }
                              return null;
                            },
                            onChanged: (v) {
                              _productIdHex = v.trim().toUpperCase();
                            },
                            onSaved: (v) => _productIdHex = (v ?? '').trim().toUpperCase(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Strings always editable (same as ProfileEditScreen behavior)
                  TextFormField(
                    key: ValueKey('manu_$_stringsRevision'),
                    initialValue: _manufacturer,
                    decoration: InputDecoration(
                      labelText: 'Manufacturer',
                      helperText: (_usbSource == UsbIdentitySource.usbIdsDb &&
                              (_selectedVendor?.name.trim().isNotEmpty ?? false))
                          ? 'Suggested: ${_selectedVendor!.name}'
                          : null,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    onChanged: (v) {
                      _manufacturer = v;
                      _manuDirty = true;
                    },
                    onSaved: (v) => _manufacturer = v ?? '',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: ValueKey('prod_$_stringsRevision'),
                    initialValue: _product,
                    decoration: InputDecoration(
                      labelText: 'Product',
                      helperText: (_usbSource == UsbIdentitySource.usbIdsDb &&
                              (_selectedProduct?.name.trim().isNotEmpty ?? false))
                          ? 'Suggested: ${_selectedProduct!.name}'
                          : null,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    onChanged: (v) {
                      _product = v;
                      _prodDirty = true;
                    },
                    onSaved: (v) => _product = v ?? '',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: _serial,
                    decoration: const InputDecoration(labelText: 'Serial number'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    onChanged: (v) => _serial = v,
                    onSaved: (v) => _serial = v ?? '',
                  ),
                ],
              ),
            ),
            Step(
              title: const Text('Advanced'),
              isActive: _step >= 2,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Role tunables are intentionally minimal in v1. HID report descriptors are selected automatically for the chosen role.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Notes'),
                          SizedBox(height: 8),
                          Text('• Requires root (su) to create configfs gadgets.'),
                          Text('• Your kernel must support configfs and USB gadget (UDC).'),
                          Text('• Some ROMs lock down UDC selection or USB controller properties.'),
                        ],
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
                    Expanded(child: Text('Find vendor', style: Theme.of(context).textTheme.titleLarge)),
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
                    Expanded(child: Text('Find product', style: Theme.of(context).textTheme.titleLarge)),
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
                    Expanded(child: Text('Find product', style: Theme.of(context).textTheme.titleLarge)),
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
