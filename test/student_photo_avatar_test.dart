import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:edupro/alumnos/widgets/student_photo_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const studentPath = 'schools/synthetic-school/alumnos/synthetic-student';

void main() {
  testWidgets(
    'A private photo uses only the authenticated loader and does not reload on rebuild',
    (tester) async {
      final bytes = File('assets/logo.png').readAsBytesSync();
      var calls = 0;
      Future<Uint8List?> load(String path) async {
        calls++;
        expect(path, '$studentPath/profile.png');
        return bytes;
      }

      Widget photo() => MaterialApp(
        home: StudentPhotoAvatar(
          studentPath: studentPath,
          photoPath: '$studentPath/profile.png',
          loadPhoto: load,
        ),
      );
      await tester.pumpWidget(photo());
      await tester.pumpAndSettle();
      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
        isA<MemoryImage>(),
      );
      await tester.pumpWidget(photo());
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Another school path and provider errors fall back without leaking details',
    (tester) async {
      var calls = 0;
      Future<Uint8List?> load(String _) async {
        calls++;
        throw StateError('private-path');
      }

      await tester.pumpWidget(
        MaterialApp(
          home: StudentPhotoAvatar(
            studentPath: studentPath,
            photoPath:
                'schools/other-school/alumnos/synthetic-student/profile.png',
            loadPhoto: load,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byIcon(Icons.person), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: StudentPhotoAvatar(
            studentPath: studentPath,
            photoPath: '$studentPath/profile.png',
            loadPhoto: load,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.textContaining('private-path'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Switching students cannot keep the previous student photo while loading',
    (tester) async {
      final bytes = File('assets/logo.png').readAsBytesSync();
      final pending = Completer<Uint8List?>();
      Future<Uint8List?> load(String path) =>
          path.startsWith(studentPath) ? Future.value(bytes) : pending.future;
      await tester.pumpWidget(
        MaterialApp(
          home: StudentPhotoAvatar(
            studentPath: studentPath,
            photoPath: '$studentPath/profile.png',
            loadPhoto: load,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
        isA<MemoryImage>(),
      );
      const nextPath = 'schools/synthetic-school/alumnos/next-student';
      await tester.pumpWidget(
        MaterialApp(
          home: StudentPhotoAvatar(
            studentPath: nextPath,
            photoPath: '$nextPath/profile.png',
            loadPhoto: load,
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
        isNull,
      );
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
