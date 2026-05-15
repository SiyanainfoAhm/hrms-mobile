import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../ui/empty_state.dart';
import '../ui/formatters.dart';
import '../widgets/hrms_ui/app_card.dart';
import '../widgets/hrms_ui/skeleton.dart';

class HolidaysScreen extends StatelessWidget {
  const HolidaysScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final companyId = app.user?.companyId;
    return Scaffold(
      appBar: AppBar(title: const Text('Holidays')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(HrmsTokens.s4),
          child: companyId == null || companyId.isEmpty
              ? const EmptyState(
                  title: 'No company assigned',
                  subtitle: 'Ask your admin to assign you to a company to view holidays.',
                  icon: Icons.business_outlined,
                )
              : FutureBuilder<List<Map<String, dynamic>>>(
                  future: RpcService().holidaysList(companyId),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return ListView.separated(
                        itemCount: 6,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, __) => const SkeletonCard(lines: 2),
                      );
                    }
                    if (snap.hasError) {
                      return EmptyState(
                        title: 'Could not load holidays',
                        subtitle: snap.error.toString(),
                        icon: Icons.error_outline,
                      );
                    }
                    final rows = snap.data ?? const <Map<String, dynamic>>[];
                    if (rows.isEmpty) {
                      return const EmptyState(
                        title: 'No holidays yet',
                        subtitle: 'Your company has not added any holidays.',
                        icon: Icons.event_busy,
                      );
                    }

                    return ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final ymd = (r['holiday_date'] ?? '').toString();
                        final dt = DateTime.tryParse(ymd.length >= 10 ? ymd.substring(0, 10) : '');
                        final day = dt != null ? dt.day.toString().padLeft(2, '0') : '—';
                        final mon = dt != null
                            ? const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1]
                            : '';
                        final dateLabel = UiFormatters.indianDate(r['holiday_date']);
                        final end = r['holiday_end_date'] != null ? UiFormatters.indianDate(r['holiday_end_date']) : null;
                        final optional = r['is_optional'] == true;
                        return AppCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 56,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: optional ? HrmsTokens.warning.withValues(alpha: 0.12) : HrmsTokens.primarySoft,
                                  borderRadius: HrmsTokens.rMd(),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      day,
                                      style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: HrmsTokens.text),
                                    ),
                                    Text(mon, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: HrmsTokens.muted)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (r['name'] ?? '').toString(),
                                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: HrmsTokens.text),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      end != null ? '$dateLabel → $end' : dateLabel,
                                      style: GoogleFonts.inter(fontSize: 13, color: HrmsTokens.muted),
                                    ),
                                    if (optional) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: HrmsTokens.warning.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(color: HrmsTokens.warning.withValues(alpha: 0.35)),
                                        ),
                                        child: Text(
                                          'Optional',
                                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: HrmsTokens.warning),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}
