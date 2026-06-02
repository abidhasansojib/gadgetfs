import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/backend/providers.dart';
import '../../shared/widgets/section_card.dart';

class DeviceInfoScreen extends ConsumerStatefulWidget {
  const DeviceInfoScreen({super.key});

  @override
  ConsumerState<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends ConsumerState<DeviceInfoScreen> {
  bool _loading = true;
  Object? _error;
  Map<String, dynamic> _report = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  dynamic _deepNormalize(dynamic value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) {
        out[k.toString()] = _deepNormalize(v);
      });
      return out;
    }
    if (value is List) {
      return value.map(_deepNormalize).toList(growable: false);
    }
    return value;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final pkg = await PackageInfo.fromPlatform();
      final deviceInfo = DeviceInfoPlugin();

      AndroidDeviceInfo? android;
      try {
        android = await deviceInfo.androidInfo;
      } catch (_) {
        android = null;
      }

      final backend = ref.read(gadgetBackendProvider);

      Map<String, dynamic>? status;
      try {
        status = (await backend.getStatus()).toJson();
      } catch (_) {
        status = null;
      }

      Map<String, dynamic>? diagnostics;
      try {
        final raw = await backend.getDiagnostics();
        diagnostics = (_deepNormalize(raw) as Map).cast<String, dynamic>();
      } catch (_) {
        diagnostics = null;
      }

      final kernelConfig =
          (diagnostics?['kernelConfig'] is Map) ? (diagnostics!['kernelConfig'] as Map).cast<String, dynamic>() : null;

      final locale = WidgetsBinding.instance.platformDispatcher.locale;
      final now = DateTime.now();

      final report = <String, dynamic>{
        'generatedAt': now.toIso8601String(),
        'app': {
          'name': pkg.appName,
          'packageName': pkg.packageName,
          'version': pkg.version,
          'buildNumber': pkg.buildNumber,
        },
        'flutter': {
          'platform': Platform.operatingSystem,
          'platformVersion': Platform.operatingSystemVersion,
          'dartVersion': Platform.version,
          'locale': locale.toLanguageTag(),
          'timeZoneName': now.timeZoneName,
          'timeZoneOffsetMinutes': now.timeZoneOffset.inMinutes,
        },
        'gadgetfs': {
          'status': status,
          if (kernelConfig != null) 'kernelConfig': kernelConfig,
          // Keep full diagnostics available for copy/paste and troubleshooting.
          if (diagnostics != null) 'diagnostics': diagnostics,
        },
        'android': android == null
            ? null
            : {
                'brand': android.brand,
                'manufacturer': android.manufacturer,
                'model': android.model,
                'device': android.device,
                'product': android.product,
                'board': android.board,
                'hardware': android.hardware,
                'bootloader': android.bootloader,
                'fingerprint': android.fingerprint,
                'display': android.display,
                'host': android.host,
                'tags': android.tags,
                'type': android.type,
                'isPhysicalDevice': android.isPhysicalDevice,
                'supportedAbis': android.supportedAbis,
                'supported32BitAbis': android.supported32BitAbis,
                'supported64BitAbis': android.supported64BitAbis,
                'version': {
                  'sdkInt': android.version.sdkInt,
                  'release': android.version.release,
                  'codename': android.version.codename,
                  'incremental': android.version.incremental,
                  'securityPatch': android.version.securityPatch,
                  'baseOS': android.version.baseOS,
                  'previewSdkInt': android.version.previewSdkInt,
                },
              },
      };

      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _copyAll() async {
    final pretty = const JsonEncoder.withIndent('  ').convert(_report);
    await Clipboard.setData(ClipboardData(text: pretty));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Device info copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Info'),
        actions: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_all),
            onPressed: _report.isEmpty ? null : _copyAll,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(
                    error: _error!,
                    onRetry: _load,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Display', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            _KeyValue(
                              k: 'size',
                              v: '${mq.size.width.toStringAsFixed(0)} × ${mq.size.height.toStringAsFixed(0)}',
                            ),
                            _KeyValue(k: 'devicePixelRatio', v: '${mq.devicePixelRatio}'),
                            _KeyValue(k: 'textScaleFactor', v: '${mq.textScaler.scale(1.0)}'),
                            _KeyValue(
                              k: 'brightness',
                              v: mq.platformBrightness.name,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _MapSection(
                        title: 'App',
                        map: (_report['app'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
                      ),
                      const SizedBox(height: 12),
                      _MapSection(
                        title: 'GadgetFS',
                        map: (_report['gadgetfs'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
                      ),
                      const SizedBox(height: 12),
                      _MapSection(
                        title: 'Flutter / Runtime',
                        map: (_report['flutter'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
                      ),
                      const SizedBox(height: 12),
                      _MapSection(
                        title: 'Android',
                        map: (_report['android'] as Map?)?.cast<String, dynamic>() ??
                            <String, dynamic>{'note': 'Android info unavailable'},
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.info_outline),
                          title: const Text('Tip'),
                          subtitle: const Text(
                            'If you file a bug report, include this Device Info (copy button) plus a Diagnostics report.',
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _MapSection extends StatelessWidget {
  final String title;
  final Map<String, dynamic> map;

  const _MapSection({
    required this.title,
    required this.map,
  });

  @override
  Widget build(BuildContext context) {
    List<Widget> buildRows(Map<String, dynamic> m, {String prefix = ''}) {
      final rows = <Widget>[];
      final keys = m.keys.toList()..sort();

      for (final k in keys) {
        final v = m[k];
        final key = prefix.isEmpty ? k : '$prefix.$k';

        if (v is Map) {
          rows.add(_Subheader(text: key));
          rows.addAll(buildRows(v.cast<String, dynamic>(), prefix: key));
        } else if (v is List) {
          rows.add(_KeyValue(k: key, v: v.join(', ')));
        } else {
          rows.add(_KeyValue(k: key, v: v?.toString() ?? '—'));
        }
      }
      return rows;
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...buildRows(map),
        ],
      ),
    );
  }
}

class _Subheader extends StatelessWidget {
  final String text;

  const _Subheader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String k;
  final String v;

  const _KeyValue({
    required this.k,
    required this.v,
  });

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
          SizedBox(
            width: 160,
            child: Text(k, style: labelStyle),
          ),
          Expanded(
            child: SelectableText(v, style: valueStyle),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.error,
    required this.onRetry,
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
              const Icon(Icons.error_outline),
              const SizedBox(height: 12),
              Text(
                'Failed to load device info:\n$error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
