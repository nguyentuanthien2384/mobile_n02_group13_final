import 'package:flutter/material.dart';
import 'package:todoapp/services/security_service.dart';

/// Locks protected app content whenever the process returns to foreground.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _pin = TextEditingController();
  bool _checking = true;
  bool _locked = false;
  bool _biometricEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLockState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pin.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadLockState();
  }

  Future<void> _loadLockState() async {
    final hasPin = await SecurityService.instance.hasPin();
    final biometric = await SecurityService.instance.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _locked = hasPin;
      _biometricEnabled = biometric;
      _error = null;
    });
  }

  Future<void> _unlockWithPin() async {
    final valid = await SecurityService.instance.verifyPin(_pin.text);
    if (!mounted) return;
    if (valid) {
      setState(() {
        _locked = false;
        _error = null;
        _pin.clear();
      });
    } else {
      setState(() => _error = 'PIN không đúng. Hãy thử lại.');
    }
  }

  Future<void> _unlockWithBiometric() async {
    final valid = await SecurityService.instance.authenticateBiometric();
    if (valid && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_locked) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 72),
                const SizedBox(height: 16),
                Text(
                  'Ứng dụng đã khóa',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('Nhập PIN để mở ghi chú của bạn.'),
                const SizedBox(height: 24),
                TextField(
                  controller: _pin,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 8,
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _unlockWithPin(),
                  decoration: InputDecoration(
                    labelText: 'PIN',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _unlockWithPin,
                    child: const Text('Mở khóa'),
                  ),
                ),
                if (_biometricEnabled) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _unlockWithBiometric,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Dùng sinh trắc học'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
