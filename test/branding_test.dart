import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fantextviewer/strings.dart';

void main() {
  test('current product names use fantextviewer and 판갤텍뷰', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final gradle = await File('android/app/build.gradle.kts').readAsString();
    final keystoreTool = await File(
      'tool/create_local_keystore.ps1',
    ).readAsString();

    expect(AppStrings.appName, '판갤텍뷰');
    expect(pubspec, contains('name: fantextviewer'));
    expect(gradle, contains('namespace = "com.songs.fantextviewer"'));
    expect(gradle, contains('applicationId = "com.songs.geulbom"'));
    expect(keystoreTool, contains('fantextviewer-local.jks'));
    expect(keystoreTool, isNot(contains('geulbom-local')));
  });
}
