import 'package:flutter/material.dart';

class DeviceSettingsPage extends StatelessWidget {
  final String devId;
  final String deviceName;
  const DeviceSettingsPage({Key? key, required this.devId, required this.deviceName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('设置', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _SectionTitle(title: '功能设置'),
          _SettingsItem(title: '本地相册', onTap: () {}),
          _SettingsItem(title: '录像设置', onTap: () {}),
          _SettingsItem(title: '报警设置', onTap: () {}),
          _SettingsItem(title: '云存储设置', onTap: () {}),
          _SettingsItem(title: '摄像机设置', onTap: () {}),
          const SizedBox(height: 16),
          _SectionTitle(title: '通用设置'),
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
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold),
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
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 17)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
} 