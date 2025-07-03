import 'package:flutter/foundation.dart';

class MessageMonitor extends ChangeNotifier {
  final List<String> _messages = [];

  List<String> get messages => List.unmodifiable(_messages);

  void addMqttMessage(String msg) {
    print(
        '[DEBUG][MessageMonitor] addMqttMessage: $msg, messages=${_messages.length + 1}');
    _messages.add('[MQTT-MessageMonitor] $msg');
    if (_messages.length > 50) _messages.removeAt(0);
    notifyListeners();
  }

  void addSendMessage(String msg) {
    print(
        '[DEBUG][MessageMonitor] addSendMessage: $msg, messages=${_messages.length + 1}');
    _messages.add('[SEND-MessageMonitor] $msg');
    if (_messages.length > 50) _messages.removeAt(0);
    notifyListeners();
  }

  void clear() {
    print('[DEBUG][MessageMonitor] clear, before=${_messages.length}');
    _messages.clear();
    notifyListeners();
  }
}

final messageMonitor = MessageMonitor();
