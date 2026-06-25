import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/helper/database.dart';
import 'screen/home_screen.dart';
import 'screen/search_screen.dart';
import 'screen/select_screen.dart';
import 'package:provider/provider.dart';
import 'class/note.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'screen/login_screen.dart';
import 'screen/profile_screen.dart';
import 'screen/todo_list_screen.dart';
import 'screen/rich_detail_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'provider/tag_provider.dart';
import 'screen/tag_management_screen.dart';
import 'screen/performance_test_screen.dart';
import 'screen/note_view_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Allow runtime font fetching with fallback to system font
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final database = await DatabaseHelper.database();
  final bool isLoggedIn = FirebaseAuth.instance.currentUser != null;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NoteProvider()),
        ChangeNotifierProvider(create: (_) => TagProvider()),
      ],
      child: TodoApp(database: database, isLoggedIn: isLoggedIn),
    ),
  );
}

class TodoApp extends StatefulWidget {
  final Database? database;
  final bool isLoggedIn;

  const TodoApp({super.key, this.database, required this.isLoggedIn});

  @override
  State<TodoApp> createState() => _TodoAppState();
}

class _TodoAppState extends State<TodoApp> {
  @override
  void initState() {
    super.initState();
    _checkEmailLink();
  }

  Future<void> _checkEmailLink() async {
    // Check if app was opened from an email link
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    
    // If user is not logged in, check for email link
    if (user == null) {
      // This will be handled by the LoginScreen when it checks for auth state changes
      // We listen to auth state changes to handle email link sign-in
      auth.authStateChanges().listen((User? user) {
        if (user != null && mounted) {
          // User signed in, navigate to home
          Navigator.of(context).pushReplacementNamed('/');
        }
      });
    }
  }

  Future<bool> _handleEmailLink(BuildContext context, String link) async {
    try {
      final auth = FirebaseAuth.instance;
      
      // Check if this is a sign-in email link
      if (auth.isSignInWithEmailLink(link)) {
        // Retrieve the saved email
        final prefs = await SharedPreferences.getInstance();
        final email = prefs.getString('emailForSignIn');
        
        if (email == null || email.isEmpty) {
          // Email not found, show error
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please request a new sign-in link'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return false;
        }

        // Sign in with email link
        final userCredential = await auth.signInWithEmailLink(
          email: email,
          emailLink: link,
        );

        // Clear saved email
        await prefs.remove('emailForSignIn');

        if (userCredential.user != null && mounted) {
          Navigator.of(context).pushReplacementNamed('/');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Successfully signed in!'),
              backgroundColor: Colors.green,
            ),
          );
          return true;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign-in failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        appBarTheme: AppBarTheme(
          backgroundColor: Theme.of(context).colorScheme.primary,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: GoogleFonts.lobster(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        textTheme: GoogleFonts.robotoTextTheme(
          Theme.of(context).textTheme,
        ).apply(
          bodyColor: Theme.of(context).colorScheme.onSurface,
          displayColor: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      initialRoute: widget.isLoggedIn ? '/' : '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/': (context) => HomeScreen(database: widget.database),
        '/detail': (context) => const RichDetailScreen(),
        '/todolist': (context) => const TodoListScreen(),
        '/search': (context) => const SearchScreen(),
        '/select': (context) => const SelectScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/tags': (context) => const TagManagementScreen(),
        '/performance-test': (context) => const PerformanceTestScreen(),
        '/view': (context) => const NoteViewScreen(),
      },
      // Note: Deep link handling for email authentication
      // When app opens from email link, Android passes the link via intent
      // Firebase Auth will automatically process it if the link format is correct
      // The LoginScreen listens to auth state changes to handle successful sign-in
    );
  }
}
