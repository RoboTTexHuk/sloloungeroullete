import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpHeaders, HttpClient;
import 'dart:math' as _math;
import 'package:appsflyer_sdk/appsflyer_sdk.dart' as af_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, SystemChrome, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

import 'loungepush.dart';

// ============================================================================
// Константы
// ============================================================================
const String kRouletteLoadedOnceKey = "roulette_loaded_once";
const String kRouletteStatEndpoint = "https://getgame.portalroullete.bar/stat";
const String kRouletteCachedFcmKey = "roulette_cached_fcm";

// ============================================================================
// Лёгкие сервисы (без provider/riverpod/secure_storage/logger)
// ============================================================================
class RouletteBarrel {
  static final RouletteBarrel _b = RouletteBarrel._();
  RouletteBarrel._();
  factory RouletteBarrel() => _b;

  final Connectivity net = Connectivity();

  void logI(Object msg) => debugPrint("[I] $msg");
  void logW(Object msg) => debugPrint("[W] $msg");
  void logE(Object msg) => debugPrint("[E] $msg");
}

// ============================================================================
// Сеть/данные: RouletteWire
// ============================================================================
class RouletteWire {
  final RouletteBarrel _rb = RouletteBarrel();

  Future<bool> isOnline() async {
    final c = await _rb.net.checkConnectivity();
    return c != ConnectivityResult.none;
  }

  Future<void> postJson(String url, Map<String, dynamic> data) async {
    try {
      await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      );
    } catch (e) {
      _rb.logE("postJson error: $e");
    }
  }
}

// ============================================================================
// Досье устройства: RouletteDeck
// ============================================================================
class RouletteDeck {
  String? deviceId;
  String? sessionId = "roulette-one-off";
  String? platformName; // android/ios
  String? osVersion;
  String? appVersion;
  String? lang;
  String? tzName;
  bool pushEnabled = true;

  Future<void> init() async {
    final di = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await di.androidInfo;
      deviceId = a.id;
      platformName = "android";
      osVersion = a.version.release;
    } else if (Platform.isIOS) {
      final i = await di.iosInfo;
      deviceId = i.identifierForVendor;
      platformName = "ios";
      osVersion = i.systemVersion;
    }
    final info = await PackageInfo.fromPlatform();
    appVersion = info.version;
    lang = Platform.localeName.split('_').first;
    tzName = tz_zone.local.name;
    sessionId = "roulette-${DateTime.now().millisecondsSinceEpoch}";
  }

  Map<String, dynamic> asMap({String? fcm}) => {
    "fcm_token": fcm ?? 'missing_token',
    "device_id": deviceId ?? 'missing_id',
    "app_name": "spinauraportalroullete",
    "instance_id": sessionId ?? 'missing_session',
    "platform": platformName ?? 'missing_system',
    "os_version": osVersion ?? 'missing_build',
    "app_version": appVersion ?? 'missing_app',
    "language": lang ?? 'en',
    "timezone": tzName ?? 'UTC',
    "push_enabled": pushEnabled,
  };
}

// ============================================================================
// AppsFlyer: RouletteSpy
// ============================================================================
class RouletteSpy {
  af_core.AppsFlyerOptions? _opts;
  af_core.AppsflyerSdk? _sdk;

  String afUid = "";
  String afData = "";

  void start({VoidCallback? onUpdate}) {
    final cfg = af_core.AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6754761576",
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );
    _opts = cfg;
    _sdk = af_core.AppsflyerSdk(cfg);

    _sdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    _sdk?.startSDK(
      onSuccess: () => RouletteBarrel().logI("RouletteSpy started"),
      onError: (c, m) => RouletteBarrel().logE("RouletteSpy error $c: $m"),
    );

    _sdk?.onInstallConversionData((v) {
      afData = v.toString();
      onUpdate?.call();
    });

    _sdk?.getAppsFlyerUID().then((v) {
      afUid = v.toString();
      onUpdate?.call();
    });
  }
}

// ============================================================================
// Новый неоновый лоадер: NeonRouletteLoader
// ============================================================================
class NeonRouletteLoader extends StatefulWidget {
  const NeonRouletteLoader({Key? key}) : super(key: key);

  @override
  State<NeonRouletteLoader> createState() => _NeonRouletteLoaderState();
}

class _NeonRouletteLoaderState extends State<NeonRouletteLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _spin;
  late Animation<double> _glowPulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _spin = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.linear),
    );

    _glowPulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Мягкое свечение под рулеткой
                  NeonGlow(intensity: _glowPulse.value),
                  // Сама рулетка
                  Transform.rotate(
                    angle: _spin.value * 6.283185307179586, // 2*pi
                    child: CustomPaint(
                      painter: NeonRoulettePainter(),
                      size: const Size(140, 140),
                    ),
                  ),
                  // Центральная неоновая точка
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FFC6),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FFC6).withOpacity(0.9),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class NeonGlow extends StatelessWidget {
  final double intensity;
  const NeonGlow({Key? key, required this.intensity}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final glowColor = const Color(0xFF00FFC6);
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.25 * intensity),
            blurRadius: 36 * intensity,
            spreadRadius: 6 * intensity,
          ),
          BoxShadow(
            color: glowColor.withOpacity(0.15 * intensity),
            blurRadius: 64 * intensity,
            spreadRadius: 14 * intensity,
          ),
        ],
      ),
    );
  }
}

class NeonRoulettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final outerR = w * 0.48;
    final innerR = w * 0.30;

    // Палитра неона
    final colors = <Color>[
      const Color(0xFFFF006E), // розовый неон
      const Color(0xFF3A86FF), // синий неон
      const Color(0xFF00FFC6), // мятный неон
      const Color(0xFFFFBE0B), // жёлтый неон
      const Color(0xFF8338EC), // фиолетовый неон
      const Color(0xFFFF006E),
      const Color(0xFF3A86FF),
      const Color(0xFF00FFC6),
      const Color(0xFFFFBE0B),
      const Color(0xFF8338EC),
      const Color(0xFFFF006E),
      const Color(0xFF3A86FF),
    ];

    // Рамка внешняя неоновая
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = const Color(0xFF00FFC6);
    // Мягкое свечение внешнего кольца
    final outerGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
      ..color = const Color(0xFF00FFC6).withOpacity(0.6);

    canvas.drawCircle(center, outerR, outerGlow);
    canvas.drawCircle(center, outerR, ringPaint);

    // Сегменты рулетки
    final segs = colors.length;
    final sweep = 2 * 3.141592653589793 / segs;
    for (int i = 0; i < segs; i++) {
      final start = i * sweep;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: outerR),
          start,
          sweep,
          false,
        )
        ..lineTo(
          center.dx + innerR * MathCos(start + sweep),
          center.dy + innerR * MathSin(start + sweep),
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: innerR),
          start + sweep,
          -sweep,
          false,
        )
        ..close();

      final fill = Paint()
        ..style = PaintingStyle.fill
        ..shader = RadialGradient(
          colors: [
            colors[i].withOpacity(0.85),
            colors[i].withOpacity(0.35),
          ],
          stops: const [0.3, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: outerR));

      // Свечение на гранях сегмента
      final borderGlow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..color = colors[i].withOpacity(0.8);

      canvas.drawPath(path, fill);
      canvas.drawPath(path, borderGlow);
    }

    // Внутреннее кольцо неона
    final innerRingGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..color = const Color(0xFF00FFC6).withOpacity(0.5);
    final innerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFFFFFFFF).withOpacity(0.9);

    canvas.drawCircle(center, innerR, innerRingGlow);
    canvas.drawCircle(center, innerR, innerRing);
  }

  double MathSin(double x) => _math.sin(x);
  double MathCos(double x) => _math.cos(x);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// FCM фоновые крики
// ============================================================================
@pragma('vm:entry-point')
Future<void> rouletteFcmBg(RemoteMessage msg) async {
  RouletteBarrel().logI("bg-fcm: ${msg.messageId}");
  RouletteBarrel().logI("bg-data: ${msg.data}");
}

// ============================================================================
// Мост для получения токена через нативный канал: RouletteFcmBridge
// ============================================================================
class RouletteFcmBridge {
  final RouletteBarrel _rb = RouletteBarrel();
  String? _token;
  final List<void Function(String)> _waiters = [];

  String? get token => _token;

  RouletteFcmBridge() {
    const MethodChannel('com.example.fcm/token').setMethodCallHandler((call) async {
      if (call.method == 'setToken') {
        final String s = call.arguments as String;
        if (s.isNotEmpty) {
          _setToken(s);
        }
      }
    });
    _restore();
  }

  Future<void> _restore() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cached = sp.getString(kRouletteCachedFcmKey);
      if (cached != null && cached.isNotEmpty) {
        _setToken(cached, notify: false);
      }
    } catch (_) {}
  }

  Future<void> _persist(String t) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kRouletteCachedFcmKey, t);
    } catch (_) {}
  }

  void _setToken(String t, {bool notify = true}) {
    _token = t;
    _persist(t);
    if (notify) {
      for (final cb in List.of(_waiters)) {
        try {
          cb(t);
        } catch (e) {
          _rb.logW("fcm waiter error: $e");
        }
      }
      _waiters.clear();
    }
  }

  Future<void> waitToken(Function(String t) onToken) async {
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if ((_token ?? '').isNotEmpty) {
        onToken(_token!);
        return;
      }
      _waiters.add(onToken);
    } catch (e) {
      _rb.logE("waitToken error: $e");
    }
  }
}

// ============================================================================
// Вестибюль (Splash) с неоновой рулеткой: RouletteHall
// ============================================================================
class RouletteHall extends StatefulWidget {
  const RouletteHall({Key? key}) : super(key: key);

  @override
  State<RouletteHall> createState() => _RouletteHallState();
}

class _RouletteHallState extends State<RouletteHall> {
  final RouletteFcmBridge _bridge = RouletteFcmBridge();
  bool _once = false;
  Timer? _fallback;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    _bridge.waitToken((t) => _go(t));
    _fallback = Timer(const Duration(seconds: 8), () => _go(''));
  }

  void _go(String sig) {
    if (_once) return;
    _once = true;
    _fallback?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => RouletteHarbor(signal: sig)),
    );
  }

  @override
  void dispose() {
    _fallback?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: NeonRouletteLoader()),
    );
  }
}

// ============================================================================
// ViewModel + Courier: RouletteBosun + RouletteCourier
// ============================================================================
class RouletteBosun {
  final RouletteDeck deck;
  final RouletteSpy spy;

  RouletteBosun({required this.deck, required this.spy});

  Map<String, dynamic> deviceMap(String? token) => deck.asMap(fcm: token);

  Map<String, dynamic> afMap(String? token) => {
    "content": {
      "af_data": spy.afData,
      "af_id": spy.afUid,
      "fb_app_name": "spinauraportalroullete",
      "app_name": "spinauraportalroullete",
      "deep": null,
      "bundle_identifier": "ccom.porttoul.fag.sloungeportalroullete",
      "app_version": "1.0.0",
      "apple_id": "6754761576",
      "fcm_token": token ?? "no_token",
      "device_id": deck.deviceId ?? "no_device",
      "instance_id": deck.sessionId ?? "no_instance",
      "platform": deck.platformName ?? "no_type",
      "os_version": deck.osVersion ?? "no_os",
      "app_version": deck.appVersion ?? "no_app",
      "language": deck.lang ?? "en",
      "timezone": deck.tzName ?? "UTC",
      "push_enabled": deck.pushEnabled,
      "useruid": spy.afUid,
    },
  };
}

class RouletteCourier {
  final RouletteBosun model;
  final InAppWebViewController Function() getWeb;

  RouletteCourier({required this.model, required this.getWeb});

  Future<void> putDeviceToLocalStorage(String? token) async {
    final m = model.deviceMap(token);
    await getWeb().evaluateJavascript(source: '''
localStorage.setItem('app_data', JSON.stringify(${jsonEncode(m)}));
''');
  }

  Future<void> sendRawToPage(String? token) async {
    final payload = model.afMap(token);
    final jsonString = jsonEncode(payload);

    print("load stry"+ jsonString.toString());
    RouletteBarrel().logI("SendRawData: $jsonString");
    await getWeb().evaluateJavascript(source: "sendRawData(${jsonEncode(jsonString)});");
  }
}

// ============================================================================
// Переходы/статистика
// ============================================================================
Future<String> rouletteFinalUrl(String startUrl, {int maxHops = 10}) async {
  final client = HttpClient();

  try {
    var current = Uri.parse(startUrl);
    for (int i = 0; i < maxHops; i++) {
      final req = await client.getUrl(current);
      req.followRedirects = false;
      final res = await req.close();
      if (res.isRedirect) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        if (loc == null || loc.isEmpty) break;
        final next = Uri.parse(loc);
        current = next.hasScheme ? next : current.resolveUri(next);
        continue;
      }
      return current.toString();
    }
    return current.toString();
  } catch (e) {
    debugPrint("rouletteFinalUrl error: $e");
    return startUrl;
  } finally {
    client.close(force: true);
  }
}

Future<void> roulettePostStat({
  required String event,
  required int timeStart,
  required String url,
  required int timeFinish,
  required String appSid,
  int? firstPageLoadTs,
}) async {
  try {
    final finalUrl = await rouletteFinalUrl(url);
    final payload = {
      "event": event,
      "timestart": timeStart,
      "timefinsh": timeFinish,
      "url": finalUrl,
      "appleID": "6754761576",
      "open_count": "$appSid/$timeStart",
    };

    debugPrint("rouletteStat $payload");
    final res = await http.post(
      Uri.parse("$kRouletteStatEndpoint/$appSid"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );
    debugPrint("rouletteStat resp=${res.statusCode} body=${res.body}");
  } catch (e) {
    debugPrint("roulettePostStat error: $e");
  }
}

// ============================================================================
// Главный WebView — RouletteHarbor
// ============================================================================
class RouletteHarbor extends StatefulWidget {
  final String? signal;
  const RouletteHarbor({super.key, required this.signal});

  @override
  State<RouletteHarbor> createState() => _RouletteHarborState();
}

class _RouletteHarborState extends State<RouletteHarbor> with WidgetsBindingObserver {
  late InAppWebViewController _web;
  final String _home = "https://getgame.portalroullete.bar/";

  int _hatch = 0;
  DateTime? _sleepAt;
  bool _veil = false;
  double _warmProgress = 0.0;
  late Timer _warmTimer;
  final int _warmSecs = 6;
  bool _cover = true;

  bool _loadedOnceSent = false;
  int? _firstPageTs;

  RouletteCourier? _courier;
  RouletteBosun? _bosun;

  String _currentUrl = "";
  var _startLoadTs = 0;

  final RouletteDeck _deck = RouletteDeck();
  final RouletteSpy _spy = RouletteSpy();

  final Set<String> _schemes = {
    'tg', 'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  final Set<String> _extHosts = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com', 'www.bnl.com',
    // Новые соцсети
    'facebook.com', 'www.facebook.com', 'm.facebook.com',
    'instagram.com', 'www.instagram.com',
    'twitter.com', 'www.twitter.com',
    'x.com', 'www.x.com',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firstPageTs = DateTime.now().millisecondsSinceEpoch;

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _cover = false);
    });

    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() => _veil = true);
    });

    _boot();
  }

  Future<void> _loadLoadedFlag() async {
    final sp = await SharedPreferences.getInstance();
    _loadedOnceSent = sp.getBool(kRouletteLoadedOnceKey) ?? false;
  }

  Future<void> _saveLoadedFlag() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kRouletteLoadedOnceKey, true);
    _loadedOnceSent = true;
  }

  Future<void> sendLoadedOnce({required String url, required int timestart}) async {
    if (_loadedOnceSent) {
      debugPrint("Loaded already sent, skip");
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await roulettePostStat(
      event: "Loaded",
      timeStart: timestart,
      timeFinish: now,
      url: url,
      appSid: _spy.afUid,
      firstPageLoadTs: _firstPageTs,
    );
    await _saveLoadedFlag();
  }

  void _boot() {
    _startWarm();
    _wireFcm();
    _spy.start(onUpdate: () => setState(() {}));
    _bindNotificationTap();
    _prepareDeck();

    Future.delayed(const Duration(seconds: 6), () async {
      await _pushDevice();
      await _pushAf();
    });
  }

  void _wireFcm() {
    FirebaseMessaging.onMessage.listen((msg) {
      final link = msg.data['uri'];
      if (link != null) {
        _navigate(link.toString());
      } else {
        _resetHome();
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final link = msg.data['uri'];
      if (link != null) {
        _navigate(link.toString());
      } else {
        _resetHome();
      }
    });
  }

  void _bindNotificationTap() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(call.arguments);
        if (payload["uri"] != null && !payload["uri"].toString().contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => RouletteTableView(payload["uri"].toString())),
                (route) => false,
          );
        }
      }
    });
  }

  Future<void> _prepareDeck() async {
    try {
      await _deck.init();
      await _askPushPerms();
      _bosun = RouletteBosun(deck: _deck, spy: _spy);
      _courier = RouletteCourier(model: _bosun!, getWeb: () => _web);
      await _loadLoadedFlag();
    } catch (e) {
      RouletteBarrel().logE("prepare fail: $e");
    }
  }

  Future<void> _askPushPerms() async {
    FirebaseMessaging m = FirebaseMessaging.instance;
    await m.requestPermission(alert: true, badge: true, sound: true);
  }

  void _navigate(String link) async {
    try {
      await _web.loadUrl(urlRequest: URLRequest(url: WebUri(link)));
    } catch (e) {
      RouletteBarrel().logE("navigate error: $e");
    }
  }

  void _resetHome() async {
    Future.delayed(const Duration(seconds: 3), () {
      try {
        _web.loadUrl(urlRequest: URLRequest(url: WebUri(_home)));
      } catch (_) {}
    });
  }

  Future<void> _pushDevice() async {
    RouletteBarrel().logI("TOKEN ship ${widget.signal}");
    try {
      await _courier?.putDeviceToLocalStorage(widget.signal);
    } catch (e) {
      RouletteBarrel().logE("pushDevice error: $e");
    }
  }

  Future<void> _pushAf() async {
    try {
      await _courier?.sendRawToPage(widget.signal);
    } catch (e) {
      RouletteBarrel().logE("pushAf error: $e");
    }
  }

  void _startWarm() {
    int n = 0;
    _warmProgress = 0.0;
    _warmTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      setState(() {
        n++;
        _warmProgress = n / (_warmSecs * 10);
        if (_warmProgress >= 1.0) {
          _warmProgress = 1.0;
          _warmTimer.cancel();
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) {
      _sleepAt = DateTime.now();
    }
    if (s == AppLifecycleState.resumed) {
      if (Platform.isIOS && _sleepAt != null) {
        final now = DateTime.now();
        final drift = now.difference(_sleepAt!);
        if (drift > const Duration(minutes: 25)) {
          _reboard();
        }
      }
      _sleepAt = null;
    }
  }

  void _reboard() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => RouletteHarbor(signal: widget.signal)),
            (route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _warmTimer.cancel();
    super.dispose();
  }

  // ================== URL helpers ==================
  bool _isBareEmail(Uri u) {
    final s = u.scheme;
    if (s.isNotEmpty) return false;
    final raw = u.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  Uri _toMailto(Uri u) {
    final full = u.toString();
    final parts = full.split('?');
    final email = parts.first;
    final qp = parts.length > 1 ? Uri.splitQueryString(parts[1]) : <String, String>{};
    return Uri(scheme: 'mailto', path: email, queryParameters: qp.isEmpty ? null : qp);
  }

  bool _isPlatformish(Uri u) {
    final s = u.scheme.toLowerCase();
    if (_schemes.contains(s)) return true;

    if (s == 'http' || s == 'https') {
      final h = u.host.toLowerCase();
      if (_extHosts.contains(h)) return true;
      if (h.endsWith('t.me')) return true;
      if (h.endsWith('wa.me')) return true;
      if (h.endsWith('m.me')) return true;
      if (h.endsWith('signal.me')) return true;
      if (h.endsWith('facebook.com')) return true;
      if (h.endsWith('instagram.com')) return true;
      if (h.endsWith('twitter.com')) return true;
      if (h.endsWith('x.com')) return true;
    }
    return false;
  }

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri _httpize(Uri u) {
    final s = u.scheme.toLowerCase();

    if (s == 'tg' || s == 'telegram') {
      final qp = u.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {if (qp['start'] != null) 'start': qp['start']!});
      }
      final path = u.path.isNotEmpty ? u.path : '';
      return Uri.https('t.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if ((s == 'http' || s == 'https') && u.host.toLowerCase().endsWith('t.me')) {
      return u;
    }

    if (s == 'viber') return u;

    if (s == 'whatsapp') {
      final qp = u.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${_digits(phone)}', {if (text != null && text.isNotEmpty) 'text': text});
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    if ((s == 'http' || s == 'https') &&
        (u.host.toLowerCase().endsWith('wa.me') || u.host.toLowerCase().endsWith('whatsapp.com'))) {
      return u;
    }

    if (s == 'skype') return u;

    if (s == 'fb-messenger') {
      final path = u.pathSegments.isNotEmpty ? u.pathSegments.join('/') : '';
      final qp = u.queryParameters;
      final id = qp['id'] ?? qp['user'] ?? path;
      if (id.isNotEmpty) {
        return Uri.https('m.me', '/$id', u.queryParameters.isEmpty ? null : u.queryParameters);
      }
      return Uri.https('m.me', '/', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if (s == 'sgnl') {
      final qp = u.queryParameters;
      final ph = qp['phone'];
      final un = u.queryParameters['username'];
      if (ph != null && ph.isNotEmpty) return Uri.https('signal.me', '/#p/${_digits(ph)}');
      if (un != null && un.isNotEmpty) return Uri.https('signal.me', '/#u/$un');
      final path = u.pathSegments.join('/');
      if (path.isNotEmpty) return Uri.https('signal.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
      return u;
    }

    if (s == 'tel') {
      return Uri.parse('tel:${_digits(u.path)}');
    }

    if (s == 'mailto') return u;

    if (s == 'bnl') {
      final newPath = u.path.isNotEmpty ? u.path : '';
      return Uri.https('bnl.com', '/$newPath', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    return u;
  }

  Future<bool> _openMailWeb(Uri mailto) async {
    final u = _gmailize(mailto);
    return await _openWeb(u);
  }

  Uri _gmailize(Uri m) {
    final qp = m.queryParameters;
    final params = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (m.path.isNotEmpty) 'to': m.path,
      if ((qp['subject'] ?? '').isNotEmpty) 'su': qp['subject']!,
      if ((qp['body'] ?? '').isNotEmpty) 'body': qp['body']!,
      if ((qp['cc'] ?? '').isNotEmpty) 'cc': qp['cc']!,
      if ((qp['bcc'] ?? '').isNotEmpty) 'bcc': qp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', params);
  }

  Future<bool> _openWeb(Uri u) async {
    try {
      if (await launchUrl(u, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openInAppBrowser error: $e; url=$u');
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> _openExternal(Uri u) async {
    try {
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openExternal error: $e; url=$u');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _bindNotificationTap(); // повторная привязка

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_cover)
              const NeonRouletteLoader()
            else
              Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    InAppWebView(
                      key: ValueKey(_hatch),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        disableDefaultErrorPage: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        allowsPictureInPictureMediaPlayback: true,
                        useOnDownloadStart: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                        transparentBackground: true,
                      ),
                      initialUrlRequest: URLRequest(url: WebUri(_home)),
                      onWebViewCreated: (c) {
                        _web = c;

                        _bosun ??= RouletteBosun(deck: _deck, spy: _spy);
                        _courier ??= RouletteCourier(model: _bosun!, getWeb: () => _web);

                        _web.addJavaScriptHandler(
                          handlerName: 'onServerResponse',
                          callback: (args) {
                            try {
                              final saved = args.isNotEmpty &&
                                  args[0] is Map &&
                                  args[0]['savedata'].toString() == "true";

                              if (saved) {
                                // Placeholder for savedata flag
                              }
                            } catch (_) {}
                            if (args.isEmpty) return null;
                            try {
                              return args.reduce((curr, next) => curr + next);
                            } catch (_) {
                              return args.first;
                            }
                          },
                        );
                      },
                      onLoadStart: (c, u) async {
                        setState(() {
                          _startLoadTs = DateTime.now().millisecondsSinceEpoch;
                        });
                        final v = u;
                        if (v != null) {
                          if (_isBareEmail(v)) {
                            try {
                              await c.stopLoading();
                            } catch (_) {}
                            final mailto = _toMailto(v);
                            await _openMailWeb(mailto);
                            return;
                          }
                          final sch = v.scheme.toLowerCase();
                          if (sch != 'http' && sch != 'https') {
                            try {
                              await c.stopLoading();
                            } catch (_) {}
                          }
                        }
                      },
                      onLoadError: (controller, url, code, message) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final ev = "InAppWebViewError(code=$code, message=$message)";
                        await roulettePostStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: url?.toString() ?? '',
                          appSid: _spy.afUid,
                          firstPageLoadTs: _firstPageTs,
                        );
                      },
                      onReceivedHttpError: (controller, request, errorResponse) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final ev = "HTTPError(status=${errorResponse.statusCode}, reason=${errorResponse.reasonPhrase})";
                        await roulettePostStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: request.url?.toString() ?? '',
                          appSid: _spy.afUid,
                          firstPageLoadTs: _firstPageTs,
                        );
                      },
                      onReceivedError: (controller, request, error) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final desc = (error.description ?? '').toString();
                        final ev = "WebResourceError(code=${error}, message=$desc)";
                        await roulettePostStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: request.url?.toString() ?? '',
                          appSid: _spy.afUid,
                          firstPageLoadTs: _firstPageTs,
                        );
                      },
                      onLoadStop: (c, u) async {
                        await c.evaluateJavascript(source: "console.log('Roulette harbor up!');");
                        await _pushDevice();
                        await _pushAf();

                        setState(() => _currentUrl = u.toString());

                        Future.delayed(const Duration(seconds: 20), () {
                          sendLoadedOnce(url: _currentUrl.toString(), timestart: _startLoadTs);
                        });
                      },
                      shouldOverrideUrlLoading: (c, action) async {
                        final uri = action.request.url;
                        if (uri == null) return NavigationActionPolicy.ALLOW;

                        if (_isBareEmail(uri)) {
                          final mailto = _toMailto(uri);
                          await _openMailWeb(mailto);
                          return NavigationActionPolicy.CANCEL;
                        }

                        final sch = uri.scheme.toLowerCase();

                        if (sch == 'mailto') {
                          await _openMailWeb(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (sch == 'tel') {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          return NavigationActionPolicy.CANCEL;
                        }

                        // Соцсети — всегда наружу
                        final host = uri.host.toLowerCase();
                        final isSoc =
                            host.endsWith('facebook.com') ||
                                host.endsWith('instagram.com') ||
                                host.endsWith('twitter.com') ||
                                host.endsWith('x.com');

                        if (isSoc) {
                          await _openExternal(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        // Прочие платформенные — наружу (включая tg/wa и их web-версии)
                        if (_isPlatformish(uri)) {
                          final web = _httpize(uri);
                          await _openExternal(web);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (sch != 'http' && sch != 'https') {
                          return NavigationActionPolicy.CANCEL;
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (c, req) async {
                        final uri = req.request.url;
                        if (uri == null) return false;

                        if (_isBareEmail(uri)) {
                          final mailto = _toMailto(uri);
                          await _openMailWeb(mailto);
                          return false;
                        }

                        final sch = uri.scheme.toLowerCase();

                        if (sch == 'mailto') {
                          await _openMailWeb(uri);
                          return false;
                        }

                        if (sch == 'tel') {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          return false;
                        }

                        // Соцсети — наружу
                        final host = uri.host.toLowerCase();
                        final isSoc =
                            host.endsWith('facebook.com') ||
                                host.endsWith('instagram.com') ||
                                host.endsWith('twitter.com') ||
                                host.endsWith('x.com');

                        if (isSoc) {
                          await _openExternal(uri);
                          return false;
                        }

                        if (_isPlatformish(uri)) {
                          final web = _httpize(uri);
                          await _openExternal(web);
                          return false;
                        }

                        if (sch == 'http' || sch == 'https') {
                          c.loadUrl(urlRequest: URLRequest(url: uri));
                        }
                        return false;
                      },
                      onDownloadStartRequest: (c, req) async {
                        await _openExternal(req.url);
                      },
                    ),
                    Visibility(
                      visible: !_veil,
                      child: const NeonRouletteLoader(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Отдельный WebView для внешней ссылки (из уведомлений): RouletteDeckScreen
// ============================================================================
class RouletteDeckScreen extends StatefulWidget with WidgetsBindingObserver {
  final String lane;
  const RouletteDeckScreen(this.lane, {super.key});

  @override
  State<RouletteDeckScreen> createState() => _RouletteDeckScreenState();
}

class _RouletteDeckScreenState extends State<RouletteDeckScreen> with WidgetsBindingObserver {
  late InAppWebViewController _deck;

  @override
  Widget build(BuildContext context) {
    final night = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: night ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: InAppWebView(
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            disableDefaultErrorPage: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            allowsPictureInPictureMediaPlayback: true,
            useOnDownloadStart: true,
            javaScriptCanOpenWindowsAutomatically: true,
            useShouldOverrideUrlLoading: true,
            supportMultipleWindows: true,
          ),
          initialUrlRequest: URLRequest(url: WebUri(widget.lane)),
          onWebViewCreated: (c) => _deck = c,
        ),
      ),
    );
  }
}

// ============================================================================
// Help экраны: RouletteHelp, RouletteHelpLite
// ============================================================================
class RouletteHelp extends StatefulWidget {
  const RouletteHelp({super.key});

  @override
  State<RouletteHelp> createState() => _RouletteHelpState();
}

class _RouletteHelpState extends State<RouletteHelp> with WidgetsBindingObserver {
  InAppWebViewController? _ctrl;
  bool _spin = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
              initialFile: 'assets/index.html',
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                supportZoom: false,
                disableHorizontalScroll: false,
                disableVerticalScroll: false,
              ),
              onWebViewCreated: (c) => _ctrl = c,
              onLoadStart: (c, u) => setState(() => _spin = true),
              onLoadStop: (c, u) async => setState(() => _spin = false),
              onLoadError: (c, u, code, msg) => setState(() => _spin = false),
            ),
            if (_spin) const NeonRouletteLoader(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// main()
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(rouletteFcmBg);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  tz_data.initializeTimeZones();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RouletteHall(),
    ),
  );
}