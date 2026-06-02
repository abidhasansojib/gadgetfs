import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/backend/gadget_backend.dart';
import '../../core/backend/providers.dart';
import '../../core/models/gadget_status.dart';
import '../logs/log_buffer.dart';
import 'diagnostics_controller.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  Future<void> _copyReport(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final backend = ref.read(gadgetBackendProvider);
    final logBuffer = ref.read(logBufferProvider);

    GadgetStatus? status;
    try {
      status = await backend.getStatus();
    } catch (_) {
      status = null;
    }

    Map<String, dynamic>? diag;
    try {
      diag = await backend.getDiagnostics();
    } catch (_) {
      diag = null;
    }

    final logs = logBuffer
        .take(250)
        .map((l) => l.toString())
        .toList(growable: false);

    final report = <String, dynamic>{
      'app': {
        'name': 'GadgetFS',
        'generatedAt': DateTime.now().toIso8601String(),
      },
      'status': status?.toJson(),
      'diagnostics': diag,
      'logsTail': logs,
    };

    final pretty = const JsonEncoder.withIndent('  ').convert(report);
    await Clipboard.setData(ClipboardData(text: pretty));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics report copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(gadgetStatusStreamProvider);
    final diagAsync = ref.watch(diagnosticsControllerProvider);
    final logBuffer = ref.watch(logBufferProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy_all),
            onPressed: () => _copyReport(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Live status',
            child: statusAsync.when(
              data: (s) => _StatusCard(status: s),
              loading: () => _LoadingCard(
                title: 'Waiting for status stream…',
                subtitle: 'If this stays here, use “Force refresh” below and copy a report.',
              ),
              error: (e, _) => _ErrorCard(
                title: 'Status stream error',
                message: e.toString(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Actions',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final backend = ref.read(gadgetBackendProvider);
                    try {
                      await backend.refreshStatus();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Status refreshed')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Refresh failed: $e')),
                      );
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Force refresh'),
                ),
                OutlinedButton.icon(
                  onPressed: () => ref.read(diagnosticsControllerProvider.notifier).run(),
                  icon: const Icon(Icons.medical_information),
                  label: const Text('Run diagnostics'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.goNamed('logs'),
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Open logs'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Diagnostics output',
            child: diagAsync.when(
              data: (map) {
                if (map == null) {
                  return const _HintCard(
                    text: 'No diagnostics collected yet. Tap “Run diagnostics” above.',
                  );
                }
                final pretty = const JsonEncoder.withIndent('  ').convert(map);
                return _CodeBlock(text: pretty);
              },
              loading: () => const _LoadingCard(
                title: 'Collecting diagnostics…',
                subtitle: 'Running a few root + system checks.',
              ),
              error: (e, _) => _ErrorCard(
                title: 'Diagnostics error',
                message: e.toString(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Log tail (most recent)',
            child: _CodeBlock(
              text: logBuffer.take(80).map((l) => l.toString()).join('\n'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final GadgetStatus status;

  const _StatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final pairs = <(String, String)>[
      ('rootAvailable', status.rootAvailable.toString()),
      ('supportAvailable', status.supportAvailable.toString()),
      ('udcCount', status.udcList.length.toString()),
      ('state', status.state),
      ('activeProfileId', status.activeProfileId ?? ''),
      ('message', status.message ?? ''),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...pairs.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        p.$1,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    Expanded(child: Text(p.$2)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _LoadingCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String title;
  final String message;

  const _ErrorCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 8),
            Text(message, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final String text;

  const _HintCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String text;

  const _CodeBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text.isEmpty ? '(empty)' : text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
        ),
      ),
    );
  }
}
