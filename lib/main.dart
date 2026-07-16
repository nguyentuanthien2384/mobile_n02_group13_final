import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/helper/database.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'provider/theme_provider.dart';
import 'provider/folder_provider.dart';
import 'provider/social_provider.dart';
import 'screen/tag_management_screen.dart';
import 'screen/performance_test_screen.dart';
import 'screen/note_view_screen.dart';
import 'screen/statistics_screen.dart';
import 'screen/trash_screen.dart';
import 'screen/archived_notes_screen.dart';
import 'services/notification_service.dart';
import 'services/api_service.dart';
import 'screen/main_shell.dart';
import 'screen/onboarding_screen.dart';
import 'screen/settings_screen.dart';
import 'screen/folder_screen.dart';
import 'screen/shared_notes_screen.dart';
import 'screen/favorites_screen.dart';
import 'screen/security_screen.dart';
import 'screen/today_screen.dart';
import 'widget/app_lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Guard against [core/duplicate-app]: only initialize when no app exists yet
  // (the native side may auto-initialize from google-services.json, and hot
  // restart can re-run main() while the default app is still alive).
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
  }
  await NotificationService.instance.init();
  await ApiService.loadConfiguration();
  final themeProvider = ThemeProvider();
  await themeProvider.load();
  final database = await DatabaseHelper.database();
  final bool isLoggedIn = FirebaseAuth.instance.currentUser != null;

  final prefs = await SharedPreferences.getInstance();
  final bool onboardingCompleted =
      prefs.getBool('onboarding_completed') ?? false;
  String initialRoute;
  if (!onboardingCompleted) {
    initialRoute = '/onboarding';
  } else if (!isLoggedIn) {
    initialRoute = '/login';
  } else {
    initialRoute = '/';
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NoteProvider()),
        ChangeNotifierProvider(create: (_) => TagProvider()),
        ChangeNotifierProvider(create: (_) => FolderProvider()),
        ChangeNotifierProvider(create: (_) => SocialProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: TodoApp(
        database: database,
        isLoggedIn: isLoggedIn,
        initialRoute: initialRoute,
      ),
    ),
  );
}

/// Builds the light/dark [ThemeData] used by the app for the given brightness.
ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: brightness,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? scheme.surface
        : scheme.surfaceContainerHighest,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      iconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: GoogleFonts.lobster(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.bold,
      ),
    ),
    textTheme: GoogleFonts.robotoTextTheme(
      base.textTheme,
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
  );
}

class TodoApp extends StatefulWidget {
  final Database? database;
  final bool isLoggedIn;
  final String initialRoute;

  const TodoApp({
    super.key,
    this.database,
    required this.isLoggedIn,
    required this.initialRoute,
  });

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

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().mode;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      initialRoute: widget.initialRoute,
      routes: {
        '/login': (context) => const LoginScreen(),
        '/': (context) => const AppLockGate(child: MainShell()),
        '/detail': (context) => const RichDetailScreen(),
        '/todolist': (context) => const TodoListScreen(),
        '/search': (context) => const SearchScreen(),
        '/select': (context) => const SelectScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/tags': (context) => const TagManagementScreen(),
        '/performance-test': (context) => const PerformanceTestScreen(),
        '/view': (context) => const NoteViewScreen(),
        '/statistics': (context) => const StatisticsScreen(),
        '/trash': (context) => const TrashScreen(),
        '/archived': (context) => const ArchivedNotesScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/folders': (context) => const FolderScreen(),
        '/shared': (context) => const SharedNotesScreen(),
        '/favorites': (context) => const FavoritesScreen(),
        '/security': (context) => const SecurityScreen(),
        '/today': (context) => const TodayScreen(),
      },
      // Note: Deep link handling for email authentication
      // When app opens from email link, Android passes the link via intent
      // Firebase Auth will automatically process it if the link format is correct
      // The LoginScreen listens to auth state changes to handle successful sign-in
    );
  }
}
