import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muskl/features/client_home_content.dart';
import 'package:muskl/features/auth/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (font.existsSync()) {
      final loader = FontLoader('Preview');
      loader.addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
  });

  Future<void> mount(WidgetTester tester, Widget child, {double width = 390, double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF101216),
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Preview'),
      ),
      builder: (context, widget) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: widget!),
      home: RepaintBoundary(key: const ValueKey('preview'), child: child),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final folder = Platform.environment['UI_PREVIEW_DIR'];
    if (folder == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('preview')));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(folder).create(recursive: true);
      await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('home shows the correct next step and navigates to routine', (tester) async {
    String? route;
    await mount(tester, Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: ClientHomeContent(
      data: const {'first_name': 'Ana', 'routine_name': 'Fuerza y movilidad', 'trainer_name': 'Daniel', 'attendance_total': 18, 'gym_attendance_streak': 3, 'plan_name': 'Mensual'},
      onNavigate: (value) => route = value,
    ))));
    await capture(tester, 'inicio');
    await tester.tap(find.text('Ver mi rutina'));
    expect(route, '/home/routine');
  });

  testWidgets('small screen and large text preserve onboarding action', (tester) async {
    String? route;
    await mount(tester, Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: ClientHomeContent(data: const {}, onNavigate: (value) => route = value))), width: 320, scale: 1.6);
    await tester.ensureVisible(find.text('Elegir entrenador'));
    await tester.tap(find.text('Elegir entrenador'));
    expect(route, '/home/trainers');
    expect(tester.takeException(), isNull);
  });

  testWidgets('login has readable actions and no unconfigured Apple button', (tester) async {
    await mount(tester, const LoginScreen());
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Continuar con Apple'), findsNothing);
    await capture(tester, 'acceso');
  });
}
