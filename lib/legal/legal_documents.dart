import 'legal_config.dart';

enum LegalDocumentKind { privacy, terms }

class LegalSection {
  const LegalSection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

class LegalDocuments {
  LegalDocuments._();

  static String titleFor(LegalDocumentKind kind) => switch (kind) {
        LegalDocumentKind.privacy => 'Privacy Policy',
        LegalDocumentKind.terms => 'Terms and Conditions',
      };

  static String effectiveDateFor(LegalDocumentKind kind) => switch (kind) {
        LegalDocumentKind.privacy => LegalConfig.privacyPolicyEffectiveDate,
        LegalDocumentKind.terms => LegalConfig.termsEffectiveDate,
      };

  static String introFor(LegalDocumentKind kind) {
    final app = LegalConfig.appName;
    final entity = LegalConfig.legalEntityName;
    return switch (kind) {
      LegalDocumentKind.privacy =>
        'This Privacy Policy describes how $entity ("we", "us", "our") collects, uses, stores, and protects personal information when you use the $app mobile application and related HRMS services (the "Service"). By creating an account or using the Service, you acknowledge this Policy.',
      LegalDocumentKind.terms =>
        'These Terms and Conditions ("Terms") govern your access to and use of the $app mobile application and related HRMS services (the "Service") operated by $entity ("we", "us", "our"). Please read them carefully before using the Service.',
    };
  }

  static List<LegalSection> sectionsFor(LegalDocumentKind kind) => switch (kind) {
        LegalDocumentKind.privacy => _privacySections,
        LegalDocumentKind.terms => _termsSections,
      };

  static final List<LegalSection> _privacySections = [
    LegalSection(
      title: '1. Who we are',
      paragraphs: [
        'Data controller: ${LegalConfig.legalEntityName}, ${LegalConfig.registeredAddress}.',
        'Contact for privacy requests: ${LegalConfig.contactEmail}.',
      ],
    ),
    LegalSection(
      title: '2. Scope',
      paragraphs: [
        'This Policy applies to employees, administrators, and other authorised users who access the Service through an account issued or approved by their employer (your "Organisation").',
        'Your Organisation may also have its own HR or IT policies. Where those policies apply to employment matters, they operate alongside this Policy for app-specific processing.',
      ],
    ),
    LegalSection(
      title: '3. Information we collect',
      paragraphs: [
        'Account and identity: name, work email, phone number, password (stored in hashed form by our authentication provider), profile photo if uploaded, and sign-in information when you use Google Sign-In.',
        'Employment and HR data: employee code, designation, department, division, shift, date of joining, employment status, compensation-related fields your Organisation chooses to store, leave balances and requests, attendance and punch records, holiday calendar data, and payslip or payroll information made available to you.',
        'Location data: when you mark attendance or use location-enabled features, we may collect precise or approximate device location only as permitted by your device settings and your Organisation\'s configuration.',
        'Documents and files: identity or HR documents, reimbursement receipts, or other files you upload through the Service.',
        'Device and technical data: app version, device type, operating system, IP address, and diagnostic logs needed to operate and secure the Service.',
      ],
    ),
    LegalSection(
      title: '4. How we use information',
      paragraphs: [
        'Provide and operate the Service, including authentication, attendance, leave, payroll views, reimbursements, and profile management.',
        'Process actions requested by you or authorised by your Organisation (for example, approving leave or viewing payslips).',
        'Maintain security, prevent fraud, troubleshoot errors, and improve reliability.',
        'Comply with law, respond to lawful requests, and enforce our Terms.',
        'Send service-related communications (for example, account or security notices) where applicable.',
      ],
    ),
    LegalSection(
      title: '5. Legal bases (where applicable)',
      paragraphs: [
        'We process personal information to perform our contract with your Organisation and you as a user, based on legitimate interests in operating a secure HR platform, and where required to comply with legal obligations.',
        'Your Organisation is responsible for ensuring it has a lawful basis to collect and share employee data with the Service.',
      ],
    ),
    LegalSection(
      title: '6. Sharing and disclosure',
      paragraphs: [
        'Within your Organisation: administrators and managers may access data according to roles and permissions configured by your Organisation.',
        'Service providers: we use trusted third parties that help us run the Service, including cloud hosting and database providers (such as Supabase), and Google for optional single sign-on. These providers process data on our instructions and under appropriate safeguards.',
        'Legal and safety: we may disclose information if required by law, court order, or government request, or to protect rights, safety, and security of users and the Service.',
        'We do not sell your personal information.',
      ],
    ),
    LegalSection(
      title: '7. International transfers',
      paragraphs: [
        'Your data may be stored or processed in countries other than where you live, including where our infrastructure or service providers operate. We take steps designed to ensure appropriate protection consistent with applicable law.',
      ],
    ),
    LegalSection(
      title: '8. Retention',
      paragraphs: [
        'We retain personal information for as long as your account is active, as needed to provide the Service, and as required by your Organisation\'s policies or applicable law.',
        'When data is no longer needed, we delete or anonymise it in accordance with our retention practices and your Organisation\'s instructions where applicable.',
      ],
    ),
    LegalSection(
      title: '9. Security',
      paragraphs: [
        'We implement administrative, technical, and organisational measures designed to protect personal information, including access controls, encryption in transit where supported, and monitoring.',
        'No method of transmission or storage is completely secure. You are responsible for keeping your login credentials confidential and notifying your Organisation if you suspect unauthorised access.',
      ],
    ),
    LegalSection(
      title: '10. Your rights and choices',
      paragraphs: [
        'Depending on applicable law, you may have rights to access, correct, delete, restrict, or object to certain processing of your personal information, and to data portability where technically feasible.',
        'You can update many profile fields in the app. For other requests, contact your Organisation\'s HR administrator or email us at ${LegalConfig.contactEmail}.',
        'You can control location permissions through your device settings. Denying location may limit attendance features that require it.',
      ],
    ),
    LegalSection(
      title: '11. Children',
      paragraphs: [
        'The Service is intended for authorised workplace users and is not directed to children under 16. We do not knowingly collect personal information from children.',
      ],
    ),
    LegalSection(
      title: '12. Changes to this Policy',
      paragraphs: [
        'We may update this Privacy Policy from time to time. We will post the updated version in the app and update the "Last updated" date. Material changes may be communicated through the app or your Organisation where appropriate.',
        'Continued use of the Service after the effective date of an update constitutes acceptance of the revised Policy, unless otherwise required by law.',
      ],
    ),
    LegalSection(
      title: '13. Contact',
      paragraphs: [
        'Questions about this Privacy Policy: ${LegalConfig.contactEmail}',
        '${LegalConfig.legalEntityName}, ${LegalConfig.registeredAddress}',
      ],
    ),
  ];

  static final List<LegalSection> _termsSections = [
    LegalSection(
      title: '1. Acceptance',
      paragraphs: [
        'By downloading, installing, accessing, or using the ${LegalConfig.appName} app, you agree to these Terms. If you do not agree, do not use the Service.',
        'If you use the Service on behalf of an Organisation, you confirm you are authorised to do so and that your Organisation accepts these Terms for your use.',
      ],
    ),
    LegalSection(
      title: '2. The Service',
      paragraphs: [
        '${LegalConfig.appName} is a human resources management platform that may include attendance tracking, leave management, employee records, payroll or payslip viewing, reimbursements, holidays, and related features.',
        'Features available to you depend on your role and your Organisation\'s configuration. We may modify, suspend, or discontinue features with reasonable notice where practicable.',
      ],
    ),
    LegalSection(
      title: '3. Eligibility and accounts',
      paragraphs: [
        'You must be invited or registered by an authorised representative of your Organisation, or complete organisation signup where that flow is enabled.',
        'You must provide accurate information and keep your credentials secure. You are responsible for activity under your account unless you promptly report unauthorised use.',
        'We may suspend or terminate accounts that violate these Terms or pose a security risk.',
      ],
    ),
    LegalSection(
      title: '4. Acceptable use',
      paragraphs: [
        'You agree to use the Service only for lawful business purposes and in accordance with your Organisation\'s policies.',
        'You must not: (a) attempt unauthorised access to systems or data; (b) interfere with the Service; (c) upload malware or unlawful content; (d) misuse another person\'s data; (e) falsify attendance, leave, or reimbursement records; or (f) reverse engineer the app except where law permits.',
      ],
    ),
    LegalSection(
      title: '5. Organisation relationship',
      paragraphs: [
        'Your Organisation controls much of the data in the Service and decides who may access it. Employment decisions remain between you and your Organisation; the Service is a tool, not an employer.',
        'Questions about payroll amounts, leave approval, or HR records should be directed to your Organisation unless they relate to technical access to the app.',
      ],
    ),
    LegalSection(
      title: '6. Intellectual property',
      paragraphs: [
        'The Service, including software, design, and branding, is owned by ${LegalConfig.legalEntityName} or its licensors and is protected by intellectual property laws.',
        'You receive a limited, non-exclusive, non-transferable licence to use the app for authorised HR purposes during your access period.',
      ],
    ),
    LegalSection(
      title: '7. Third-party services',
      paragraphs: [
        'The Service may integrate with third-party services (for example, Google Sign-In or cloud infrastructure). Your use of those services may be subject to their separate terms and privacy policies.',
      ],
    ),
    LegalSection(
      title: '8. Disclaimers',
      paragraphs: [
        'The Service is provided "as is" and "as available" to the fullest extent permitted by law. We do not warrant uninterrupted or error-free operation.',
        'Payslip figures, leave balances, and attendance records depend on data entered by your Organisation and integrated systems. Verify critical information with your Organisation before relying on it for financial or legal decisions.',
      ],
    ),
    LegalSection(
      title: '9. Limitation of liability',
      paragraphs: [
        'To the maximum extent permitted by applicable law, ${LegalConfig.legalEntityName} and its officers, employees, and suppliers shall not be liable for indirect, incidental, special, consequential, or punitive damages, or loss of profits, data, or goodwill arising from your use of the Service.',
        'Our total liability for claims relating to the Service shall not exceed the greater of (a) amounts you paid us directly for the Service in the twelve months before the claim, or (b) INR 5,000, except where liability cannot be limited by law.',
      ],
    ),
    LegalSection(
      title: '10. Indemnity',
      paragraphs: [
        'You agree to indemnify and hold harmless ${LegalConfig.legalEntityName} against claims arising from your misuse of the Service or violation of these Terms, except to the extent caused by our gross negligence or wilful misconduct.',
      ],
    ),
    LegalSection(
      title: '11. Termination',
      paragraphs: [
        'You may stop using the Service at any time. Your Organisation or we may suspend or end your access when your employment ends, your account is deactivated, or these Terms are breached.',
        'Sections that by nature should survive termination (including intellectual property, disclaimers, limitation of liability, and governing law) will survive.',
      ],
    ),
    LegalSection(
      title: '12. Governing law and disputes',
      paragraphs: [
        'These Terms are governed by the laws of ${LegalConfig.governingLawRegion}, without regard to conflict-of-law principles.',
        'Courts located in Ahmedabad, Gujarat, India shall have exclusive jurisdiction, subject to mandatory consumer protection or employment laws that apply in your jurisdiction.',
      ],
    ),
    LegalSection(
      title: '13. Changes to Terms',
      paragraphs: [
        'We may update these Terms from time to time. The "Last updated" date will change when we do. Continued use after changes take effect constitutes acceptance unless applicable law requires otherwise.',
      ],
    ),
    LegalSection(
      title: '14. Contact',
      paragraphs: [
        'For questions about these Terms: ${LegalConfig.contactEmail}',
        '${LegalConfig.legalEntityName}, ${LegalConfig.registeredAddress}',
      ],
    ),
  ];
}
