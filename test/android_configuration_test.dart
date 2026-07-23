import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Auto Backup is disabled for local reader state', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(manifest, contains('android:allowBackup="false"'));
  });

  test(
    'Android document metadata is queried inside import error handling',
    () async {
      final source = await File(
        'android/app/src/main/kotlin/com/songs/fantextviewer/MainActivity.kt',
      ).readAsString();
      final importStart = source.indexOf('private fun importUri(');
      final importEnd = source.indexOf('private fun promoteLegacyImport(');
      final importMethod = source.substring(importStart, importEnd);
      final executor = importMethod.indexOf('fileExecutor.execute {');
      final errorHandling = importMethod.indexOf('try {');
      final metadata = importMethod.indexOf(
        'val metadata = documentMetadata(uri)',
      );

      expect(importStart, greaterThanOrEqualTo(0));
      expect(importEnd, greaterThan(importStart));
      expect(executor, greaterThanOrEqualTo(0));
      expect(errorHandling, greaterThan(executor));
      expect(metadata, greaterThan(errorHandling));
    },
  );
}
