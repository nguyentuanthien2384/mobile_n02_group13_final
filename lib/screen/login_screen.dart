import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSendingLink = false;
  bool _linkSent = false;

  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _checkEmailLink();
    // Listen to auth state changes to handle email link sign-in
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
    super.dispose();
  }


  Future<void> _checkEmailLink() async {
    // Check if app was opened from an email link
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('emailForSignIn');
    
    if (email != null && email.isNotEmpty) {
      // Try to get the current link if app was opened from email
      // This will be handled when user clicks the link and app opens
      // The link is processed by Android and passed to Firebase Auth automatically
    }
  }
  

  Future<void> _signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // canceled
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google sign-in failed: $e')),
        );
      }
    }
  }

  Future<void> _sendSignInLink() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final email = _emailController.text.trim();
    
    setState(() {
      _isSendingLink = true;
    });

    try {
      // Construct ActionCodeSettings
      // URL must be whitelisted in Firebase Console → Authentication → Settings → Authorized domains
      // Use domain root - Firebase will handle the auth path automatically
      final actionCodeSettings = ActionCodeSettings(
        url: 'https://mobile-final-3.firebaseapp.com',
        handleCodeInApp: true,
        androidPackageName: 'com.example.todoapp',
        androidMinimumVersion: '12',
        iOSBundleId: 'com.example.todoapp',
      );

      // Save email locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('emailForSignIn', email);

      await FirebaseAuth.instance.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: actionCodeSettings,
      );

      if (mounted) {
        setState(() {
          _isSendingLink = false;
          _linkSent = true;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign-in link sent! Check your email.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isSendingLink = false;
        });
        
        String errorMessage = 'Failed to send email';
        if (e.code == 'invalid-email') {
          errorMessage = 'Invalid email address';
        } else if (e.code == 'user-disabled') {
          errorMessage = 'This account has been disabled';
        } else if (e.code == 'too-many-requests') {
          errorMessage = 'Too many requests. Please wait a few minutes before trying again.';
        } else if (e.message != null && e.message!.toLowerCase().contains('blocked')) {
          errorMessage = 'Too many requests from this device. Please wait 30-60 minutes before trying again, or use Google sign-in instead.';
        } else {
          errorMessage = e.message ?? 'Failed to send email: ${e.code}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSendingLink = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
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
                            style: GoogleFonts.lobster(
                              fontSize: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (!_linkSent) ...[
                          Text(
                            'Sign in with Email',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'We\'ll send you a sign-in link to your email',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofocus: true,
                            validator: _validateEmail,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              hintText: 'Enter your email',
                              prefixIcon: const Icon(Icons.email, color: Color(0xFF4285F4)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(28),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSendingLink ? null : _sendSignInLink,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                backgroundColor: Colors.white,
                                foregroundColor: theme.colorScheme.primary,
                              ),
                              child: _isSendingLink
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          PhosphorIconsDuotone.paperPlaneTilt,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Send Sign-in Link',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.5))),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'OR',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.5))),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _signInWithGoogle,
                              icon: Icon(
                                PhosphorIconsDuotone.googleLogo,
                                color: const Color(0xFF4285F4),
                                size: 20,
                              ),
                              label: Text(
                                'Sign in with Google',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                side: const BorderSide(color: Colors.white, width: 0),
                                foregroundColor: theme.colorScheme.primary,
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ] else ...[
                          Icon(
                            PhosphorIconsDuotone.envelope,
                            size: 64,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Check your email',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'We sent a sign-in link to ${_emailController.text}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Click the link in the email to sign in. You can close this screen and return after clicking the link.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _linkSent = false;
                                _emailController.clear();
                              });
                            },
                            child: Text(
                              'Use a different email',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                            ),
                          ),
                        ],
                      ],
                    ),
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