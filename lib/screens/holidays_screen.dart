import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../services/rpc_service.dart';
import '../ui/empty_state.dart';
import '../ui/formatters.dart';
import '../widgets/app_drawer.dart';

class HolidaysScreen extends StatelessWidget {
  const HolidaysScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final companyId = app.user?.companyId;
    return Scaffold(
      appBar: AppBar(title: const Text('Holidays')),
      drawer: AppDrawer(app: app),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: companyId == null || companyId.isEmpty
            ? const EmptyState(
                title: 'No company assigned',
                subtitle: 'Ask your admin to assign you to a company to view holidays.',
                icon: Icons.business_outlined,
              )
            : FutureBuilder(
                future: RpcService().holidaysList(companyId),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return EmptyState(
                      title: 'Could not load holidays',
                      subtitle: snap.error.toString(),
                      icon: Icons.error_outline,
                    );
                  }
                  final rows = (snap.data ?? const <Map<String, dynamic>>[]);
                  if (rows.isEmpty) {
                    return const EmptyState(
                      title: 'No holidays yet',
                      subtitle: 'Your company has not added any holidays.',
                      icon: Icons.event_busy,
                    );
                  }

                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final date = UiFormatters.indianDate(r['holiday_date']);
                      final end = r['holiday_end_date'] != null ? UiFormatters.indianDate(r['holiday_end_date']) : null;
                      final optional = r['is_optional'] == true;
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8F0))),
                        child: ListTile(
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: optional ? const Color(0xFFFFF7ED) : const Color(0xFFEFFDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(optional ? Icons.star_outline : Icons.event_available_outlined, color: const Color(0xFF047857)),
                          ),
                          title: Text((r['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(end != null ? '$date → $end' : date),
                          trailing: optional
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF7ED),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: const Color(0xFF9A3412).withValues(alpha: 0.2)),
                                  ),
                                  child: const Text('OPTIONAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9A3412))),
                                )
                              : null,
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

