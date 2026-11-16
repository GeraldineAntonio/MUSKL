import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:muskl/features/auth/google_auth.dart';

void main() {
  const reauth = GoogleSignInException(code: GoogleSignInExceptionCode.canceled, description: '[16] Account reauth failed.');
  test('clears a stale provider session and retries once', () async {
    var calls = 0;
    var cleared = 0;
    final value = await recoverGoogleAuthentication(
      authenticate: () async { if (++calls == 1) throw reauth; return 'ok'; },
      clearSession: () async { cleared++; },
    );
    expect(value, 'ok'); expect(calls, 2); expect(cleared, 1);
  });
  test('does not loop when reauthentication keeps failing', () async {
    var calls = 0;
    await expectLater(recoverGoogleAuthentication<String>(
      authenticate: () async { calls++; throw reauth; },
      clearSession: () async {},
    ), throwsA(isA<GoogleSignInException>()));
    expect(calls, 2);
  });
  test('does not retry an ordinary cancellation', () async {
    var cleared = false;
    await expectLater(recoverGoogleAuthentication<String>(
      authenticate: () async => throw const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      clearSession: () async { cleared = true; },
    ), throwsA(isA<GoogleSignInException>()));
    expect(cleared, false);
  });
}
