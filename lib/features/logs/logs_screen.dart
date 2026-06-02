import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'log_buffer.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  String _query = '';
  final _fmt = DateFormat('HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(logBufferProvider);

    final filtered = lines.where((l) {
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return true;
      return l.message.toLowerCase().contains(q) || l.tag.toLowerCase().contains(q);
    }).toList(growable: false);

    Future<void> copyAll() async {
      final txt = filtered.map((e) => e.toString()).join('\n');
      await Clipboard.setData(ClipboardData(text: txt));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied ${filtered.length} lines')),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            tooltip: 'Copy',
            onPressed: filtered.isEmpty ? null : copyAll,
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: () => ref.read(logBufferProvider.notifier).clear(),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Filter',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No logs yet. Activate a profile to see live output.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final l = filtered[i];
                        final time = _fmt.format(l.ts);
                        return _LogRow(
                          time: time,
                          level: l.level,
                          tag: l.tag,
                          message: l.message,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final String time;
  final String level;
  final String tag;
  final String message;

  const _LogRow({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$time  [$level]  $tag', style: mono),
            const SizedBox(height: 6),
            Text(message, style: mono),
          ],
        ),
      ),
    );
  }
}
