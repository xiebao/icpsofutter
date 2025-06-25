import 'package:flutter/material.dart';

class DeviceSettingsPage extends StatelessWidget {
  final String devId;
  final String deviceName;
  const DeviceSettingsPage({Key? key, required this.devId, required this.deviceName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('设置', style: theme.textTheme.titleLarge),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _SectionTitle(title: '功能设置', textColor: textColor),
          _SettingsItem(title: '本地相册', onTap: () {}),
          _SettingsItem(title: '录像设置', onTap: () {}),
          _SettingsItem(title: '报警设置', onTap: () {}),
          _SettingsItem(title: '云存储设置', onTap: () {}),
          _SettingsItem(title: '摄像机设置', onTap: () {}),
          const SizedBox(height: 16),
          _SectionTitle(title: '通用设置', textColor: textColor),
          _SettingsItem(
            title: '设备名称',
            subtitle: deviceName,
            onTap: () {},
          ),
          _SettingsItem(title: '位置管理', onTap: () {}),
          _SettingsItem(title: '设备共享', onTap: () {}),
          _SettingsItem(title: '智能场景', onTap: () {}),
          _SettingsItem(title: '产品百科', onTap: () {}),
          _SettingsItem(title: '固件升级', onTap: () {}),
          _SettingsItem(title: '帮助与反馈', onTap: () {}),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color? textColor;
  const _SectionTitle({required this.title, this.textColor});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: TextStyle(color: textColor?.withOpacity(0.54) ?? Colors.black54, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  const _SettingsItem({required this.title, this.subtitle, this.onTap});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(color: textColor)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: textColor.withOpacity(0.54))),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: colorScheme.primary.withOpacity(0.38)),
            ],
          ),
        ),
      ),
    );
  }
} 