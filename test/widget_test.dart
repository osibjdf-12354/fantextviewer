import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/main.dart';

void main() {
  testWidgets('앱이 한국어 제목과 파일 탐색 버튼으로 시작한다', (tester) async {
    final store = _MemoryStore();

    await tester.pumpWidget(GeulbomApp(store: store));

    expect(find.text('판갤텍뷰'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open), findsWidgets);
    expect(find.text('최근에 읽은 파일이 없습니다.'), findsOneWidget);
  });
}

class _MemoryStore extends AppStore {
  _MemoryStore() : super(File('unused'));

  @override
  Future<void> save() async {}
}
