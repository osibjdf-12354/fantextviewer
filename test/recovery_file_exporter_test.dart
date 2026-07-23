import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fantextviewer/recovery_file_exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android recovery export streams through the host document creator',
    () async {
      const channel = MethodChannel('test/recovery-export');
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final exporter = RecoveryFileExporter(channel: channel, isAndroid: true);

      final exported = await exporter.export(
        File('/app/files/state.json.broken'),
      );

      expect(exported, isTrue);
      expect(received?.method, 'exportRecoveryFile');
      expect(received?.arguments, {
        'path': '/app/files/state.json.broken',
        'suggestedName': 'fantextviewer-state-recovery.json',
      });
    },
  );
}
