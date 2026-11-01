import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.load();
  runApp(const BidApp());
}

// ---------------------------------------------------------------------------
// Shared state + local storage
// ---------------------------------------------------------------------------
const Map<String, String> fieldLabels = {
  'profile_photo': 'Profile photo',
  'full_legal_name': 'Full legal name',
  'phone_number': 'Phone number',
  'date_of_birth': 'Date of birth',
  'country_of_residence': 'Country of residence',
  'aadhaar': 'Aadhaar number',
  'proof_of_address': 'Proof of address',
  'dob_proof': 'Date-of-birth proof',
};

const Map<String, IconData> fieldIcons = {
  'profile_photo': Icons.account_circle,
  'full_legal_name': Icons.person,
  'phone_number': Icons.phone,
  'date_of_birth': Icons.cake,
  'country_of_residence': Icons.public,
  'aadhaar': Icons.badge,
  'proof_of_address': Icons.home,
  'dob_proof': Icons.description,
};

/// Profile photos travel as base64 text. This turns it back into image bytes.
Uint8List? decodePhoto(String? b64) {
  if (b64 == null || b64.isEmpty) return null;
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

/// Round profile picture (falls back to a person icon).
class Avatar extends StatelessWidget {
  final Uint8List? bytes;
  final double size;
  const Avatar({super.key, required this.bytes, this.size = 48});

  Widget _placeholder() => Container(
        width: size,
        height: size,
        color: const Color(0xFFE2E8F0),
        child: Icon(Icons.person, size: size * 0.6, color: AppColors.slate500),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: ClipOval(
        child: bytes == null
            ? _placeholder()
            : Image.memory(
                bytes!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _placeholder(),
              ),
      ),
    );
  }
}

class Booking {
  final String title;
  final String detail;
  final IconData icon;
  Booking(this.title, this.detail, this.icon);
  Map<String, String> toMap() => {'title': title, 'detail': detail};
}

class AppState {
  // Change the default to your PC's IP (shown when you start Flask).
  static String backendUrl = 'http://10.110.1.142:5000';
  static const int p2pPort = 8080;

  /// The registered BID hash (saved on the phone).
  static String? bid;

  /// Switch states for personal details (key = server field name).
  static final Map<String, bool> personalSwitches = {
    for (final k in fieldLabels.keys) k: true,
  };

  /// Dummy bookings (kept on the phone) and their switches.
  static final List<Booking> bookings = [
    Booking('Graviton Invitation 2026', 'CGC University, Mohali', Icons.event),
    Booking('Ramayana Movie Ticket', '5th November 2026', Icons.movie),
    Booking('Bus Ticket', 'Jammu to Chandigarh', Icons.directions_bus),
  ];
  static final List<bool> bookingSwitches = [true, true, true];

  /// What was fetched from Flask for the current selection (only ON items).
  static Map<String, String> selectedPersonal = {};
  static List<Map<String, String>> selectedBookings = [];

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      bid = p.getString('bid');
      backendUrl = p.getString('server_url') ?? backendUrl;
    } catch (_) {}
  }

  static Future<void> saveBid(String value) async {
    bid = value;
    final p = await SharedPreferences.getInstance();
    await p.setString('bid', value);
  }

  static Future<void> clearBid() async {
    bid = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('bid');
  }

  static Future<void> saveServerUrl(String url) async {
    backendUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final p = await SharedPreferences.getInstance();
    await p.setString('server_url', backendUrl);
  }
}

void snack(BuildContext context, String m) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

Future<void> showServerDialog(BuildContext context) async {
  final c = TextEditingController(text: AppState.backendUrl);
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Blockchain server'),
      content: TextField(
        controller: c,
        decoration: const InputDecoration(
          labelText: 'Server URL',
          helperText: 'e.g. http://10.110.1.142:5000',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await AppState.saveServerUrl(c.text);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// UI theme (matches the BID website design)
// ---------------------------------------------------------------------------
class AppColors {
  static const primary = Color(0xFF0284C7); // bright sky cyan
  static const secondary = Color(0xFF2563EB); // royal blue
  static const accent = Color(0xFF0D9488); // teal
  static const bg = Color(0xFFF8FAFC); // off white
  static const dark = Color(0xFF0F172A); // slate dark
  static const slate600 = Color(0xFF475569);
  static const slate500 = Color(0xFF64748B);
  static const border = Color(0xFFCBD5E1);
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );
  static const tealGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, primary],
  );
}

class BidLogo extends StatelessWidget {
  final double size;
  const BidLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppColors.gradient,
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        'B',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.5,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const GradientText(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [AppColors.primary, AppColors.secondary, AppColors.accent],
      ).createShader(bounds),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool loading;
  final double height;
  final double fontSize;
  final Gradient gradient;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
    this.height = 54,
    this.fontSize = 16,
    this.gradient = AppColors.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: (onPressed == null && !loading) ? 0.55 : 1,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: enabled ? onPressed : null,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    else if (icon != null)
                      Icon(icon, color: Colors.white, size: fontSize + 6),
                    if (loading || icon != null) const SizedBox(width: 10),
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: fontSize,
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

/// Dark "terminal" box used for status messages (like the ZKP console).
class StatusConsole extends StatelessWidget {
  final String text;
  const StatusConsole(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('bid-nearby.sol',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF94A3B8))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('STATUS',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: Color(0xFF5EEAD4))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('> $text',
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.4,
                  color: Color(0xFF5EEAD4))),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final String text;
  const _LiveBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF7DD3FC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
                color: AppColors.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every screen uses this: soft glows + animated blockchain network behind it.
class BidScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  const BidScaffold({super.key, this.appBar, required this.body});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const NetworkBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: appBar,
          body: body,
        ),
      ],
    );
  }
}

class _Node {
  double x, y, vx, vy, r;
  _Node(this.x, this.y, this.vx, this.vy, this.r);
}

class NetworkBackground extends StatefulWidget {
  const NetworkBackground({super.key});

  @override
  State<NetworkBackground> createState() => _NetworkBackgroundState();
}

class _NetworkBackgroundState extends State<NetworkBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final List<_Node> _nodes = [];
  final Random _rand = Random();
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 10))
      ..addListener(_step)
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ensureNodes(Size s) {
    if (s == _size && _nodes.isNotEmpty) return;
    _size = s;
    _nodes.clear();
    final count = (s.width / 25).floor().clamp(10, 28);
    for (var i = 0; i < count; i++) {
      _nodes.add(_Node(
        _rand.nextDouble() * s.width,
        _rand.nextDouble() * s.height,
        (_rand.nextDouble() - 0.5) * 0.5,
        (_rand.nextDouble() - 0.5) * 0.5,
        _rand.nextDouble() * 2 + 1,
      ));
    }
  }

  void _step() {
    for (final n in _nodes) {
      n.x += n.vx;
      n.y += n.vy;
      if (n.x < 0 || n.x > _size.width) n.vx *= -1;
      if (n.y < 0 || n.y > _size.height) n.vy *= -1;
    }
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _ensureNodes(Size(c.maxWidth, c.maxHeight));
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.bg),
          Positioned(
              top: -140, left: -120, child: _glow(420, const Color(0x80BAE6FD))),
          Positioned(
              top: c.maxHeight * 0.35,
              right: -160,
              child: _glow(460, const Color(0x66BFDBFE))),
          CustomPaint(painter: _NetPainter(_nodes, _c), size: Size.infinite),
        ],
      );
    });
  }
}

class _NetPainter extends CustomPainter {
  final List<_Node> nodes;
  _NetPainter(this.nodes, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = AppColors.primary.withOpacity(0.5);
    final line = Paint()..strokeWidth = 1;
    for (var i = 0; i < nodes.length; i++) {
      final a = nodes[i];
      canvas.drawCircle(Offset(a.x, a.y), a.r, dot);
      for (var j = i + 1; j < nodes.length; j++) {
        final b = nodes[j];
        final d = sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
        if (d < 110) {
          final alpha = ((0.15 - d / 700) * 0.7).clamp(0.0, 1.0);
          line.color = AppColors.primary.withOpacity(alpha);
          canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), line);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NetPainter old) => true;
}

class BidApp extends StatelessWidget {
  const BidApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      tertiary: AppColors.accent,
      surface: Colors.white,
      onSurface: AppColors.dark,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    );

    return MaterialApp(
      title: 'BID',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: scheme,
        scaffoldBackgroundColor: AppColors.bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xD9FFFFFF),
          foregroundColor: AppColors.dark,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: AppColors.dark,
          ),
          shape: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xEBFFFFFF),
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xB3CBD5E1)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: inputBorder,
          enabledBorder: inputBorder,
          focusedBorder: inputBorder.copyWith(
            borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
          ),
          errorBorder: inputBorder.copyWith(
            borderSide: const BorderSide(color: Color(0xFFE11D48)),
          ),
          focusedErrorBorder: inputBorder.copyWith(
            borderSide: const BorderSide(color: Color(0xFFE11D48), width: 1.6),
          ),
          labelStyle: const TextStyle(color: AppColors.slate600),
          helperStyle: const TextStyle(color: AppColors.slate500),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.dark,
            backgroundColor: Colors.white.withOpacity(0.75),
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        listTileTheme: const ListTileThemeData(iconColor: AppColors.primary),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.dark,
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const IntroScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Intro screen. If a BID is already saved, it continues automatically.
// ---------------------------------------------------------------------------
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    if (AppState.bid != null) {
      _autoTimer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const ShareScreen()));
        }
      });
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  void _goDirect() {
    _autoTimer?.cancel(); // stop the automatic jump to the share screen
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const ChoiceScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final registered = AppState.bid != null;
    return BidScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _LiveBadge(text: 'SOVEREIGN IDENTITY FOR INDIA'),
                const SizedBox(height: 30),
                const BidLogo(size: 96),
                const SizedBox(height: 22),
                const GradientText('BID',
                    style: TextStyle(
                        fontSize: 60,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8)),
                const SizedBox(height: 4),
                const Text('BLOCKCHAIN IDENTIFICATION NETWORK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const SizedBox(height: 18),
                const Text(
                  'Your identity, secured with SHA-256 and shared only with the people you choose.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16, height: 1.5, color: AppColors.slate600),
                ),
                const SizedBox(height: 40),
                if (registered) ...[
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 14),
                  const Text('Welcome back, opening your BID...',
                      style: TextStyle(color: AppColors.slate600)),
                  const SizedBox(height: 28),
                ] else ...[
                  GradientButton(
                    icon: Icons.badge,
                    label: 'Get Started',
                    onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RegistrationScreen())),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.swap_horiz, color: AppColors.primary),
                    label: const Text('Send / Receive directly'),
                    onPressed: _goDirect,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. BID registration (only once; saved on the phone)
// ---------------------------------------------------------------------------
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final bidCtrl = TextEditingController();
  final urlCtrl = TextEditingController(text: AppState.backendUrl);
  String? error;

  Future<void> _register() async {
    final value = bidCtrl.text.trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      setState(() => error = 'BID must be the 64-character hash (letters a-f, digits 0-9)');
      return;
    }
    await AppState.saveServerUrl(urlCtrl.text);
    await AppState.saveBid(value);
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const ShareScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return BidScaffold(
      appBar: AppBar(
        title: const Text('BID Registration'),
        actions: [
          IconButton(
            tooltip: 'Send / Receive directly',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChoiceScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text('Register your BID',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
              'Paste the BID hash you received when your details were added to the blockchain. '
              'You only need to do this once.'),
          const SizedBox(height: 20),
          TextField(
            controller: bidCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'BID hash',
              errorText: error,
              prefixIcon: const Icon(Icons.vpn_key),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => error = null),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: urlCtrl,
            decoration: const InputDecoration(
              labelText: 'Blockchain server URL',
              helperText: 'e.g. http://10.110.1.142:5000 (same Wi-Fi as the PC)',
              prefixIcon: Icon(Icons.dns),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          GradientButton(
            onPressed: _register,
            icon: Icons.verified,
            label: 'Register BID',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Choose what to share (switches). Only ON items are fetched/sent.
// ---------------------------------------------------------------------------
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  bool loading = false;

  Future<void> _continue() async {
    final keys = [
      for (final e in AppState.personalSwitches.entries)
        if (e.value) e.key
    ];
    final chosenBookings = [
      for (var i = 0; i < AppState.bookings.length; i++)
        if (AppState.bookingSwitches[i]) AppState.bookings[i].toMap()
    ];

    if (keys.isEmpty && chosenBookings.isEmpty) {
      snack(context, 'Switch on at least one item to share.');
      return;
    }

    setState(() => loading = true);
    Map<String, String> fetched = {};

    try {
      if (keys.isNotEmpty) {
        // Ask the server ONLY for the fields that are switched on.
        final res = await http
            .post(
              Uri.parse('${AppState.backendUrl}/get_data'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'bid': AppState.bid, 'fields': keys}),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body)['data'] as Map<String, dynamic>;
          fetched = data.map((k, v) => MapEntry(k, v.toString()));
        } else if (res.statusCode == 404) {
          if (!mounted) return;
          snack(context, 'BID not found on the server. Check your BID (menu > Change BID).');
          return;
        } else {
          if (!mounted) return;
          snack(context, 'Server error ${res.statusCode}: ${res.body}');
          return;
        }
      }

      AppState.selectedPersonal = fetched;
      AppState.selectedBookings = chosenBookings;
      if (!mounted) return;
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ChoiceScreen()));
    } catch (e) {
      if (mounted) {
        snack(context, 'Could not reach server at ${AppState.backendUrl}\n$e');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _changeBid() async {
    await AppState.clearBid();
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const RegistrationScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final bid = AppState.bid ?? '';
    final shortBid = bid.length > 16
        ? '${bid.substring(0, 8)}...${bid.substring(bid.length - 8)}'
        : bid;
    return BidScaffold(
      appBar: AppBar(
        title: const Text('Choose what to share'),
        actions: [
          IconButton(
            tooltip: 'Send / Receive directly',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChoiceScreen())),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'server') showServerDialog(context);
              if (v == 'bid') _changeBid();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'server', child: Text('Server URL')),
              PopupMenuItem(value: 'bid', child: Text('Change BID')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_user, color: AppColors.accent),
              title: const Text('Registered BID'),
              subtitle: Text(shortBid),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Personal details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Only switched-ON items are fetched from the server and shared.'),
          const SizedBox(height: 6),
          for (final e in fieldLabels.entries)
            Card(
              child: SwitchListTile(
                secondary: Icon(fieldIcons[e.key]),
                title: Text(e.value),
                value: AppState.personalSwitches[e.key]!,
                onChanged: (v) =>
                    setState(() => AppState.personalSwitches[e.key] = v),
              ),
            ),
          const SizedBox(height: 14),
          const Text('Bookings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (var i = 0; i < AppState.bookings.length; i++)
            Card(
              child: SwitchListTile(
                secondary: Icon(AppState.bookings[i].icon),
                title: Text(AppState.bookings[i].title),
                subtitle: Text(AppState.bookings[i].detail),
                value: AppState.bookingSwitches[i],
                onChanged: (v) =>
                    setState(() => AppState.bookingSwitches[i] = v),
              ),
            ),
          const SizedBox(height: 18),
          GradientButton(
            onPressed: loading ? null : _continue,
            loading: loading,
            icon: Icons.swap_horiz,
            label: 'Go to Send / Receive',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Send / Receive choice
// ---------------------------------------------------------------------------
class ChoiceScreen extends StatelessWidget {
  const ChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nP = AppState.selectedPersonal.length;
    final nB = AppState.selectedBookings.length;
    return BidScaffold(
      appBar: AppBar(title: const Text('Share Data')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Card(
              child: ListTile(
                leading: AppState.selectedPersonal.containsKey('profile_photo')
                    ? Avatar(
                        bytes: decodePhoto(AppState.selectedPersonal['profile_photo']),
                        size: 44)
                    : const Icon(Icons.checklist, color: AppColors.accent),
                title: Text(nP + nB == 0 ? 'Nothing selected yet' : 'Ready to share'),
                subtitle: Text(nP + nB == 0
                    ? 'You can still receive. To send, choose items first.'
                    : '$nP personal detail(s), $nB booking(s)'),
              ),
            ),
            const SizedBox(height: 30),
            GradientButton(
              height: 90,
              fontSize: 20,
              icon: Icons.send,
              label: 'SEND DATA',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SendScreen())),
            ),
            const SizedBox(height: 20),
            GradientButton(
              height: 90,
              fontSize: 20,
              gradient: AppColors.tealGradient,
              icon: Icons.download,
              label: 'RECEIVE DATA',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ReceiveScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nearby Connections helpers (no hotspot, no password, no IP address)
// ---------------------------------------------------------------------------
const String kServiceId = 'com.example.bid_app_go.share';

String deviceLabel() => 'BID-${1000 + Random().nextInt(9000)}';

/// Asks for every permission Nearby Connections may need.
/// Returns true if the essential one (location) was granted.
Future<bool> requestNearbyPermissions() async {
  final results = await [
    Permission.location,
    Permission.bluetoothScan,
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
    Permission.nearbyWifiDevices,
  ].request();
  return results[Permission.location]?.isGranted ?? false;
}

/// Shows the pairing code. Both phones must show the same code.
Future<bool> confirmConnection(BuildContext context, ConnectionInfo info) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm connection'),
      content: Text(
        'Connect with ${info.endpointName}?\n\n'
        'Code: ${info.authenticationToken}\n\n'
        'Check that the same code is shown on the other phone.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Reject')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accept')),
      ],
    ),
  );
  return ok ?? false;
}

// ---------------------------------------------------------------------------
// 5. Send: find nearby phones and send the selected data
// ---------------------------------------------------------------------------
class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final String myName = deviceLabel();
  final Map<String, String> endpoints = {}; // endpointId -> device name
  String status = 'Starting...';
  bool busy = false;

  bool get _nothingSelected =>
      AppState.selectedPersonal.isEmpty && AppState.selectedBookings.isEmpty;

  Map<String, dynamic> _payload() => {
        'sender_bid': AppState.bid,
        'details': AppState.selectedPersonal,
        'bookings': AppState.selectedBookings,
      };

  /// Readable preview of what will be sent (no raw JSON).
  Widget _buildSummary() {
    final details = AppState.selectedPersonal;
    final photo = decodePhoto(details['profile_photo']);
    final bookings = AppState.selectedBookings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (photo != null) ...[
          Center(child: Avatar(bytes: photo, size: 84)),
          const SizedBox(height: 12),
        ],
        for (final e in details.entries)
          if (e.key != 'profile_photo')
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(fieldIcons[e.key] ?? Icons.info_outline,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${fieldLabels[e.key] ?? e.key}: ${e.value}'),
                  ),
                ],
              ),
            ),
        if (bookings.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text('Bookings',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final b in bookings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• ${b['title']} (${b['detail']})'),
            ),
        ],
        if (details.isEmpty && bookings.isEmpty) const Text('Nothing selected'),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  @override
  void dispose() {
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    super.dispose();
  }

  void _setStatus(String s) {
    if (mounted) setState(() => status = s);
  }

  Future<void> _startDiscovery() async {
    _setStatus('Checking permissions...');
    if (!await requestNearbyPermissions()) {
      _setStatus('Permission denied. Allow Location / Nearby devices in app settings.');
      return;
    }
    try {
      await Nearby().stopDiscovery();
      endpoints.clear();
      await Nearby().startDiscovery(
        myName,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (id, name, serviceId) {
          if (mounted) setState(() => endpoints[id] = name);
        },
        onEndpointLost: (id) {
          if (mounted && id != null) setState(() => endpoints.remove(id));
        },
        serviceId: kServiceId,
      );
      _setStatus('Searching for nearby phones... (the other phone must be on Receive Data)');
    } catch (e) {
      _setStatus('Error: $e\nTurn on Bluetooth, Wi-Fi and Location, then press Refresh.');
    }
  }

  Future<void> _connect(String id, String name) async {
    setState(() {
      busy = true;
      status = 'Connecting to $name...';
    });
    try {
      await Nearby().requestConnection(
        myName,
        id,
        onConnectionInitiated: (endpointId, info) async {
          final accepted = await confirmConnection(context, info);
          if (accepted) {
            await Nearby().acceptConnection(
              endpointId,
              onPayLoadRecieved: (_, __) {},
              onPayloadTransferUpdate: (_, __) {},
            );
          } else {
            await Nearby().rejectConnection(endpointId);
            if (mounted) setState(() => busy = false);
          }
        },
        onConnectionResult: (endpointId, s) async {
          if (s == Status.CONNECTED) {
            await _sendData(endpointId, name);
          } else {
            _setStatus(s == Status.REJECTED
                ? 'The other phone rejected the connection.'
                : 'Connection failed.');
            if (mounted) setState(() => busy = false);
          }
        },
        onDisconnected: (endpointId) {
          if (mounted) setState(() => busy = false);
        },
      );
    } catch (e) {
      _setStatus('Could not connect: $e');
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sendData(String id, String name) async {
    try {
      var payload = _payload();
      var bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
      var note = '';
      // One Nearby message can carry at most 32 KB. Leave the photo out if needed.
      if (bytes.length > 30000 &&
          AppState.selectedPersonal.containsKey('profile_photo')) {
        final details = Map<String, String>.from(AppState.selectedPersonal)
          ..remove('profile_photo');
        payload = {...payload, 'details': details};
        bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
        note = ' (photo left out: too large for one message)';
      }
      await Nearby().sendBytesPayload(id, bytes);
      _setStatus('Sent successfully to $name!$note');
      await Future.delayed(const Duration(seconds: 2));
      await Nearby().disconnectFromEndpoint(id);
    } catch (e) {
      _setStatus('Failed to send: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BidScaffold(
      appBar: AppBar(
        title: const Text('Send Data'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: busy ? null : _startDiscovery,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_nothingSelected)
            Card(
              color: Colors.orange.withOpacity(0.15),
              child: const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Nothing selected to send'),
                subtitle: Text(
                    'Go back to "Choose what to share", switch items on and continue.'),
              ),
            ),
          const Text('1. On the other phone open RECEIVE DATA.'),
          const Text('2. Tap that phone in the list below.'),
          const Text('3. Accept on both phones when the same code appears.'),
          const SizedBox(height: 14),
          StatusConsole(status),
          const SizedBox(height: 10),
          const Text('Nearby phones',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (endpoints.isEmpty) const Text('None found yet...'),
          for (final e in endpoints.entries)
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone_android),
                title: Text(e.value),
                trailing: const Icon(Icons.send),
                enabled: !busy && !_nothingSelected,
                onTap: () => _connect(e.key, e.value),
              ),
            ),
          const SizedBox(height: 16),
          const Text('Data that will be sent:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _buildSummary(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Receive: advertise this phone and accept data from a sender
// ---------------------------------------------------------------------------
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final String myName = deviceLabel();
  final List<Map<String, dynamic>> received = [];
  String status = 'Starting...';

  @override
  void initState() {
    super.initState();
    _startAdvertising();
  }

  @override
  void dispose() {
    Nearby().stopAdvertising();
    Nearby().stopAllEndpoints();
    super.dispose();
  }

  void _setStatus(String s) {
    if (mounted) setState(() => status = s);
  }

  Future<void> _startAdvertising() async {
    _setStatus('Checking permissions...');
    if (!await requestNearbyPermissions()) {
      _setStatus('Permission denied. Allow Location / Nearby devices in app settings.');
      return;
    }
    try {
      await Nearby().stopAdvertising();
      await Nearby().startAdvertising(
        myName,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: (id, info) async {
          final accepted = await confirmConnection(context, info);
          if (accepted) {
            await Nearby().acceptConnection(
              id,
              onPayLoadRecieved: (endpointId, payload) {
                if (payload.type == PayloadType.BYTES && payload.bytes != null) {
                  try {
                    final data =
                        jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;
                    if (mounted) setState(() => received.insert(0, data));
                    _setStatus('Data received!');
                  } catch (_) {
                    _setStatus('Received data could not be read.');
                  }
                }
              },
              onPayloadTransferUpdate: (_, __) {},
            );
          } else {
            await Nearby().rejectConnection(id);
          }
        },
        onConnectionResult: (id, s) {
          _setStatus(s == Status.CONNECTED
              ? 'Connected. Waiting for data...'
              : 'Connection ${s.name}.');
        },
        onDisconnected: (id) => _setStatus('Visible to nearby senders. Waiting...'),
        serviceId: kServiceId,
      );
      _setStatus('Visible to nearby senders. Waiting...');
    } catch (e) {
      _setStatus('Error: $e\nTurn on Bluetooth, Wi-Fi and Location, then reopen this screen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BidScaffold(
      appBar: AppBar(title: const Text('Receive Data')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusConsole(status),
                  const SizedBox(height: 10),
                  Text('This phone appears as: $myName',
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 6),
                  const Text(
                      'Keep this screen open. Bluetooth, Wi-Fi and Location must be on.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Received data',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (received.isEmpty) const Text('Waiting for data...'),
          for (final r in received) _ReceivedCard(data: r),
        ],
      ),
    );
  }
}

class _ReceivedCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ReceivedCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final details = (data['details'] as Map?)?.cast<String, dynamic>() ?? {};
    final photo = decodePhoto(details['profile_photo']?.toString());
    final bookings = (data['bookings'] as List?) ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo != null) ...[
              Center(child: Avatar(bytes: photo, size: 96)),
              const SizedBox(height: 12),
            ],
            if (details.isEmpty) const Text('No personal details shared'),
            for (final e in details.entries)
              if (e.key != 'profile_photo')
                Text('${fieldLabels[e.key] ?? e.key}: ${e.value}'),
            const SizedBox(height: 8),
            const Text('Bookings:', style: TextStyle(fontWeight: FontWeight.bold)),
            if (bookings.isEmpty) const Text('None shared'),
            for (final b in bookings) Text('• ${b['title']} (${b['detail']})'),
          ],
        ),
      ),
    );
  }
}