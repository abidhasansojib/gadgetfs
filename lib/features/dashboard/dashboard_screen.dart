import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'widgets/selected_profile_card.dart';
import '../../core/backend/gadget_backend.dart';
import '../../core/backend/providers.dart';
import '../../core/models/gadget_profile.dart';
import '../../core/models/gadget_status.dart';
import '../../core/storage/providers.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/status_pill.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _autoActivationAttempted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeAutoActivate();
  }

  Future<void> _maybeAutoActivate() async {
    if (_autoActivationAttempted) return;
    _autoActivationAttempted = true;

    /* Small delay to allow providers to warm up. */
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    final profilesAsync = ref.read(profilesProvider);
    final statusAsync = ref.read(gadgetStatusStreamProvider);
    if (!profilesAsync.hasValue || !statusAsync.hasValue) return;

    final status = statusAsync.value ?? GadgetStatus.empty;
    if (!status.isIdle) return;

    final profiles = profilesAsync.value ?? const <GadgetProfile>[];
    final selectedId = ref.read(selectedProfileIdProvider);
    final selected = _resolveSelectedProfile(profiles, selectedId);
    if (selected == null) return;
    if (!selected.activateOnOpen) return;

    try {
      final backend = ref.read(gadgetBackendProvider);
      await backend.activateProfile(selected);
    } catch (_) {
      /* Ignore auto-activation failures. */
    }
  }

  GadgetProfile? _resolveSelectedProfile(
    List<GadgetProfile> profiles,
    String? selectedId,
  ) {
    if (profiles.isEmpty) return null;
    if (selectedId == null) return profiles.first;
    return profiles.firstWhere((p) => p.id == selectedId, orElse: () => profiles.first);
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final statusAsync = ref.watch(gadgetStatusStreamProvider);
    final selectedId = ref.watch(selectedProfileIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GadgetFS'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (v) {
              switch (v) {
                case 'profiles':
                  context.go('/profiles');
                  break;
                case 'logs':
                  context.go('/logs');
                  break;
                case 'device_info':
                  context.goNamed('device_info');
                  break;
                case 'about':
                  context.go('/settings');
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'profiles',
                child: Row(
                  children: [
                    Icon(Icons.tune),
                    SizedBox(width: 10),
                    Text('Profiles'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'logs',
                child: Row(
                  children: [
                    Icon(Icons.subject_outlined),
                    SizedBox(width: 10),
                    Text('Logs'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'device_info',
                child: Row(
                  children: [
                    Icon(Icons.phone_android),
                    SizedBox(width: 10),
                    Text('Device Info'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 10),
                    Text('About'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: profilesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => _ErrorState(message: 'Failed to load profiles: $e'),
          data: (profiles) {
            final selected = _resolveSelectedProfile(profiles, selectedId);
            return statusAsync.when(
              loading: () => const _LoadingState(),
              error: (e, st) => _ErrorState(
                message: 'Backend status error: $e',
                showDiagnosticsActions: true,
              ),
              data: (status) => _DashboardBody(
                profiles: profiles,
                selected: selected,
                status: status,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final List<GadgetProfile> profiles;
  final GadgetProfile? selected;
  final GadgetStatus status;

  const _DashboardBody({
    required this.profiles,
    required this.selected,
    required this.status,
  });

  GadgetProfile? _resolveActiveProfile() {
    if (!status.isActive) return selected;
    final activeId = status.activeProfileId;
    if (activeId == null || activeId.isEmpty) return selected;
    for (final p in profiles) {
      if (p.id == activeId) return p;
    }
    return selected;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIdCtrl = ref.read(selectedProfileIdProvider.notifier);
    final backend = ref.read(gadgetBackendProvider);

    final canActivate = selected != null && status.rootAvailable && status.supportAvailable;
    final isBusy = status.state == 'ACTIVATING';

    Future<void> onToggle() async {
      if (isBusy) return;
      try {
        if (status.isActive) {
          await backend.deactivate();
        } else if (selected != null) {
          await backend.activateProfile(selected!);
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Operation failed: $e')),
        );
      }
    }

    Future<void> onPanic() async {
      if (isBusy) return;
      await backend.panicStop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Panic stop executed')),
        );
      }
    }

    final activeProfile = _resolveActiveProfile();
    final roleType = activeProfile?.roleType ?? GadgetRoleType.mouse;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Selected profile', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selected?.id,
                      items: [
                        for (final p in profiles)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text('${p.name} • ${gadgetRoleTypeToString(p.roleType)}'),
                          ),
                      ],
                      onChanged: (id) => selectedIdCtrl.setSelected(id),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => context.go('/profiles/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('New'),
                  ),
                ],
              ),
              if (activeProfile != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Current identity',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    Chip(
                      avatar: Icon(
                        status.isActive ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      label: Text(status.isActive ? 'Active' : 'Selected'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _IdentityRow(k: 'Role', v: gadgetRoleTypeToString(activeProfile.roleType)),
                _IdentityRow(
                  k: 'VID',
                  v: '0x${activeProfile.vendorId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                ),
                _IdentityRow(
                  k: 'PID',
                  v: '0x${activeProfile.productId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                ),
                _IdentityRow(
                  k: 'Manufacturer',
                  v: activeProfile.manufacturer.trim().isEmpty ? '—' : activeProfile.manufacturer.trim(),
                ),
                _IdentityRow(
                  k: 'Product',
                  v: activeProfile.product.trim().isEmpty ? '—' : activeProfile.product.trim(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  StatusPill(label: 'Root', ok: status.rootAvailable),
                  StatusPill(label: 'Support', ok: status.supportAvailable),
                  StatusPill(
                    label: 'UDC',
                    ok: status.udcList.isNotEmpty,
                    subtitle: status.udcList.isEmpty ? 'none' : status.udcList.first,
                  ),
                  StatusPill(
                    label: status.state,
                    ok: status.state != 'ERROR',
                    subtitle: status.message,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (status.message != null && status.message!.isNotEmpty)
                Text(status.message!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Control', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canActivate ? onToggle : null,
                      icon: Icon(status.isActive ? Icons.stop : Icons.play_arrow),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          status.isActive ? 'Deactivate' : 'Activate',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isBusy ? null : () => context.go('/logs'),
                      icon: const Icon(Icons.subject),
                      label: const Text('View logs'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isBusy ? null : onPanic,
                      icon: const Icon(Icons.warning_amber),
                      label: const Text('Panic stop'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quick tests', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                status.isActive ? 'Active role: ${gadgetRoleTypeToString(roleType)}' : 'Activate a profile to enable tests.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (!status.isActive)
                Text(
                  'Activate a profile to enable test actions.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                _QuickTestsPanel(backend: backend, roleType: roleType),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Advanced', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Diagnostics'),
                subtitle: Text('UDCs: ${status.udcList.isEmpty ? 'none' : status.udcList.join(', ')}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/diagnostics'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune_outlined),
                title: const Text('Manage profiles'),
                subtitle: const Text('Create, edit, duplicate, and delete gadget profiles'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/profiles'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_android),
                title: const Text('Device Info'),
                subtitle: const Text('Hardware, OS, runtime, and GadgetFS status'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.goNamed('device_info'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickTestsPanel extends StatefulWidget {
  final GadgetBackend backend;
  final GadgetRoleType roleType;

  const _QuickTestsPanel({
    required this.backend,
    required this.roleType,
  });

  @override
  State<_QuickTestsPanel> createState() => _QuickTestsPanelState();
}

class _QuickTestsPanelState extends State<_QuickTestsPanel> {
  bool get _showKeyboard => widget.roleType == GadgetRoleType.keyboard || widget.roleType == GadgetRoleType.composite;
  bool get _showMouse => widget.roleType == GadgetRoleType.mouse || widget.roleType == GadgetRoleType.composite;

  @override
  Widget build(BuildContext context) {
    if (_showKeyboard && _showMouse) {
      return LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 720;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _KeyboardTestCard(backend: widget.backend)),
                const SizedBox(width: 12),
                Expanded(child: _MouseTestCard(backend: widget.backend)),
              ],
            );
          }
          return Column(
            children: [
              _KeyboardTestCard(backend: widget.backend),
              const SizedBox(height: 12),
              _MouseTestCard(backend: widget.backend),
            ],
          );
        },
      );
    }
    if (_showKeyboard) return _KeyboardTestCard(backend: widget.backend);
    return _MouseTestCard(backend: widget.backend);
  }
}

class _KeyboardTestCard extends StatefulWidget {
  final GadgetBackend backend;
  const _KeyboardTestCard({required this.backend});

  @override
  State<_KeyboardTestCard> createState() => _KeyboardTestCardState();
}

class _KeyboardTestCardState extends State<_KeyboardTestCard> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  String _committedText = ''; // what we believe we already sent to host
  String _pendingText = ''; // latest text in the field
  Timer? _flushTimer;
  bool _sending = false;
  bool _flushAgain = false;

  String _lastSent = '—';

  @override
  void dispose() {
    _flushTimer?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _sendKey(String label) async {
    try {
      await widget.backend.testKeyboardKey(label);
      if (!mounted) return;
      setState(() => _lastSent = label);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Keyboard test failed: $e')),
      );
    }
  }

  Future<void> _sendTextChunk(String text) async {
    if (text.isEmpty) return;
    try {
      // Uses the same platform method; Android will treat unknown labels as "type this text".
      await widget.backend.testKeyboardKey(text);
      if (!mounted) return;
      final preview = text.length <= 22 ? text : '${text.substring(0, 22)}…';
      setState(() => _lastSent = 'TEXT: "$preview"');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Keyboard typing failed: $e')),
      );
    }
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    // Small debounce to micro-batch and prevent onChanged re-entrancy races.
    _flushTimer = Timer(const Duration(milliseconds: 45), _flushPending);
  }

  Future<void> _flushPending() async {
    if (_sending) {
      _flushAgain = true;
      return;
    }
    _sending = true;
    _flushAgain = false;

    try {
      final next = _pendingText;

      if (next == _committedText) return;

      // Common case: append at end
      if (next.startsWith(_committedText)) {
        final added = next.substring(_committedText.length);
        await _sendTextChunk(added);
        _committedText = next;
        return;
      }

      // Common case: delete from end
      if (_committedText.startsWith(next)) {
        final removedCount = _committedText.length - next.length;
        if (removedCount > 0) {
          final backspaces = List.filled(removedCount, '\b').join();
          await _sendTextChunk(backspaces);
        }
        _committedText = next;
        return;
      }

      // Fallback: the user edited in the middle or pasted/rewrote.
      // Best-effort behavior: backspace the whole committed text, then type the whole new string.
      if (_committedText.isNotEmpty) {
        final backspaces = List.filled(_committedText.length, '\b').join();
        await _sendTextChunk(backspaces);
      }
      if (next.isNotEmpty) {
        await _sendTextChunk(next);
      }
      _committedText = next;
    } finally {
      _sending = false;
      if (_flushAgain && mounted) {
        // Run another flush soon if changes happened during send.
        _scheduleFlush();
      }
    }
  }

  Future<void> _onChanged(String next) async {
    _pendingText = next;
    _scheduleFlush();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.keyboard_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Keyboard test',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Focus',
                  onPressed: () => _focus.requestFocus(),
                  icon: const Icon(Icons.center_focus_strong),
                ),
                IconButton(
                  tooltip: 'Clear',
                  onPressed: () async {
                    final old = _pendingText;
                    _ctrl.clear();
                    _pendingText = '';
                    _scheduleFlush();

                    // Fast path: if we already had committed text, try to erase it on host now.
                    if (old.isNotEmpty && _committedText.isNotEmpty) {
                      final backspaces = List.filled(_committedText.length, '\b').join();
                      await _sendTextChunk(backspaces);
                      _committedText = '';
                    }
                    if (mounted) setState(() => _lastSent = '—');
                  },
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Type below to send HID keys to the host. Deletions send BACKSPACE. '
              'For special keys, use the quick buttons.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              focusNode: _focus,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Type to test (sends to host)',
                isDense: true,
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _sendKey('ENTER'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Last sent: ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                Expanded(
                  child: Text(_lastSent, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonal(onPressed: () => _sendKey('A'), child: const Text('A')),
                FilledButton.tonal(onPressed: () => _sendKey('ENTER'), child: const Text('Enter')),
                FilledButton.tonal(onPressed: () => _sendKey('TAB'), child: const Text('Tab')),
                FilledButton.tonal(onPressed: () => _sendKey('ESC'), child: const Text('Esc')),
                FilledButton.tonal(onPressed: () => _sendKey('BACKSPACE'), child: const Text('Backspace')),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () async {
                try {
                  await widget.backend.testCtrlAltDel();
                  if (!mounted) return;
                  setState(() => _lastSent = 'CTRL+ALT+DEL');
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ctrl+Alt+Del failed: $e')),
                  );
                }
              },
              icon: const Icon(Icons.keyboard_command_key),
              label: const Text('Ctrl + Alt + Del'),
            ),
            const SizedBox(height: 6),
            Text(
              'Note: Some hosts may block Ctrl+Alt+Del or interpret it differently.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MouseTestCard extends StatefulWidget {
  final GadgetBackend backend;
  const _MouseTestCard({required this.backend});

  @override
  State<_MouseTestCard> createState() => _MouseTestCardState();
}

class _MouseTestCardState extends State<_MouseTestCard> {
  Offset? _lastPos;
  int _buttons = 0;

  // Accumulate deltas so throttling does not lose distance.
  int _accumDx = 0;
  int _accumDy = 0;

  int _lastFlushMs = 0;
  bool _sending = false;

  // Higher sensitivity + consistent flush.
  static const int _flushIntervalMs = 16; // ~60Hz
  static const double _sensitivity = 3.4;

  Future<void> _sendMove(int dx, int dy, {int wheel = 0, int? buttons}) async {
    try {
      await widget.backend.testMouseMove(
        dx: dx,
        dy: dy,
        wheel: wheel,
        buttons: buttons ?? _buttons,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mouse test failed: $e')),
      );
    }
  }

  int _scaleDelta(double d) {
    // Scale and clamp into HID report range.
    final v = (d * _sensitivity).round();
    return v.clamp(-127, 127);
  }

  Future<void> _pressButton(int mask) async {
    _buttons = mask;
    await _sendMove(0, 0, buttons: _buttons);
  }

  Future<void> _releaseButtons() async {
    _buttons = 0;
    await _sendMove(0, 0, buttons: _buttons);
  }

  void _accumulateAndFlush(int dx, int dy, {bool force = false}) {
    _accumDx += dx;
    _accumDy += dy;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force && (nowMs - _lastFlushMs) < _flushIntervalMs) return;
    _lastFlushMs = nowMs;

    if (_sending) return;

    final sendDx = _accumDx.clamp(-127, 127);
    final sendDy = _accumDy.clamp(-127, 127);
    if (sendDx == 0 && sendDy == 0) return;

    _accumDx -= sendDx;
    _accumDy -= sendDy;

    _sending = true;
    unawaited(() async {
      try {
        await _sendMove(sendDx, sendDy);
      } finally {
        _sending = false;
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mouse_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mouse test',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Drag inside the pad to send relative movement. Tap/press to click.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 1.15,
              child: _MousePad(
                onPanStart: (p) => _lastPos = p,
                onPanEnd: () {
                  _lastPos = null;
                  _accumulateAndFlush(0, 0, force: true);
                },
                onPanUpdate: (p) {
                  final last = _lastPos;
                  _lastPos = p;
                  if (last == null) return;

                  final delta = p - last;
                  final dx = _scaleDelta(delta.dx);
                  final dy = _scaleDelta(delta.dy);
                  if (dx == 0 && dy == 0) return;

                  _accumulateAndFlush(dx, dy);
                },
                onTapDown: () => _pressButton(1), /* left */
                onTapUp: _releaseButtons,
                onCancel: _releaseButtons,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonal(onPressed: () => _sendMove(-45, 0), child: const Text('Nudge left')),
                FilledButton.tonal(onPressed: () => _sendMove(45, 0), child: const Text('Nudge right')),
                FilledButton.tonal(onPressed: () => _sendMove(0, -45), child: const Text('Nudge up')),
                FilledButton.tonal(onPressed: () => _sendMove(0, 45), child: const Text('Nudge down')),
                FilledButton.tonal(onPressed: () => _sendMove(0, 0, wheel: -18), child: const Text('Wheel up')),
                FilledButton.tonal(onPressed: () => _sendMove(0, 0, wheel: 18), child: const Text('Wheel down')),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await _pressButton(1);
                    await Future<void>.delayed(const Duration(milliseconds: 35));
                    await _releaseButtons();
                  },
                  icon: const Icon(Icons.touch_app_outlined),
                  label: const Text('Left click'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await _pressButton(2);
                    await Future<void>.delayed(const Duration(milliseconds: 35));
                    await _releaseButtons();
                  },
                  icon: const Icon(Icons.mouse_outlined),
                  label: const Text('Right click'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await _pressButton(4);
                    await Future<void>.delayed(const Duration(milliseconds: 35));
                    await _releaseButtons();
                  },
                  icon: const Icon(Icons.circle_outlined),
                  label: const Text('Middle click'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MousePad extends StatelessWidget {
  final void Function(Offset localPos) onPanStart;
  final void Function(Offset localPos) onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onCancel;

  const _MousePad({
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onTapDown,
    required this.onTapUp,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTapDown: (_) => onTapDown(),
        onTapCancel: onCancel,
        onTapUp: (_) => onTapUp(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => onPanStart(d.localPosition),
          onPanUpdate: (d) => onPanUpdate(d.localPosition),
          onPanEnd: (_) => onPanEnd(),
          onPanCancel: onPanEnd,
          child: CustomPaint(
            painter: _CrosshairPainter(color: cs.onSurface.withOpacity(0.22)),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final Color color;
  _CrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * 0.40;

    canvas.drawCircle(center, r, p);
    canvas.drawLine(Offset(center.dx - r, center.dy), Offset(center.dx + r, center.dy), p);
    canvas.drawLine(Offset(center.dx, center.dy - r), Offset(center.dx, center.dy + r), p);

    final dot = Paint()..color = color.withOpacity(0.55);
    canvas.drawCircle(center, 3.0, dot);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) => oldDelegate.color != color;
}

class _IdentityRow extends StatelessWidget {
  final String k;
  final String v;

  const _IdentityRow({required this.k, required this.v});

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );
    final valueStyle = Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(k, style: labelStyle)),
          Expanded(child: SelectableText(v, style: valueStyle)),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Loading gadget status…', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.go('/diagnostics'),
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Diagnostics'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/logs'),
                    icon: const Icon(Icons.subject_outlined),
                    label: const Text('Logs'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final bool showDiagnosticsActions;

  const _ErrorState({
    required this.message,
    this.showDiagnosticsActions = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              if (showDiagnosticsActions) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => context.go('/diagnostics'),
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('Diagnostics'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/logs'),
                      icon: const Icon(Icons.subject_outlined),
                      label: const Text('Logs'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
