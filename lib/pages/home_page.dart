import 'package:flutter/material.dart';
import 'package:ipcso_main/gen_l10n/app_localizations.dart';
import 'p2p_video_main_page.dart';
import 'p2p_video_simple_page.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  bool _isGrid = false; // false: 一行一个, true: 一行两个

  final List<Map<String, String>> _devices = [
    {
      'devId': 'camId123',
      'deviceName': '客厅',
      'type': 'camera',
      'desc': 'v智能云台机',
    },
    {
      'devId': 'camId123',
      'deviceName': '客厅的',
      'type': 'tv',
      'desc': '长期离线',
    },
  ];

  void onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _addDevice() {
    Navigator.of(context).pushNamed('/wifi_config');
    return;
    // // TODO: 跳转到添加设备流程
    // showDialog(
    //   context: context,
    //   builder: (_) => AlertDialog(
    //     title: Text('添加设备'),
    //     content: Text('这里可以实现添加设备的流程。'),
    //     actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('关闭'))],
    //   ),
    // );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black;
    return Scaffold(
        appBar: AppBar(
          elevation: 0,
          title: Row(
            children: [
              Icon(Icons.home, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text('我的家庭', style: theme.textTheme.titleLarge),
              const SizedBox(width: 8),
              Icon(Icons.keyboard_arrow_down,
                  color: colorScheme.onSurface.withOpacity(0.7), size: 20),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.add, color: colorScheme.primary),
              tooltip: '添加设备',
              onPressed: _addDevice,
            ),
            // IconButton(
            //   icon: Icon(Icons.wifi, color: colorScheme.primary),
            //   tooltip: 'WiFi配网',
            //   onPressed: () {
            //     Navigator.of(context).pushNamed('/wifi_config');
            //   },
            // ),
            IconButton(
              icon: Icon(Icons.system_update, color: colorScheme.primary),
              tooltip: '升级测试',
              onPressed: () {
                Navigator.of(context).pushNamed('/test_update');
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 房间tab
              Row(
                children: [
                  _RoomTab(text: '全屋', selected: true, textColor: textColor),
                  _RoomTab(text: '客厅', textColor: textColor),
                  _RoomTab(text: '未分配房间', textColor: textColor),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                        _isGrid
                            ? Icons.view_agenda_outlined
                            : Icons.grid_view_outlined,
                        color: colorScheme.primary.withOpacity(0.74)),
                    tooltip: _isGrid ? '切换为单列' : '切换为双列',
                    onPressed: () {
                      setState(() {
                        _isGrid = !_isGrid;
                      });
                    },
                  ),
                  Icon(Icons.menu,
                      color: colorScheme.onSurface.withOpacity(0.38)),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isGrid
                    ? GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.1,
                        children: [
                          ..._devices.map((d) => _DeviceCard(
                                devId: d['devId']!,
                                deviceName: d['deviceName']!,
                                type: d['type']!,
                                desc: d['desc']!,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => P2pVideoSimplePage(
                                        devId: d['devId']!,
                                        deviceName: d['deviceName']!,
                                      ),
                                    ),
                                  );
                                },
                                isGrid: true,
                              )),
                          _TestDeviceCard(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        P2pVideoMainPage(devId: 'camId123'),
                                  ),
                                );
                              },
                              isGrid: true),
                        ],
                      )
                    : ListView(
                        children: [
                          ..._devices.map((d) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _DeviceCard(
                                  devId: d['devId']!,
                                  deviceName: d['deviceName']!,
                                  type: d['type']!,
                                  desc: d['desc']!,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            P2pVideoSimplePage(
                                          devId: d['devId']!,
                                          deviceName: d['deviceName']!,
                                        ),
                                      ),
                                    );
                                  },
                                  isGrid: false,
                                ),
                              )),
                          _TestDeviceCard(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        P2pVideoMainPage(devId: 'camId123'),
                                  ),
                                );
                              },
                              isGrid: false),
                        ],
                      ),
              ),
            ],
          ),
        ));
  }
}

class _RoomTab extends StatelessWidget {
  final String text;
  final bool selected;
  final Color? textColor;
  const _RoomTab({required this.text, this.selected = false, this.textColor});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Text(
        text,
        style: TextStyle(
          color: selected
              ? (textColor ?? Colors.black)
              : (textColor?.withOpacity(0.54) ?? Colors.black54),
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final String devId;
  final String deviceName;
  final String type;
  final String desc;
  final VoidCallback onTap;
  final bool isGrid;
  const _DeviceCard(
      {required this.devId,
      required this.deviceName,
      required this.type,
      required this.desc,
      required this.onTap,
      this.isGrid = false});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black;
    IconData iconData = Icons.devices_other;
    if (type == 'camera') iconData = Icons.videocam;
    if (type == 'tv') iconData = Icons.tv;
    final cardHeight = isGrid ? 170.0 : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: cardHeight,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: colorScheme.primary.withOpacity(0.18), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.2),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(iconData, color: colorScheme.primary, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(deviceName,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: colorScheme.primary.withOpacity(0.08),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      minimumSize: Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onTap,
                    child: Text('进入', style: theme.textTheme.labelLarge),
                  ),
                ],
              ),
              if (isGrid) const Spacer(),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  desc,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: textColor.withOpacity(0.7)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestDeviceCard extends StatelessWidget {
  final VoidCallback onTap;
  final bool isGrid;
  const _TestDeviceCard({required this.onTap, this.isGrid = false});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black;
    final cardHeight = isGrid ? 160.0 : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: cardHeight,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: colorScheme.primary.withOpacity(0.18), width: 1.2),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam,
                    color: colorScheme.primary.withOpacity(0.54), size: 36),
                SizedBox(height: 8),
                Text('测试设备',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: textColor.withOpacity(0.54))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
