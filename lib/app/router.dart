import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/settings/settings_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/diagnostics/diagnostics_screen.dart';
import '../features/device_info/device_info_screen.dart';
import '../features/logs/logs_screen.dart';
import '../features/profiles/profile_edit_screen.dart';
import '../features/profiles/profiles_screen.dart';
import '../features/touchpad/touchpad_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
        routes: [
          GoRoute(
            path: 'touchpad',
            name: 'touchpad',
            builder: (context, state) => const TouchpadScreen(),
          ),
          GoRoute(
            path: 'profiles',
            name: 'profiles',
            builder: (context, state) => const ProfilesScreen(),
          ),
          GoRoute(
            path: 'profiles/new',
            name: 'profile_new',
            builder: (context, state) => const ProfileEditScreen(),
          ),
          GoRoute(
            path: 'profiles/:id',
            name: 'profile_edit',
            builder: (context, state) =>
                ProfileEditScreen(profileId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'logs',
            name: 'logs',
            builder: (context, state) => const LogsScreen(),
          ),
          GoRoute(
            path: 'diagnostics',
            name: 'diagnostics',
            builder: (context, state) => const DiagnosticsScreen(),
          ),
          GoRoute(
            path: 'device-info',
            name: 'device_info',
            builder: (context, state) => const DeviceInfoScreen(),
          ),
          GoRoute(
            path: 'settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
