import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores only a salted PIN hash and keeps every lock setting account-scoped.
class SecurityService {
  SecurityService._();

  static final instance = SecurityService._();
  final LocalAuthentication _auth = LocalAuthentication();

  String get _accountKey => FirebaseAuth.instance.currentUser?.uid ?? 'guest';
  String get _pinKey => 'app_pin_hash_$_accountKey';
  String get _biometricKey => 'app_biometric_$_accountKey';

  String _hash(String pin) =>
      sha256.convert(utf8.encode('todoapp:$_accountKey:$pin')).toString();

  Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_pinKey);
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw const FormatException('PIN phải gồm 4 đến 8 chữ số.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, _hash(pin));
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pinKey);
    return saved != null && saved == _hash(pin);
  }

  Future<void> disablePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey);
    await prefs.remove(_biometricKey);
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (enabled && !await canUseBiometrics()) {
      throw StateError('Thiết bị chưa cài khóa sinh trắc học.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, enabled);
  }

  Future<bool> authenticateBiometric() async {
    if (!await isBiometricEnabled()) return false;
    try {
      return await _auth.authenticate(
        localizedReason: 'Xác thực để mở ghi chú của bạn',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
