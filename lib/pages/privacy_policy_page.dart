import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class PrivacyPolicyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.privacyPolicy),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Privacy Policy', // This should not be translated as it's a title
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 10),
            Text('Last updated: [Date]'), // Replace with actual date
            SizedBox(height: 20),
            Text(
              // IMPORTANT: Replace this with your actual privacy policy text.
              // This is just a placeholder.
              'Welcome to our app. This privacy policy explains how we collect, use, and share information about you when you use our mobile application and related services. \n\n'
              '1. Information We Collect\n'
              'We may collect information you provide directly to us, such as when you create an account, update your profile, or communicate with us. This information may include your name, email address, password, and any other information you choose to provide.\n\n'
              '2. How We Use Your Information\n'
              'We use the information we collect to operate, maintain, and provide you with the features and functionality of the service, to communicate with you, to monitor and improve our service, and for other customer service purposes.\n\n'
              '3. Sharing of Your Information\n'
              'We do not share your personal information with third parties except as described in this privacy policy...\n\n'
              '[...add all required sections...]'
            ),
          ],
        ),
      ),
    );
  }
}
