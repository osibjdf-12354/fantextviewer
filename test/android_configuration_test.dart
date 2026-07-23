import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Auto Backup is disabled for local reader state', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(manifest, contains('android:allowBackup="false"'));
  });
}
