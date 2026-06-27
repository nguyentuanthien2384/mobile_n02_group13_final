import 'package:flutter/foundation.dart';
import 'package:todoapp/services/notification_api_service.dart';

/// Holds the unread-notification count so a badge can be shown app-wide.
class SocialProvider extends ChangeNotifier {
  int _unread = 0;
  int get unread => _unread;

  Future<void> refreshUnread() async {
    final count = await NotificationApiService.unreadCount();
    if (count != _unread) {
      _unread = count;
      notifyListeners();
    }
  }

  void setUnread(int value) {
    if (value != _unread) {
      _unread = value < 0 ? 0 : value;
      notifyListeners();
    }
  }

  void clear() {
    if (_unread != 0) {
      _unread = 0;
      notifyListeners();
    }
  }
}
