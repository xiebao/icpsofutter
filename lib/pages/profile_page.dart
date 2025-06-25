import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../auth/auth_provider.dart';
import '../utils/app_routes.dart';
import 'package:ipcso_main/gen_l10n/app_localizations.dart';

class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  File? _avatar;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _avatar = File(pickedFile.path);
      });
      // TODO: Implement logic to upload the avatar to your server
      // and update the user's profile URL.
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Avatar selected. Upload logic needed.')));
    }
  }

  void _clearCache() {
    // This is a placeholder. Real cache clearing would depend on what you cache.
    // e.g., clearing image cache from a package like cached_network_image.
    setState(() {
      // Simulate clearing by removing selected avatar for demo
      _avatar = null; 
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Cache cleared (simulated).')));
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    // Check if the user is authenticated, if not, show a login prompt.
    if (!authProvider.isAuthenticated) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l10n.pleaseLogin),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.login),
              child: Text(l10n.login),
            ),
          ],
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profile),
        automaticallyImplyLeading: false, // No back button on this tab
      ),
      body: ListView(
        children: <Widget>[
          SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 50,
                backgroundImage: _avatar != null
                    ? FileImage(_avatar!)
                    : (authProvider.user?.avatarUrl != null
                        ? NetworkImage(authProvider.user!.avatarUrl!)
                        : null) as ImageProvider?,
                child: _avatar == null && authProvider.user?.avatarUrl == null
                    ? Icon(Icons.person, size: 50)
                    : null,
              ),
            ),
          ),
          SizedBox(height: 10),
          Center(child: Text(authProvider.user?.name ?? '', style: Theme.of(context).textTheme.headlineSmall)),
          Center(child: Text(authProvider.user?.email ?? '')),
          SizedBox(height: 30),
          ListTile(
            leading: Icon(Icons.password),
            title: Text(l10n.changePassword),
            onTap: () {
              // TODO: Navigate to a change password page
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Navigate to change password page.'))
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.settings),
            title: Text(l10n.settings),
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.settings),
          ),
          ListTile(
            leading: Icon(Icons.cleaning_services),
            title: Text(l10n.clearCache),
            onTap: _clearCache,
          ),
          ListTile(
            leading: Icon(Icons.privacy_tip),
            title: Text(l10n.privacyPolicy),
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.privacy),
          ),
          SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(l10n.logout),
              onPressed: () {
                Provider.of<AuthProvider>(context, listen: false).logout();
                // After logout, push to login and remove all previous routes
                Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
              },
            ),
          ),
        ],
      ),
    );
  }
}
