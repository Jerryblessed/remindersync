import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/**
 * REMINDERSYNC AI - PRODUCTION APP
 * Built for RevenueCat Shipaton 2026
 * Features: Natural Language Thought Capture, Reusable Action Snippets,
 * Offline-First Cloud Sync, RevenueCat IAP Subscriptions & Credits
 */

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize RevenueCat with your designated ReminderSync Android Key
  await Purchases.configure(
    PurchasesConfiguration('goog_BvgJzoXXmvaDyUlsZGzKtnGXIMH'),
  );

  runApp(const ReminderSyncApp());
}

class ReminderSyncApp extends StatelessWidget {
  const ReminderSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReminderSync AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5), // Indigo Accent
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

// === MODELS ===

enum UserTier { free, pro, premium }

class UserSession {
  final String userId;
  final String email;
  int trialsRemaining;
  UserTier tier;

  UserSession({
    required this.userId,
    required this.email,
    this.trialsRemaining = 5,
    this.tier = UserTier.free,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
    userId: json['user_id']?.toString() ?? '',
    email: json['email'] ?? '',
    trialsRemaining: json['trials_remaining'] ?? 5,
    tier: UserTier.values.firstWhere(
      (t) => t.toString().split('.').last == (json['tier'] ?? 'free'),
      orElse: () => UserTier.free,
    ),
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'email': email,
    'trials_remaining': trialsRemaining,
    'tier': tier.toString().split('.').last,
  };
}

class ReminderItem {
  final String id;
  String title;
  String description; // Stores both context notes and Action Snippets
  DateTime dateTime;
  String? recurringPattern;
  bool isCompleted;
  DateTime updatedAt;

  ReminderItem({
    required this.id,
    required this.title,
    this.description = '',
    required this.dateTime,
    this.recurringPattern,
    this.isCompleted = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory ReminderItem.fromJson(Map<String, dynamic> json) => ReminderItem(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    dateTime: DateTime.tryParse(json['datetime'] ?? '') ?? DateTime.now(),
    recurringPattern: json['recurring_pattern'],
    isCompleted: json['is_completed'] == 1 || json['is_completed'] == true,
    updatedAt:
        json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'])
            : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'datetime': dateTime.toIso8601String(),
    'recurring_pattern': recurringPattern,
    'is_completed': isCompleted ? 1 : 0,
    'updated_at': updatedAt.toIso8601String(),
  };
}

// === API SERVICE ===

class ApiService {
  static const String baseUrl =
      'https://remind-e4a7h4e6a7g9gqgd.eastus-01.azurewebsites.net';

  static Future<Map<String, dynamic>> register(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<List<ReminderItem>> getReminders(String userId) async {
    final response = await http.get(Uri.parse('$baseUrl/reminders/$userId'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body)['reminders'] ?? [];
      return data.map((r) => ReminderItem.fromJson(r)).toList();
    }
    return [];
  }

  static Future<bool> createReminder(
    String userId,
    ReminderItem reminder,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reminders/$userId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(reminder.toJson()),
    );
    return response.statusCode == 200;
  }

  static Future<bool> updateReminder(
    String userId,
    ReminderItem reminder,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/reminders/$userId/${reminder.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(reminder.toJson()),
    );
    return response.statusCode == 200;
  }

  static Future<bool> deleteReminder(String userId, String reminderId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/reminders/$userId/$reminderId'),
    );
    return response.statusCode == 200;
  }

  static Future<Map<String, dynamic>> parseReminderWithAI(
    String userId,
    String naturalText,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ai/parse-reminder'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'text': naturalText}),
    );
    return jsonDecode(response.body);
  }

  static Future<List<ReminderItem>> syncReminders(
    String userId,
    List<ReminderItem> localReminders,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/sync/$userId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'reminders': localReminders.map((r) => r.toJson()).toList(),
      }),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body)['reminders'] ?? [];
      return data.map((r) => ReminderItem.fromJson(r)).toList();
    }
    return localReminders;
  }
}

// === AUTH WRAPPER ===

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  UserSession? session;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_session');

    if (userData != null) {
      setState(() {
        session = UserSession.fromJson(jsonDecode(userData));
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
    }
  }

  void handleAuth(UserSession user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_session', jsonEncode(user.toJson()));
    setState(() => session = user);

    // === SYNC WITH REVENUECAT ===
    try {
      // 1. Identify the user by your database user_id
      await Purchases.logIn(user.userId);

      // 2. Attach their email
      await Purchases.setEmail(user.email);

      // 3. Attach phone number (if you collect it)
      // await Purchases.setPhoneNumber('+1234567890');

      // 4. Attach any custom metadata (e.g. app name)
      await Purchases.setAttributes({
        'app_name': 'ReminderSync',
        'signup_tier': user.tier.toString(),
      });
    } catch (e) {
      // Non-blocking error handling
      debugPrint('RevenueCat user sync error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return session == null
        ? LoginScreen(onSuccess: handleAuth)
        : MainNavigation(
          user: session!,
          onSessionUpdate: (u) => setState(() => session = u),
        );
  }
}

// === LOGIN SCREEN ===

class LoginScreen extends StatefulWidget {
  final Function(UserSession) onSuccess;
  const LoginScreen({super.key, required this.onSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isLogin = true;
  bool isLoading = false;
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);

    try {
      final response =
          isLogin
              ? await ApiService.login(
                _emailController.text,
                _passController.text,
              )
              : await ApiService.register(
                _emailController.text,
                _passController.text,
              );

      if (response['success'] == true) {
        widget.onSuccess(UserSession.fromJson(response['user']));
      } else {
        _showError(response['message'] ?? 'Authentication failed');
      }
    } catch (e) {
      _showError('Network error. Check connection.');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.sync_alt_rounded,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ReminderSync AI',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Thought capture with 1-tap action snippets',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                    const SizedBox(height: 36),

                    // Email Field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Email address',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator:
                          (v) =>
                              v!.contains('@') ? null : 'Valid email required',
                    ),
                    const SizedBox(height: 14),

                    // Password Field
                    TextFormField(
                      controller: _passController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator:
                          (v) => v!.length >= 6 ? null : 'Min 6 characters',
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF4F46E5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child:
                            isLoading
                                ? const CircularProgressIndicator()
                                : Text(
                                  isLogin ? 'Sign In' : 'Create Free Account',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: () => setState(() => isLogin = !isLogin),
                      child: Text(
                        isLogin
                            ? 'New shipper? Create an account'
                            : 'Already have an account? Sign In',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// === MAIN NAVIGATION ===

class MainNavigation extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onSessionUpdate;

  const MainNavigation({
    super.key,
    required this.user,
    required this.onSessionUpdate,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _updatePages();
  }

  @override
  void didUpdateWidget(MainNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      _updatePages();
    }
  }

  void _updatePages() {
    _pages = [
      TimelineScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      SnippetVaultScreen(user: widget.user),
      UpgradeScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      SettingsScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        elevation: 0,
        backgroundColor: Colors.white,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'Timeline',
          ),
          NavigationDestination(
            icon: Icon(Icons.content_copy_outlined),
            selectedIcon: Icon(Icons.content_copy),
            label: 'Snippets',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'Upgrade',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// === TIMELINE SCREEN ===

class TimelineScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const TimelineScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<ReminderItem> _reminders = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String _filter = 'All'; // All, Today, Upcoming, Completed

  final _quickCaptureController = TextEditingController();
  bool _isParsingAI = false;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    setState(() => _isLoading = true);
    final list = await ApiService.getReminders(widget.user.userId);
    setState(() {
      _reminders = list;
      _isLoading = false;
    });
  }

  Future<void> _sync() async {
    setState(() => _isSyncing = true);
    final updated = await ApiService.syncReminders(
      widget.user.userId,
      _reminders,
    );
    setState(() {
      _reminders = updated;
      _isSyncing = false;
    });
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cloud sync complete!'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // AI Brain-Dump Quick Parser
  Future<void> _handleAIBrainDump() async {
    final text = _quickCaptureController.text.trim();
    if (text.isEmpty) return;

    if (widget.user.trialsRemaining <= 0 && widget.user.tier == UserTier.free) {
      _showUpgradePrompt();
      return;
    }

    setState(() => _isParsingAI = true);
    HapticFeedback.mediumImpact();

    try {
      final response = await ApiService.parseReminderWithAI(
        widget.user.userId,
        text,
      );

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        final newItem = ReminderItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: data['title'] ?? text,
          description: data['description'] ?? 'Captured via AI Brain Dump',
          dateTime:
              DateTime.tryParse(data['datetime'] ?? '') ??
              DateTime.now().add(const Duration(hours: 2)),
          recurringPattern: data['recurring']?['type'],
        );

        await ApiService.createReminder(widget.user.userId, newItem);

        if (widget.user.trialsRemaining > 0) {
          widget.user.trialsRemaining--;
          widget.onUpdate(widget.user);
        }

        _quickCaptureController.clear();
        _loadReminders();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scheduled: "${newItem.title}"'),
            backgroundColor: const Color(0xFF4F46E5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Could not parse thought'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error parsing thought')));
    } finally {
      setState(() => _isParsingAI = false);
    }
  }

  void _showUpgradePrompt() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Out of AI Credits'),
            content: const Text(
              'Upgrade to Pro or grab a credit pack to enjoy unlimited Gemini 3 thought capture and sync!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Upgrade'),
              ),
            ],
          ),
    );
  }

  List<ReminderItem> get filteredReminders {
    final now = DateTime.now();
    return _reminders.where((item) {
      if (_filter == 'Completed') return item.isCompleted;
      if (item.isCompleted) return false;

      if (_filter == 'Today') {
        return item.dateTime.year == now.year &&
            item.dateTime.month == now.month &&
            item.dateTime.day == now.day;
      }
      if (_filter == 'Upcoming') {
        return item.dateTime.isAfter(now);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Focus Timeline',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              avatar: const Icon(Icons.bolt, size: 16, color: Colors.amber),
              label: Text(
                '${widget.user.trialsRemaining} AI',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              backgroundColor: const Color(0xFFEEF2FF),
            ),
          ),
          IconButton(
            onPressed: _isSyncing ? null : _sync,
            icon:
                _isSyncing
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.cloud_sync_outlined),
            tooltip: 'Sync across devices',
          ),
        ],
      ),
      body: Column(
        children: [
          // AI Natural Language Brain Dump Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quickCaptureController,
                    decoration: const InputDecoration(
                      hintText:
                          'e.g. Call Marcus tomorrow 2pm with pitch deck...',
                      hintStyle: TextStyle(fontSize: 13),
                      prefixIcon: Icon(
                        Icons.auto_awesome,
                        color: Color(0xFF4F46E5),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                    ),
                    onSubmitted: (_) => _handleAIBrainDump(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isParsingAI ? null : _handleAIBrainDump,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                  ),
                  icon:
                      _isParsingAI
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : const Icon(Icons.arrow_upward, color: Colors.white),
                ),
              ],
            ),
          ),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children:
                  ['All', 'Today', 'Upcoming', 'Completed'].map((f) {
                    final isSelected = _filter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(f),
                        selected: isSelected,
                        onSelected: (val) => setState(() => _filter = f),
                        backgroundColor: Colors.white,
                        selectedColor: const Color(0xFFEEF2FF),
                        labelStyle: TextStyle(
                          color:
                              isSelected
                                  ? const Color(0xFF4F46E5)
                                  : Colors.grey.shade700,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color:
                                isSelected
                                    ? const Color(0xFF4F46E5)
                                    : Colors.grey.shade300,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),

          // Reminders List
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredReminders.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.checklist_rtl_rounded,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No reminders found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                    : RefreshIndicator(
                      onRefresh: _loadReminders,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredReminders.length,
                        itemBuilder: (context, index) {
                          final item = filteredReminders[index];
                          return _ReminderCard(
                            item: item,
                            onToggle: () async {
                              item.isCompleted = !item.isCompleted;
                              item.updatedAt = DateTime.now();
                              await ApiService.updateReminder(
                                widget.user.userId,
                                item,
                              );
                              setState(() {});
                              HapticFeedback.lightImpact();
                            },
                            onDelete: () async {
                              await ApiService.deleteReminder(
                                widget.user.userId,
                                item.id,
                              );
                              _loadReminders();
                            },
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final ReminderItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ReminderCard({
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });

  void _copySnippet(BuildContext context) {
    if (item.description.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: item.description));
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Action snippet copied to clipboard! 📋'),
          duration: Duration(milliseconds: 1500),
          backgroundColor: Color(0xFF4F46E5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOverdue =
        !item.isCompleted && item.dateTime.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: onToggle,
                  icon: Icon(
                    item.isCompleted
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color:
                        item.isCompleted
                            ? Colors.green
                            : const Color(0xFF4F46E5),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          decoration:
                              item.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                          color:
                              item.isCompleted
                                  ? Colors.grey.shade400
                                  : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color:
                                isOverdue ? Colors.red : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM d, h:mm a').format(item.dateTime),
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  isOverdue ? Colors.red : Colors.grey.shade600,
                              fontWeight:
                                  isOverdue
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          ),
                          if (item.recurringPattern != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.recurringPattern!.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
            if (item.description.isNotEmpty) ...[
              const Divider(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _copySnippet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.copy,
                              size: 14,
                              color: Color(0xFF4F46E5),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Copy',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4F46E5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// === SNIPPET VAULT SCREEN ===

class SnippetVaultScreen extends StatelessWidget {
  final UserSession user;
  const SnippetVaultScreen({super.key, required this.user});

  final List<Map<String, String>> templates = const [
    {
      'title': 'Email Follow-Up Snippet',
      'body':
          'Hi there, following up on our discussion yesterday. Let me know if you have any questions on the proposal!',
      'category': 'Work',
    },
    {
      'title': 'Standup Meeting Notes',
      'body':
          'Yesterday: Shipped RevenueCat billing wrapper. Today: Internal testing rollout on Play Console. Blockers: None.',
      'category': 'Dev',
    },
    {
      'title': 'Quick Zoom Link Template',
      'body':
          'Join our meeting room: https://zoom.us/j/9876543210 (Passcode: 2026)',
      'category': 'Links',
    },
    {
      'title': 'Invoice Request Template',
      'body':
          'Please send the itemized invoice for September consulting services to billing@company.com.',
      'category': 'Finance',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Snippet Vault',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final t = templates[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        t['title']!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Chip(
                        label: Text(
                          t['category']!,
                          style: const TextStyle(fontSize: 10),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t['body']!,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: t['body']!));
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied "${t['title']}"!'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('1-Tap Copy'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// === UPGRADE / PAYWALL SCREEN ===

class UpgradeScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const UpgradeScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  bool _isProcessing = false;

  Future<void> _purchaseSubscription(String productId) async {
    setState(() => _isProcessing = true);

    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null) {
        // Robust lookup checking both package identifier AND store product ID
        final package = offerings.current!.availablePackages.firstWhere(
          (p) =>
              p.identifier == productId ||
              p.storeProduct.identifier == productId,
          orElse:
              () =>
                  offerings.all['premium']?.availablePackages.firstWhere(
                    (p) =>
                        p.identifier == productId ||
                        p.storeProduct.identifier == productId,
                  ) ??
                  (throw Exception(
                    'Package $productId not found in offerings',
                  )),
        );

        final purchaserInfo = await Purchases.purchasePackage(package);

        if (purchaserInfo.customerInfo.entitlements.all[productId]?.isActive ??
            false) {
          if (productId.contains('pro')) {
            widget.user.tier = UserTier.pro;
            widget.user.trialsRemaining += 25;
          } else if (productId.contains('premium')) {
            widget.user.tier = UserTier.premium;
            widget.user.trialsRemaining += 50;
          }
          widget.onUpdate(widget.user);
          _showSuccess('Subscription activated!');
        }
      }
    } catch (e) {
      _showError('Purchase failed: ${e.toString()}');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _purchaseCredits(String productId, int credits) async {
    setState(() => _isProcessing = true);

    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null) {
        final package = offerings.current!.availablePackages.firstWhere(
          (p) =>
              p.identifier == productId ||
              p.storeProduct.identifier == productId,
          orElse:
              () =>
                  offerings.all['premium']?.availablePackages.firstWhere(
                    (p) =>
                        p.identifier == productId ||
                        p.storeProduct.identifier == productId,
                  ) ??
                  (throw Exception(
                    'Package $productId not found in offerings',
                  )),
        );

        await Purchases.purchasePackage(package);
        widget.user.trialsRemaining += credits;
        widget.onUpdate(widget.user);
        _showSuccess('$credits AI credits added!');
      }
    } catch (e) {
      _showError('Purchase failed: ${e.toString()}');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upgrade & Monetize'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body:
          _isProcessing
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Icon(
                    Icons.workspace_premium,
                    size: 72,
                    color: Color(0xFF4F46E5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Unlock ReminderSync Pro',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Unlimited Gemini 3 parsing & multi-device sync',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  // Current Tier Banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.star, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        Text(
                          'ACTIVE TIER: ${widget.user.tier.toString().split('.').last.toUpperCase()}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'Monthly Subscriptions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  _SubscriptionCard(
                    title: 'Pro Plan',
                    price: '\$25/month',
                    color: const Color(0xFF4F46E5),
                    features: const [
                      'Unlimited active reminders',
                      '25 Gemini 3 parses / mo',
                      'Background cloud sync',
                    ],
                    onTap: () => _purchaseSubscription('pro'),
                  ),
                  const SizedBox(height: 12),

                  _SubscriptionCard(
                    title: 'Premium Plan',
                    price: '\$35/month',
                    color: const Color(0xFF7C3AED),
                    recommended: true,
                    features: const [
                      'Everything in Pro',
                      '50 Gemini 3 parses / mo',
                      'Full Snippet Vault access',
                      'Priority sync engine',
                    ],
                    onTap: () => _purchaseSubscription('premium'),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'One-Time Credit Packs',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  ListTile(
                    tileColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEEF2FF),
                      child: Icon(Icons.bolt, color: Color(0xFF4F46E5)),
                    ),
                    title: const Text(
                      '10 AI Parse Credits',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: const Text(
                      '\$15',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () => _purchaseCredits('credits_10', 10),
                  ),
                  const SizedBox(height: 8),

                  ListTile(
                    tileColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEEF2FF),
                      child: Icon(Icons.bolt, color: Color(0xFF4F46E5)),
                    ),
                    title: const Text(
                      '25 AI Parse Credits',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: const Text(
                      '\$40',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () => _purchaseCredits('credits_25', 25),
                  ),
                ],
              ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final String title;
  final String price;
  final List<String> features;
  final Color color;
  final VoidCallback onTap;
  final bool recommended;

  const _SubscriptionCard({
    required this.title,
    required this.price,
    required this.features,
    required this.color,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: recommended ? 4 : 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    price,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 16, color: color),
                      const SizedBox(width: 8),
                      Text(f, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// === SETTINGS / PROFILE SCREEN ===

class SettingsScreen extends StatelessWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const SettingsScreen({super.key, required this.user, required this.onUpdate});

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_session');

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFF4F46E5),
            child: Text(
              user.email.isNotEmpty ? user.email[0].toUpperCase() : 'U',
              style: const TextStyle(fontSize: 32, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user.email,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _InfoRow(
                    label: 'AI Parse Trials Left',
                    value: user.trialsRemaining.toString(),
                  ),
                  const Divider(),
                  _InfoRow(
                    label: 'Sync Engine',
                    value: 'Active (Azure East US)',
                  ),
                  const Divider(),
                  _InfoRow(
                    label: 'RevenueCat Status',
                    value: 'Ready (Sandbox)',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          ListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: const Icon(Icons.exit_to_app, color: Colors.red),
            title: const Text('Log Out', style: TextStyle(color: Colors.red)),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
