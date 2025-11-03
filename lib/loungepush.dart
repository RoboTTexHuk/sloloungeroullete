// -----------------------------------------------------------------------------
// Roulette-flavored refactor of the original Caribbean-themed code
// -----------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart' show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Предполагается, что в main.dart эти названия экспортируются.
// Если у вас другие — замените здесь и в местах использования.
import 'main.dart' show MafiaHarbor, CaptainHarbor;

// ============================================================================
// Рулеточная инфраструктура и паттерны
// ============================================================================

class WheelLogger {
  const WheelLogger();
  void log(Object msg) => debugPrint('[WheelLogger] $msg');
  void warn(Object msg) => debugPrint('[WheelLogger/WARN] $msg');
  void err(Object msg) => debugPrint('[WheelLogger/ERR] $msg');
}

class RouletteVault {
  static final RouletteVault _single = RouletteVault._();
  RouletteVault._();
  factory RouletteVault() => _single;

  final WheelLogger wheel = const WheelLogger();
}

/// Набор рулеточных утилит для маршрутов/почты (CroupierKit)
class CroupierKit {
  // Похоже ли на "голый" e-mail без схемы
  static bool looksLikeBareMail(Uri u) {
    final s = u.scheme;
    if (s.isNotEmpty) return false;
    final raw = u.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  // Превращает "bare" или обычный URL в mailto:
  static Uri toMailto(Uri u) {
    final full = u.toString();
    final bits = full.split('?');
    final who = bits.first;
    final qp = bits.length > 1 ? Uri.splitQueryString(bits[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: who,
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  // Делает Gmail compose-ссылку
  static Uri gmailize(Uri m) {
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

  static String justDigits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
}

/// Сервис открытия внешних ссылок/протоколов (RouletteLinker)
class RouletteLinker {
  static Future<bool> open(Uri u) async {
    try {
      if (await launchUrl(u, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('RouletteLinker error: $e; url=$u');
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// FCM Background Handler — рулеточный крупье в бэкграунде
// ============================================================================
@pragma('vm:entry-point')
Future<void> roulette_bg_dealer(RemoteMessage spinMsg) async {
  debugPrint("Spin ID: ${spinMsg.messageId}");
  debugPrint("Spin Data: ${spinMsg.data}");
}

// ============================================================================
// Виджет-стол с webview — RouletteTableView
// ============================================================================
class RouletteTableView extends StatefulWidget with WidgetsBindingObserver {
  String startingLane;
  RouletteTableView(this.startingLane, {super.key});

  @override
  State<RouletteTableView> createState() => _RouletteTableViewState(startingLane);
}

class _RouletteTableViewState extends State<RouletteTableView> with WidgetsBindingObserver {
  _RouletteTableViewState(this._currentLane);

  final RouletteVault _vault = RouletteVault();

  late InAppWebViewController _wheelController; // штурвал — рулевое колесо :)
  String? _pushToken; // FCM token
  String? _deviceId; // device id
  String? _osBuild; // os build
  String? _platformKind; // android/ios
  String? _userLocale; // locale/lang
  String? _tzName; // timezone
  bool _pushEnabled = true; // push enabled
  bool _overlayBusy = false;
  var _gateOpen = true;
  String _currentLane;
  DateTime? _lastPausedAt;

  // Внешние “столы” (tg/wa/bnl)
  final Set<String> _externalHosts = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'bnl.com', 'www.bnl.com',
  };
  final Set<String> _externalSchemes = {'tg', 'telegram', 'whatsapp', 'bnl'};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(roulette_bg_dealer);

    _initPushAndGetToken();
    _scanDeviceDeck();
    _wireForegroundPushHandlers();
    _bindPlatformNotificationTap();

    // Плейсхолдерные таймеры
    Future.delayed(const Duration(seconds: 2), () {});
    Future.delayed(const Duration(seconds: 6), () {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lastPausedAt = DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      if (Platform.isIOS && _lastPausedAt != null) {
        final now = DateTime.now();
        final drift = now.difference(_lastPausedAt!);
        if (drift > const Duration(minutes: 25)) {
          _forceReloadToLobby();
        }
      }
      _lastPausedAt = null;
    }
  }

  void _forceReloadToLobby() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

    });
  }

  // --------------------------------------------------------------------------
  // Каналы связи: FCM, подписи
  // --------------------------------------------------------------------------
  void _wireForegroundPushHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        _navigateTo(msg.data['uri'].toString());
      } else {
        _returnToCurrentLane();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        _navigateTo(msg.data['uri'].toString());
      } else {
        _returnToCurrentLane();
      }
    });
  }

  void _navigateTo(String newLane) async {
    await _wheelController.loadUrl(urlRequest: URLRequest(url: WebUri(newLane)));
  }

  void _returnToCurrentLane() async {
    Future.delayed(const Duration(seconds: 3), () {
      _wheelController.loadUrl(urlRequest: URLRequest(url: WebUri(_currentLane)));
    });
  }

  Future<void> _initPushAndGetToken() async {
    FirebaseMessaging fm = FirebaseMessaging.instance;
    await fm.requestPermission(alert: true, badge: true, sound: true);
    _pushToken = await fm.getToken();
  }

  // --------------------------------------------------------------------------
  // Сканер “стола” — устройство и окружение
  // --------------------------------------------------------------------------
  Future<void> _scanDeviceDeck() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        _deviceId = a.id;
        _platformKind = "android";
        _osBuild = a.version.release;
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        _deviceId = i.identifierForVendor;
        _platformKind = "ios";
        _osBuild = i.systemVersion;
      }
      final pkg = await PackageInfo.fromPlatform();
      _userLocale = Platform.localeName.split('_')[0];
      _tzName = timezone.local.name;
    } catch (e) {
      debugPrint("Device Scan Error: $e");
    }
  }

  /// Привязка метода от платформы: тап по уведомлению
  void _bindPlatformNotificationTap() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((MethodCall call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(call.arguments);
        debugPrint("URI from platform tap: ${payload['uri']}");
        final uri = payload["uri"]?.toString();
        if (uri != null && !uri.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => RouletteTableView(uri)),
                (route) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // Построение UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Повторная привязка — как в оригинале
    _bindPlatformNotificationTap();

    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
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
              initialUrlRequest: URLRequest(url: WebUri(_currentLane)),
              onWebViewCreated: (controller) {
                _wheelController = controller;

                _wheelController.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (args) {
                    _vault.wheel.log("JS Args: $args");
                    try {
                      return args.reduce((v, e) => v + e);
                    } catch (_) {
                      return args.toString();
                    }
                  },
                );
              },
              onLoadStart: (controller, uri) async {
                if (uri != null) {
                  if (CroupierKit.looksLikeBareMail(uri)) {
                    try {
                      await controller.stopLoading();
                    } catch (_) {}
                    final mailto = CroupierKit.toMailto(uri);
                    await RouletteLinker.open(CroupierKit.gmailize(mailto));
                    return;
                  }
                  final s = uri.scheme.toLowerCase();
                  if (s != 'http' && s != 'https') {
                    try {
                      await controller.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (controller, uri) async {
                await controller.evaluateJavascript(source: "console.log('Hello from Roulette JS!');");
              },
              shouldOverrideUrlLoading: (controller, nav) async {
                final uri = nav.request.url;
                if (uri == null) return NavigationActionPolicy.ALLOW;

                if (CroupierKit.looksLikeBareMail(uri)) {
                  final mailto = CroupierKit.toMailto(uri);
                  await RouletteLinker.open(CroupierKit.gmailize(mailto));
                  return NavigationActionPolicy.CANCEL;
                }

                final sch = uri.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await RouletteLinker.open(CroupierKit.gmailize(uri));
                  return NavigationActionPolicy.CANCEL;
                }

                if (_isExternalTable(uri)) {
                  await RouletteLinker.open(_mapExternalToHttp(uri));
                  return NavigationActionPolicy.CANCEL;
                }

                if (sch != 'http' && sch != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (controller, req) async {
                final u = req.request.url;
                if (u == null) return false;

                if (CroupierKit.looksLikeBareMail(u)) {
                  final m = CroupierKit.toMailto(u);
                  await RouletteLinker.open(CroupierKit.gmailize(m));
                  return false;
                }

                final sch = u.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await RouletteLinker.open(CroupierKit.gmailize(u));
                  return false;
                }

                if (_isExternalTable(u)) {
                  await RouletteLinker.open(_mapExternalToHttp(u));
                  return false;
                }

                if (sch == 'http' || sch == 'https') {
                  controller.loadUrl(urlRequest: URLRequest(url: u));
                }
                return false;
              },
            ),

            if (_overlayBusy)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: CircularProgressIndicator(
                      backgroundColor: Colors.grey.shade800,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                      strokeWidth: 6,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // Рулеточные утилиты маршрутов (протоколы/внешние “столы”)
  // ========================================================================
  bool _isExternalTable(Uri u) {
    final sch = u.scheme.toLowerCase();
    if (_externalSchemes.contains(sch)) return true;

    if (sch == 'http' || sch == 'https') {
      final h = u.host.toLowerCase();
      if (_externalHosts.contains(h)) return true;
    }
    return false;
  }

  Uri _mapExternalToHttp(Uri u) {
    final sch = u.scheme.toLowerCase();

    if (sch == 'tg' || sch == 'telegram') {
      final qp = u.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {
          if (qp['start'] != null) 'start': qp['start']!,
        });
      }
      final path = u.path.isNotEmpty ? u.path : '';
      return Uri.https('t.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if (sch == 'whatsapp') {
      final qp = u.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${CroupierKit.justDigits(phone)}', {
          if (text != null && text.isNotEmpty) 'text': text,
        });
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    if (sch == 'bnl') {
      final newPath = u.path.isNotEmpty ? u.path : '';
      return Uri.https('bnl.com', '/$newPath', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    return u;
  }
}