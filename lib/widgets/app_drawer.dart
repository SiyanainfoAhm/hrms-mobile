import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key, required this.app});

  final AppState app;

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  late final Future<Map<String, dynamic>?> _companyFuture;

  @override
  void initState() {
    super.initState();
    final u = widget.app.user;
    _companyFuture = u == null ? Future.value(null) : RpcService().companyGetForUser(u.id);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.app.user;
    return Drawer(
      backgroundColor: HrmsTokens.surface,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: HrmsTokens.bg,
                border: Border(bottom: BorderSide(color: HrmsTokens.border.withValues(alpha: 0.9))),
              ),
              margin: EdgeInsets.zero,
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _companyFuture,
                builder: (context, snap) {
                  final c = snap.data;
                  final logoUrl = (c?['logo_url'] ?? c?['logoUrl'] ?? '').toString().trim();
                  final displayName = (u?.name ?? '').trim().isNotEmpty ? u!.name!.trim() : (u?.email ?? '-');
                  final sub = (u?.email ?? '').trim();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: HrmsTokens.primarySoft,
                            foregroundColor: HrmsTokens.primary,
                            child: logoUrl.isEmpty
                                ? const Icon(Icons.business_outlined)
                                : Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: ClipOval(
                                      child: Image.network(
                                        logoUrl,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.business_outlined),
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'HRMS',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: HrmsTokens.text),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(displayName, style: const TextStyle(color: HrmsTokens.text, fontWeight: FontWeight.w700)),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(sub, style: const TextStyle(color: HrmsTokens.muted)),
                      ],
                      const SizedBox(height: 4),
                      Text(u?.role ?? '-', style: const TextStyle(color: HrmsTokens.muted, fontWeight: FontWeight.w600)),
                    ],
                  );
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Dashboard'),
              onTap: () => context.go('/dashboard'),
            ),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('Attendance'),
              onTap: () => context.go('/attendance'),
            ),
            if (u?.isManagerial == true)
              ListTile(
                leading: const Icon(Icons.people_alt_outlined),
                title: const Text('Employees'),
                onTap: () => context.go('/employees'),
              ),
            ListTile(
              leading: const Icon(Icons.event),
              title: const Text('Holidays'),
              onTap: () => context.go('/holidays'),
            ),
            ListTile(
              leading: const Icon(Icons.beach_access_outlined),
              title: const Text('Leave'),
              onTap: () => context.go('/leave'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Reimbursements'),
              onTap: () => context.go('/reimbursements'),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile'),
              onTap: () => context.go('/profile'),
            ),
            if (u?.isManagerial == true) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Payroll'),
                onTap: () => context.go('/payroll'),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () => context.go('/settings'),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Payslips'),
              onTap: () => context.go('/payslips'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                await widget.app.logout();
                if (!context.mounted) return;
                context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}

