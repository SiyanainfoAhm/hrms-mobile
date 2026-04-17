import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/rpc_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../ui/empty_state.dart';
import '../ui/hrms_card.dart';
import '../ui/formatters.dart';
import '../ui/payslip_html.dart';

/// Mobile-friendly "My Pay" tab aligned to web Profile → Pay.
/// Uses the existing backend RPC (`hrms_payslips_me`) and renders the HTML payslip in-app.
class ProfilePayTab extends StatefulWidget {
  const ProfilePayTab({super.key, required this.app});

  final AppState app;

  @override
  State<ProfilePayTab> createState() => _ProfilePayTabState();
}

class _ProfilePayTabState extends State<ProfilePayTab> {
  final _rpc = RpcService();

  Map<String, dynamic>? _data;
  bool _loading = true;
  Object? _err;

  String _year = DateTime.now().year.toString();
  String _month = DateTime.now().month.toString().padLeft(2, '0');

  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.white);

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _slips() {
    final arr = (_data?['payslips'] as List?) ?? const [];
    return arr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _load() async {
    final u = widget.app.user;
    if (u == null) return;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final y = int.tryParse(_year);
      final m = int.tryParse(_month);
      _data = await _rpc.payslipsMe(userId: u.id, companyId: u.companyId, year: y, month: m);
      final slips = _slips();
      final slip = slips.isNotEmpty ? slips.first : null;
      if (slip != null) {
        final company = _data?['company'] == null ? null : Map<String, dynamic>.from(_data!['company'] as Map);
        final user = _data?['user'] == null ? null : Map<String, dynamic>.from(_data!['user'] as Map);
        final html = buildPayslipHtml(
          slip: slip,
          company: company,
          user: user,
          selectedMonth: _month,
          selectedYear: _year,
        );
        await _web.loadHtmlString(html);
      }
    } catch (e) {
      _err = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) {
      return EmptyState(
        title: 'Could not load payslips',
        subtitle: _err.toString(),
        icon: Icons.error_outline,
        action: ElevatedButton(onPressed: _load, child: const Text('Retry')),
      );
    }

    final slips = _slips();
    if (slips.isEmpty) {
      return const EmptyState(
        title: 'No payslips yet',
        subtitle: 'Payslips will appear here after payroll is run.',
        icon: Icons.description_outlined,
      );
    }

    final slip = slips.first;
    final net = slip['net_pay'];
    final generatedAt = UiFormatters.indianDateLong(slip['generated_at']);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(HrmsTokens.s4),
      children: [
        HrmsCard(
          title: 'Payslip',
          subtitle: 'Current selection: $_month/$_year',
          trailing: const Icon(Icons.payments_outlined, color: HrmsTokens.primary),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Generated', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 2),
                      Text(generatedAt, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Net', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 2),
                      Text('${net ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: HrmsTokens.s3),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _month,
                      decoration: const InputDecoration(labelText: 'Month'),
                      items: List.generate(12, (i) {
                        final v = (i + 1).toString().padLeft(2, '0');
                        return DropdownMenuItem(value: v, child: Text(v));
                      }),
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() => _month = v);
                        await _load();
                      },
                    ),
                  ),
                  const SizedBox(width: HrmsTokens.s3),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _year,
                      decoration: const InputDecoration(labelText: 'Year'),
                      items: List.generate(6, (i) {
                        final y = (DateTime.now().year - 3 + i).toString();
                        return DropdownMenuItem(value: y, child: Text(y));
                      }),
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() => _year = v);
                        await _load();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: HrmsTokens.s4),
        ClipRRect(
          borderRadius: HrmsTokens.rMd(),
          child: SizedBox(
            height: 640,
            child: WebViewWidget(controller: _web),
          ),
        ),
        const SizedBox(height: HrmsTokens.s6),
      ],
    );
  }
}

