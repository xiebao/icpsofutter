import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_provider.dart';
import '../utils/app_router.dart';
import 'package:ipcso_main/gen_l10n/app_localizations.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _isLoading = false;

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {
        _isLoading = true;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.login(_email, _password);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (success) {
          final args = ModalRoute.of(context)?.settings.arguments as Map?;
          if (args != null && args['redirect'] != null) {
            Navigator.of(context).pushReplacementNamed(args['redirect']);
            // 如果有原请求信息，可以在这里重试原请求
            // 例如：DioClient.instance._dio.fetch(args['originalRequest']);
          } else {
            Navigator.of(context).pushReplacementNamed(AppRouter.root);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.loginFailed)),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.login)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TextFormField(
                  decoration: InputDecoration(labelText: l10n.username),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) =>
                      value!.isEmpty ? l10n.emailRequired : null,
                  onSaved: (value) => _email = value!,
                ),
                SizedBox(height: 12),
                TextFormField(
                  decoration: InputDecoration(labelText: l10n.password),
                  obscureText: true,
                  validator: (value) =>
                      value!.isEmpty ? l10n.passwordRequired : null,
                  onSaved: (value) => _password = value!,
                ),
                SizedBox(height: 20),
                if (_isLoading)
                  CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: _submit,
                    child: Text(l10n.login),
                  ),
                TextButton(
                  onPressed: () {
                    // Navigate to register page
                  },
                  child: Text(l10n.dontHaveAccount),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRouter.privacy),
                  child: Text(l10n.privacyPolicy),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
