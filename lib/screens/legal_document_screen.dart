import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../legal/legal_config.dart';
import '../legal/legal_documents.dart';
import '../theme/tokens.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.kind});

  final LegalDocumentKind kind;

  @override
  Widget build(BuildContext context) {
    final title = LegalDocuments.titleFor(kind);
    final effective = LegalDocuments.effectiveDateFor(kind);
    final intro = LegalDocuments.introFor(kind);
    final sections = LegalDocuments.sectionsFor(kind);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(HrmsTokens.s4, HrmsTokens.s3, HrmsTokens.s4, 32),
        children: [
          Text(
            LegalConfig.appName,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: HrmsTokens.primary),
          ),
          const SizedBox(height: 4),
          Text(
            'Last updated: $effective',
            style: GoogleFonts.inter(fontSize: 12, color: HrmsTokens.muted),
          ),
          const SizedBox(height: 16),
          Text(
            intro,
            style: GoogleFonts.inter(fontSize: 14, height: 1.55, color: HrmsTokens.text),
          ),
          const SizedBox(height: 20),
          for (final section in sections) ...[
            Text(
              section.title,
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: HrmsTokens.text),
            ),
            const SizedBox(height: 8),
            for (final p in section.paragraphs) ...[
              Text(
                p,
                style: GoogleFonts.inter(fontSize: 14, height: 1.55, color: HrmsTokens.text),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
