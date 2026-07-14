import 'package:flutter/material.dart';
import 'package:todoapp/services/security_service.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _loading = true;
  bool _hasPin = false;
  bool _biometric = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hasPin = await SecurityService.instance.hasPin();
    final biometric = await SecurityService.instance.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _biometric = biometric;
      _loading = false;
    });
  }

  Future<String?> _askForPin({
    required bool confirm,
    String title = 'Đặt PIN',
  }) async {
    final pin = TextEditingController();
    final again = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pin,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              decoration: const InputDecoration(labelText: 'PIN (4–8 số)'),
            ),
            if (confirm)
              TextField(
                controller: again,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 8,
                decoration: const InputDecoration(labelText: 'Nhập lại PIN'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              if (confirm && pin.text != again.text) return;
              Navigator.pop(dialogContext, pin.text);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    pin.dispose();
    again.dispose();
    return result;
  }

  Future<void> _setOrChangePin() async {
    if (_hasPin) {
      final oldPin = await _askForPin(
        confirm: false,
        title: 'Nhập PIN hiện tại',
      );
      if (oldPin == null) return;
      if (!await SecurityService.instance.verifyPin(oldPin)) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN hiện tại không đúng.')),
          );
        return;
      }
    }
    final pin = await _askForPin(
      confirm: true,
      title: _hasPin ? 'Đổi PIN' : 'Đặt PIN',
    );
    if (pin == null) return;
    try {
      await SecurityService.instance.setPin(pin);
      await _load();
    } on FormatException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _disablePin() async {
    final pin = await _askForPin(
      confirm: false,
      title: 'Xác nhận PIN để tắt khóa',
    );
    if (pin == null) return;
    if (!await SecurityService.instance.verifyPin(pin)) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PIN không đúng.')));
      return;
    }
    await SecurityService.instance.disablePin();
    await _load();
  }

  Future<void> _setBiometric(bool value) async {
    try {
      await SecurityService.instance.setBiometricEnabled(value);
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Khóa ứng dụng')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.pin_outlined),
                    title: Text(_hasPin ? 'Đổi PIN' : 'Đặt PIN'),
                    subtitle: Text(
                      _hasPin
                          ? 'Ứng dụng sẽ khóa khi quay lại từ nền.'
                          : 'Dùng PIN 4–8 chữ số để bảo vệ ghi chú.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _setOrChangePin,
                  ),
                ),
                if (_hasPin)
                  Card(
                    child: SwitchListTile(
                      secondary: const Icon(Icons.fingerprint),
                      title: const Text('Mở khóa bằng sinh trắc học'),
                      subtitle: const Text(
                        'Vân tay hoặc khuôn mặt của thiết bị',
                      ),
                      value: _biometric,
                      onChanged: _setBiometric,
                    ),
                  ),
                if (_hasPin)
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.lock_open_outlined,
                        color: Colors.red,
                      ),
                      title: const Text('Tắt khóa ứng dụng'),
                      onTap: _disablePin,
                    ),
                  ),
              ],
            ),
    );
  }
}
