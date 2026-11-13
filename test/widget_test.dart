import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remember/main.dart';

void main() {
  testWidgets('添加待办后保存在本地并显示在列表', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(RememberApp(prefs: prefs));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '交电费');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待办').last);
    await tester.pumpAndSettle();
    expect(find.text('交电费'), findsOneWidget);
    expect(prefs.getString('tasks'), contains('交电费'));
  });
  testWidgets('物品数量降低到阈值时显示补充提示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(RememberApp(prefs: prefs));
    await tester.tap(find.text('物品').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '洗衣液');
    await tester.enterText(find.byType(TextField).at(1), '2');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('减少数量'));
    await tester.pumpAndSettle();
    expect(find.textContaining('需要补充'), findsOneWidget);
    expect(prefs.getString('items'), contains('洗衣液'));
  });
  testWidgets('完成重复待办后生成下一次', (tester) async {
    final now = DateTime.now();
    final future = now.add(const Duration(days: 2));
    SharedPreferences.setMockInitialValues({
      'nextId': 1,
      'tasks': jsonEncode([
        {
          'id': 1,
          'title': '每周打扫',
          'note': '',
          'done': false,
          'repeat': 'weekly',
          'remindAt': future.toIso8601String()
        }
      ])
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(RememberApp(prefs: prefs));
    await tester.tap(find.text('待办').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    final saved = jsonDecode(prefs.getString('tasks')!) as List;
    expect(saved.length, 2);
    expect(saved[0]['done'], true);
    expect(saved[1]['done'], false);
    expect(DateTime.parse(saved[1]['remindAt'] as String).day,
        future.add(const Duration(days: 7)).day);
  });
  testWidgets('每月任务在月末完成时按下月最后一天续期', (tester) async {
    SharedPreferences.setMockInitialValues({
      'nextId': 1,
      'tasks': jsonEncode([
        {
          'id': 1,
          'title': '月末检查',
          'note': '',
          'done': false,
          'repeat': 'monthly',
          'remindAt': '2030-01-31T09:00:00.000'
        }
      ])
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(RememberApp(prefs: prefs));
    await tester.tap(find.text('待办').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    final saved = jsonDecode(prefs.getString('tasks')!) as List;
    expect(DateTime.parse(saved[1]['remindAt'] as String),
        DateTime(2030, 2, 28, 9));
  });
}
