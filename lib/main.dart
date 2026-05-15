import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'services/runtime_config.dart';
import 'services/supabase_client.dart';
import 'services/rpc_service.dart';
import 'services/attendance_timezone.dart';
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
import 'widgets/hrms_shell/main_shell.dart';

final GlobalKey<NavigatorState> hrmsRootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'hrmsRoot');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ensureAttendanceTimeZonesInitialized();
  await RuntimeConfig.instance.load();
  await SupabaseApp.init();
  final rpc = RpcService();
  final app = AppState(rpc);
  await app.init();
  runApp(HrmsApp(app: app));
}

class HrmsApp extends StatefulWidget {
  const HrmsApp({super.key, required this.app});

  final AppState app;

  @override
  State<HrmsApp> createState() => _HrmsAppState();
}

class _HrmsAppState extends State<HrmsApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    _router = GoRouter(
      navigatorKey: hrmsRootNavigatorKey,
      initialLocation: app.user != null ? '/home' : '/login',
      refreshListenable: app,
      redirect: (context, state) {
        if (app.loading) return null;
        final loggedIn = app.user != null;
        final loc = state.matchedLocation;
        final isAuthRoute = loc == '/login' || loc == '/signup';
        if (!loggedIn && !isAuthRoute) return '/login';
        if (loggedIn && isAuthRoute) return '/home';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (c, s) => LoginScreen(app: app)),
        GoRoute(path: '/signup', builder: (c, s) => SignupScreen(app: app)),
        GoRoute(path: '/dashboard', redirect: (c, s) => '/home'),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => MainShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/home', builder: (c, s) => DashboardScreen(app: app)),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/attendance', builder: (c, s) => AttendanceScreen(app: app)),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/leave', builder: (c, s) => LeaveScreen(app: app)),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/payslips', builder: (c, s) => PayslipsScreen(app: app)),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/profile', builder: (c, s) => ProfileScreen(app: app)),
              ],
            ),
          ],
        ),
        GoRoute(
          parentNavigatorKey: hrmsRootNavigatorKey,
          path: '/holidays',
          builder: (c, s) => HolidaysScreen(app: app),
        ),
        GoRoute(
          parentNavigatorKey: hrmsRootNavigatorKey,
          path: '/reimbursements',
          builder: (c, s) => ReimbursementsScreen(app: app),
        ),
        GoRoute(
          parentNavigatorKey: hrmsRootNavigatorKey,
          path: '/employees',
          builder: (c, s) => EmployeesScreen(app: app),
          redirect: (c, s) => app.user?.isManagerial == true ? null : '/home',
        ),
        GoRoute(
          parentNavigatorKey: hrmsRootNavigatorKey,
          path: '/employees/invite/:userId',
          builder: (c, s) => EmployeeInviteScreen(
            app: app,
            targetUserId: s.pathParameters['userId'] ?? '',
          ),
          redirect: (c, s) => app.user?.isManagerial == true ? null : '/home',
        ),
        GoRoute(
          parentNavigatorKey: hrmsRootNavigatorKey,
          path: '/payroll',
          builder: (c, s) => PayrollScreen(app: app),
          redirect: (c, s) => app.user?.isManagerial == true ? null : '/home',
        ),
        GoRoute(
          parentNavigatorKey: hrmsRootNavigatorKey,
          path: '/settings',
          builder: (c, s) => SettingsScreen(app: app),
          redirect: (c, s) => app.user?.isManagerial == true ? null : '/home',
        ),
        GoRoute(
          parentNavigatorKey: hrmsRootNavigatorKey,
          path: '/profile/change-password',
          builder: (c, s) => ChangePasswordScreen(app: app),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HRMS',
      theme: HrmsTheme.light(),
      routerConfig: _router,
    );
  }
}
