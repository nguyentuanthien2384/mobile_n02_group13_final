import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Màn hình đăng nhập hỗ trợ 2 phương thức:
///   1. Google Sign-In
///   2. Email + Mật khẩu (đăng nhập / đăng ký)
///
/// Ghi chú: luồng "email link (passwordless)" cũ đã bị bỏ vì Firebase Dynamic
/// Links ngừng hoạt động từ 25/08/2025. Email + mật khẩu là cách thay thế
/// đơn giản, chạy ngay khi bật provider "Email/Password" trong Firebase Console.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;       // đang xử lý (email hoặc google)
  bool _isRegister = false; // false = đăng nhập, true = đăng ký
  bool _obscure = true;     // ẩn/hiện mật khẩu

  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // Khi đăng nhập thành công (Google hoặc Email), điều hướng về Home.
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null && mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  // ─────────────────────── GOOGLE SIGN-IN ───────────────────────
  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final googleSignIn = GoogleSignIn();
      // signOut trước để luôn hiện màn chọn tài khoản, tránh token cũ bị kẹt.
      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // Người dùng bấm hủy.
        if (mounted) setState(() => _busy = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      // Điều hướng do listener authStateChanges đảm nhiệm.
    } on FirebaseAuthException catch (e) {
      _showError('Đăng nhập Google thất bại: ${e.message ?? e.code}');
    } catch (e) {
      final msg = e.toString();
      // ApiException: 10 => chưa đăng ký SHA-1 của máy này trong Firebase.
      if (msg.contains('ApiException: 10') || msg.toLowerCase().contains('sign_in_failed')) {
        _showError(
          'Đăng nhập Google thất bại (ApiException 10).\n'
          'Máy bạn chưa được đăng ký SHA-1 trong Firebase project. '
          'Hãy thêm SHA-1 của máy vào Firebase rồi tải lại google-services.json.',
        );
      } else {
        _showError('Đăng nhập Google thất bại: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─────────────────────── EMAIL / PASSWORD ───────────────────────
  Future<void> _submitEmailPassword() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final auth = FirebaseAuth.instance;

    try {
      if (_isRegister) {
        await auth.createUserWithEmailAndPassword(email: email, password: password);
      } else {
        await auth.signInWithEmailAndPassword(email: email, password: password);
      }
      // Điều hướng do listener authStateChanges đảm nhiệm.
    } on FirebaseAuthException catch (e) {
      _showError(_mapAuthError(e));
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Email không hợp lệ.';
      case 'user-disabled':
        return 'Tài khoản này đã bị vô hiệu hóa.';
      case 'user-not-found':
        return 'Không tìm thấy tài khoản. Hãy đăng ký trước.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email hoặc mật khẩu không đúng.';
      case 'email-already-in-use':
        return 'Email này đã được đăng ký. Hãy đăng nhập.';
      case 'weak-password':
        return 'Mật khẩu quá yếu (cần từ 6 ký tự trở lên).';
      case 'too-many-requests':
        return 'Thử quá nhiều lần. Vui lòng đợi vài phút.';
      case 'operation-not-allowed':
        return 'Chưa bật đăng nhập Email/Password trong Firebase Console.';
      default:
        return e.message ?? 'Đăng nhập thất bại (${e.code}).';
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Vui lòng nhập email';
    final emailRegex = RegExp(r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$');
    if (!emailRegex.hasMatch(value.trim())) return 'Email không hợp lệ';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Vui lòng nhập mật khẩu';
    if (value.length < 6) return 'Mật khẩu cần ít nhất 6 ký tự';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: theme.colorScheme.primary,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Text(
                          'My Note',
                          style: GoogleFonts.lobster(fontSize: 40, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _isRegister ? 'Đăng ký tài khoản' : 'Đăng nhập',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      // EMAIL
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: _validateEmail,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          hintText: 'Email',
                          prefixIcon: const Icon(Icons.email, color: Color(0xFF4285F4)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // PASSWORD
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscure,
                        validator: _validatePassword,
                        onFieldSubmitted: (_) => _submitEmailPassword(),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          hintText: 'Mật khẩu',
                          prefixIcon: const Icon(Icons.lock, color: Color(0xFF4285F4)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_off : Icons.visibility,
                              color: Colors.black45,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // NÚT ĐĂNG NHẬP / ĐĂNG KÝ
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _busy ? null : _submitEmailPassword,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28)),
                            backgroundColor: Colors.white,
                            foregroundColor: theme.colorScheme.primary,
                          ),
                          child: _busy
                              ? const SizedBox(
                                  height: 20, width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  _isRegister ? 'Đăng ký' : 'Đăng nhập',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // CHUYỂN ĐĂNG NHẬP <-> ĐĂNG KÝ
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _isRegister = !_isRegister),
                        child: Text(
                          _isRegister
                              ? 'Đã có tài khoản? Đăng nhập'
                              : 'Chưa có tài khoản? Đăng ký',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                              child: Divider(
                                  color: Colors.white.withValues(alpha: 0.5))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('HOẶC',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontWeight: FontWeight.w600)),
                          ),
                          Expanded(
                              child: Divider(
                                  color: Colors.white.withValues(alpha: 0.5))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // GOOGLE
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _signInWithGoogle,
                          icon: Icon(PhosphorIconsDuotone.googleLogo,
                              color: const Color(0xFF4285F4), size: 20),
                          label: Text(
                            'Đăng nhập với Google',
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28)),
                            side: const BorderSide(color: Colors.white, width: 0),
                            foregroundColor: theme.colorScheme.primary,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
