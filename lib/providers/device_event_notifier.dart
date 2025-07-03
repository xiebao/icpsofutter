import 'package:flutter/foundation.dart';

enum DeviceEventType { online, offline, statusChanged, mqtt, send }

class DeviceEvent {
  final DeviceEventType type;
  final String deviceId;
  final String message;
  final DateTime time;
  DeviceEvent(this.type, this.deviceId, this.message, {DateTime? time})
      : time = time ?? DateTime.now();
}

class DeviceEventNotifier extends ChangeNotifier {
  final List<DeviceEvent> _events = [];

  List<DeviceEvent> get events => List.unmodifiable(_events);

  void addEvent(DeviceEvent event) {
    _events.add(event);
    if (_events.length > 100) _events.removeAt(0);
    notifyListeners();
  }

  void clear() {
    _events.clear();
    notifyListeners();
  }
}

final deviceEventNotifier = DeviceEventNotifier();
