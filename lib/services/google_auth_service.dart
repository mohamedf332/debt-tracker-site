import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google Sign-In wrapper.
///
/// Uses the google_sign_in **6.x** API (`GoogleSignIn(scopes: [...])` +
/// `signIn()` / `signInSilently()`). Do NOT migrate this file to the 7.x
/// `GoogleSignIn.instance.initialize()` + `authenticate()` API unless
/// `google_sign_in` in pubspec.yaml is also bumped to ^7.0.0.
class GoogleAuthService {
  GoogleAuthService._();

  static final GoogleAuthService instance = GoogleAuthService._();

  /// Scope needed to read/write only files created by this app in Drive.
  static const String driveFileScope = 'https://www.googleapis.com/auth/drive.file';

  /// Android package name - must match the OAuth client in Google Cloud Console.
  static const String androidPackage = 'com.example.debt_tracker';

  /// SHA-1 of the debug keystore (`cd android && ./gradlew signingReport`).
  static const String debugSha1 =
      'D2:BC:ED:02:86:04:AC:07:B8:C6:CC:A0:8B:27:BD:EC:85:03:06:87';

  /// **Web** OAuth client ID (client type must be `Web`, not `Android`).
  ///
  /// Supply at build time when needed:
  ///   flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<id>.apps.googleusercontent.com
  ///
  /// Must stay empty unless you have a genuine Web client ID - passing an
  /// Android client ID here makes GMS reject the sign-in (DEVELOPER_ERROR 10)
  /// because requestIdToken() expects a Web audience.
  static const String webClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [driveFileScope],
    serverClientId: webClientId.isEmpty ? null : webClientId,
  );

  /// Translates a raw sign-in exception into a short, actionable message.
  /// `ApiException: 10` is DEVELOPER_ERROR - a Cloud Console misconfiguration.
  static String describeError(Object e) {
    final s = e.toString();
    if (s.contains('ApiException: 10') || s.contains('DEVELOPER_ERROR')) {
      return 'خطأ إعداد DEVELOPER_ERROR (10): لم يتم تسجيل بصمة SHA-1 أو اسم '
          'الحزمة في Google Cloud Console، أو لا يوجد Web client ID.';
    }
    if (s.contains('ApiException: 7')) {
      return 'لا يوجد اتصال بالإنترنت (ApiException 7).';
    }
    if (s.contains('ApiException: 12501')) {
      return 'تم إلغاء تسجيل الدخول من المستخدم.';
    }
    if (s.contains('ApiException: 12500')) {
      return 'تعذر إكمال تسجيل الدخول (12500). تحقق من OAuth consent screen.';
    }
    return 'فشل تسجيل الدخول بجوجل: $e';
  }

  /// Full remediation text, logged to the console (too long for a SnackBar).
  static String debugChecklist() => '''
[GoogleAuth] CHECKLIST for DEVELOPER_ERROR (10):
  1. package       = $androidPackage   (android/app/build.gradle.kts)
  2. debug SHA-1   = $debugSha1        (./gradlew signingReport)
  3. Google Cloud Console -> APIs & Services -> Credentials:
     - Android OAuth client  (package + SHA-1 from above)
     - Web OAuth client      (needed for serverClientId / requestIdToken)
  4. APIs & Services -> Library -> enable "Google Drive API"
  5. APIs & Services -> OAuth consent screen -> Test users -> add your email
  6. Provide the Web client ID via one of:
     flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<id>.apps.googleusercontent.com
     OR drop google-services.json into android/app/ (must contain a web client entry)
''';

  GoogleSignInAccount? _currentUser;

  /// Last error message from a failed call, null if the last call succeeded.
  String? lastError;

  GoogleSignInAccount? get currentUser => _currentUser;

  Stream<GoogleSignInAccount?> get onAuthStateChanged => _googleSignIn.onCurrentUserChanged;

  /// Interactive sign-in.
  ///
  /// * Returns the account on success.
  /// * Returns `null` when the user cancels the dialog (not an error).
  /// * **Rethrows** every real failure after logging it, so callers can never
  ///   mistake an error for a cancellation.
  Future<GoogleSignInAccount?> signIn() async {
    lastError = null;
    debugPrint('[GoogleAuth] signIn() starting. API=v6, scopes=[$driveFileScope]');
    debugPrint('[GoogleAuth] package=$androidPackage sha1=$debugSha1');
    debugPrint('[GoogleAuth] serverClientId=' +
        (webClientId.isEmpty
            ? '<unset> (relying on google-services.json default_web_client_id)'
            : webClientId));
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        _currentUser = account;
        debugPrint('[GoogleAuth] signIn() OK email=${account.email} id=${account.id}');
      } else {
        debugPrint('[GoogleAuth] signIn() returned null -> user cancelled dialog');
      }
      return account;
    } catch (e, st) {
      lastError = describeError(e);
      debugPrint('[GoogleAuth] signIn() FAILED: $e');
      debugPrint('[GoogleAuth] hint: $lastError');
      debugPrint('[GoogleAuth] stack:\n$st');
      if (e.toString().contains('ApiException: 10')) {
        debugPrint(debugChecklist());
      }
      rethrow;
    }
  }

  Future<GoogleSignInAccount?> signInSilently() async {
    lastError = null;
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        _currentUser = account;
        debugPrint('[GoogleAuth] signInSilently() OK email=${account.email}');
      } else {
        debugPrint('[GoogleAuth] signInSilently() returned null (no cached session)');
      }
      return account;
    } catch (e, st) {
      lastError = e.toString();
      debugPrint('[GoogleAuth] signInSilently() FAILED: $e\n$st');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
      debugPrint('[GoogleAuth] signOut() OK');
    } catch (e, st) {
      debugPrint('[GoogleAuth] signOut() FAILED: $e\n$st');
      rethrow;
    }
  }

  Future<String?> getAccessToken() async {
    if (_currentUser == null) {
      debugPrint('[GoogleAuth] getAccessToken() -> null (not signed in)');
      return null;
    }
    try {
      final authentication = await _currentUser!.authentication;
      debugPrint('[GoogleAuth] getAccessToken() OK (expires in '
          '${authentication.accessToken == null ? "n/a" : "obtained"})');
      return authentication.accessToken;
    } catch (e, st) {
      lastError = e.toString();
      debugPrint('[GoogleAuth] getAccessToken() FAILED: $e\n$st');
      return null;
    }
  }

  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
      _currentUser = null;
      debugPrint('[GoogleAuth] disconnect() OK');
    } catch (e, st) {
      debugPrint('[GoogleAuth] disconnect() FAILED: $e\n$st');
      rethrow;
    }
  }

  bool get isSignedIn => _currentUser != null;

  String? get currentUserEmail => _currentUser?.email;

  String? get currentUserId => _currentUser?.id;
}
