import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'services/runtime_config.dart';
import 'services/supabase_client.dart';
import 'services/rpc_service.dart';
import 'state/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/attendance_screen.dart';
import 'screens/employees_screen.dart';
import 'screens/employee_invite_screen.dart';
import 'screens/holidays_screen.dart';
import 'screens/leave_screen.dart';
import 'screens/reimbursements_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/payroll_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/payslips_screen.dart';
import 'theme/hrms_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RuntimeConfig.instance.load();
  await SupabaseApp.init();
  runApp(const HrmsApp());
}

class HrmsApp extends StatefulWidget {
  const HrmsApp({super.key});

  @override
  State<HrmsApp> createState() => _HrmsAppState();
}

class _HrmsAppState extends State<HrmsApp> {
  late final AppState app = AppState(RpcService())..init();

  late final GoRouter _router = GoRouter(
    initialLocation: '/login',
    refreshListenable: app,
    redirect: (context, state) {
      if (app.loading) return null;
      final loggedIn = app.user != null;
      final isAuthRoute = state.matchedLocation == '/login' || state.matchedLocation == '/signup';
      if (!loggedIn && !isAuthRoute) return '/login';
      if (loggedIn && isAuthRoute) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => LoginScreen(app: app)),
      GoRoute(path: '/signup', builder: (c, s) => SignupScreen(app: app)),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => DashboardScreen(app: app),
      ),
      GoRoute(
        path: '/attendance',
        builder: (c, s) => AttendanceScreen(app: app),
      ),
      GoRoute(
        path: '/employees',
        builder: (c, s) => EmployeesScreen(app: app),
        redirect: (c, s) => app.user?.isManagerial == true ? null : '/dashboard',
      ),
      GoRoute(
        path: '/employees/invite/:userId',
        builder: (c, s) => EmployeeInviteScreen(
          app: app,
          targetUserId: s.pathParameters['userId'] ?? '',
        ),
        redirect: (c, s) => app.user?.isManagerial == true ? null : '/dashboard',
      ),
      GoRoute(path: '/holidays', builder: (c, s) => HolidaysScreen(app: app)),
      GoRoute(path: '/leave', builder: (c, s) => LeaveScreen(app: app)),
      GoRoute(path: '/reimbursements', builder: (c, s) => ReimbursementsScreen(app: app)),
      GoRoute(path: '/profile', builder: (c, s) => ProfileScreen(app: app)),
      GoRoute(path: '/profile/change-password', builder: (c, s) => ChangePasswordScreen(app: app)),
      GoRoute(
        path: '/payroll',
        builder: (c, s) => PayrollScreen(app: app),
        redirect: (c, s) => app.user?.isManagerial == true ? null : '/dashboard',
      ),
      GoRoute(
        path: '/settings',
        builder: (c, s) => SettingsScreen(app: app),
        redirect: (c, s) => app.user?.isManagerial == true ? null : '/dashboard',
      ),
      GoRoute(
        path: '/payslips',
        builder: (c, s) => PayslipsScreen(app: app),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HRMS',
      theme: HrmsTheme.light(),
      routerConfig: _router,
    );
  }
}
