import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'reminders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final reminders = Reminders();
  await reminders.initialize();
  runApp(RememberApp(prefs: prefs, reminders: reminders));
}

class RememberApp extends StatelessWidget {
  const RememberApp({super.key, required this.prefs, this.reminders});
  final SharedPreferences prefs;
  final Reminders? reminders;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '记得',
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        supportedLocales: const [Locale('zh', 'CN')],
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: Home(prefs: prefs, reminders: reminders),
      );
}

class Home extends StatefulWidget {
  const Home({super.key, required this.prefs, this.reminders});
  final SharedPreferences prefs;
  final Reminders? reminders;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> items = [];
  String? error;

  @override
  void initState() {
    super.initState();
    try {
      tasks = (jsonDecode(widget.prefs.getString('tasks') ?? '[]') as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      items = (jsonDecode(widget.prefs.getString('items') ?? '[]') as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      error = '数据读取失败，请勿继续修改，避免覆盖原有数据。';
    }
  }

  Future<void> save() async {
    await widget.prefs.setString('tasks', jsonEncode(tasks));
    await widget.prefs.setString('items', jsonEncode(items));
  }

  int newId() {
    final next = (widget.prefs.getInt('nextId') ?? 0) + 1;
    widget.prefs.setInt('nextId', next);
    return next;
  }

  Future<void> syncTask(Map<String, dynamic> task) async {
    final reminders = widget.reminders;
    final id = task['id'] as int?;
    if (reminders == null || id == null) return;
    await reminders.cancel(id);
    final time = DateTime.tryParse(task['remindAt'] as String? ?? '');
    if (time != null && task['done'] != true) {
      await reminders.schedule(id, task['title'] as String, time,
          body: task['note'] as String? ?? '',
          repeat: task['repeat'] as String? ?? 'none');
    }
  }

  DateTime nextOccurrence(DateTime current, String repeat) {
    if (repeat == 'monthly') {
      final first = DateTime(current.year, current.month + 1, 1);
      final last = DateTime(first.year, first.month + 1, 0).day;
      return DateTime(
          first.year,
          first.month,
          current.day > last ? last : current.day,
          current.hour,
          current.minute);
    }
    return DateTime(
        current.year,
        current.month,
        current.day + (repeat == 'weekly' ? 7 : 1),
        current.hour,
        current.minute);
  }

  Future<void> toggleTask(int index, bool done) async {
    final task = tasks[index];
    Map<String, dynamic>? next;
    if (done &&
        task['done'] != true &&
        task['repeat'] != null &&
        task['repeat'] != 'none' &&
        task['remindAt'] != null) {
      var date = DateTime.parse(task['remindAt'] as String);
      do {
        date = nextOccurrence(date, task['repeat'] as String);
      } while (!date.isAfter(DateTime.now()));
      next = {
        ...task,
        'id': newId(),
        'done': false,
        'remindAt': date.toIso8601String()
      };
    }
    setState(() {
      task['done'] = done;
      if (next != null) tasks.add(next);
    });
    await save();
    await syncTask(task);
    if (next != null) await syncTask(next);
  }

  Future<void> editTask([int? index]) async {
    final old = index == null ? null : tasks[index];
    final title = TextEditingController(text: old?['title'] as String? ?? '');
    final note = TextEditingController(text: old?['note'] as String? ?? '');
    DateTime? when = DateTime.tryParse(old?['remindAt'] as String? ?? '');
    String repeat = old?['repeat'] as String? ?? 'none';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
                title: Text(old == null ? '添加待办' : '编辑待办'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: title,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: '标题')),
                  TextField(
                      controller: note,
                      decoration: const InputDecoration(labelText: '备注')),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          when == null ? '设置提醒时间' : '提醒：${formatDate(when!)}'),
                      trailing: when == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => refresh(() => when = null)),
                      onTap: () async {
                        final now = DateTime.now();
                        final date = await showDatePicker(
                            context: context,
                            initialDate: when != null && when!.isAfter(now)
                                ? when!
                                : now,
                            firstDate: DateTime(now.year, now.month, now.day),
                            lastDate: DateTime(now.year + 10));
                        if (date == null || !context.mounted) return;
                        final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(when ?? now));
                        if (time != null) {
                          refresh(() => when = DateTime(date.year, date.month,
                              date.day, time.hour, time.minute));
                        }
                      }),
                  DropdownButtonFormField<String>(
                      initialValue: repeat,
                      decoration: const InputDecoration(labelText: '重复'),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('不重复')),
                        DropdownMenuItem(value: 'daily', child: Text('每天')),
                        DropdownMenuItem(value: 'weekly', child: Text('每周')),
                        DropdownMenuItem(value: 'monthly', child: Text('每月'))
                      ],
                      onChanged: (v) => refresh(() => repeat = v ?? 'none')),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () {
                        if (title.text.trim().isEmpty) return;
                        if (when != null && !when!.isAfter(DateTime.now())) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请选择未来的提醒时间')));
                          return;
                        }
                        Navigator.pop(context, {
                          'id': old?['id'] ?? newId(),
                          'title': title.text.trim(),
                          'note': note.text.trim(),
                          'done': old?['done'] ?? false,
                          'remindAt': when?.toIso8601String(),
                          'repeat': repeat
                        });
                      },
                      child: const Text('保存'))
                ],
              )),
    );
    if (result == null || !mounted) return;
    if (result['remindAt'] != null && widget.reminders != null) {
      final allowed = await widget.reminders!.requestPermission();
      if (!allowed && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('通知权限未开启，请在系统设置中启用')));
      }
    }
    setState(() {
      if (index == null) {
        tasks.add(result);
      } else {
        tasks[index] = result;
      }
    });
    await save();
    try {
      await syncTask(result);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('提醒设置失败，请检查系统通知设置')));
      }
    }
  }

  String formatDate(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<void> syncItem(Map<String, dynamic> item) async {
    final id = item['id'] as int?;
    if (id == null || widget.reminders == null) return;
    await widget.reminders!.cancel(id);
    final expiry = DateTime.tryParse(item['expiry'] as String? ?? '');
    if (expiry != null) {
      final alert = DateTime(expiry.year, expiry.month, expiry.day, 9)
          .subtract(Duration(days: item['advance'] as int? ?? 1));
      await widget.reminders!
          .schedule(id, '${item['name']}即将到期', alert, body: '请及时使用或处理');
    }
  }

  Future<void> editItem([int? index]) async {
    final old = index == null ? null : items[index];
    final name = TextEditingController(text: old?['name'] as String? ?? '');
    final quantity = TextEditingController(text: '${old?['quantity'] ?? 1}');
    final unit = TextEditingController(text: old?['unit'] as String? ?? '个');
    final threshold = TextEditingController(text: '${old?['threshold'] ?? 1}');
    final advance = TextEditingController(text: '${old?['advance'] ?? 1}');
    DateTime? expiry = DateTime.tryParse(old?['expiry'] as String? ?? '');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
                title: Text(old == null ? '添加物品' : '编辑物品'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: '名称')),
                  TextField(
                      controller: quantity,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '当前数量')),
                  TextField(
                      controller: unit,
                      decoration: const InputDecoration(labelText: '单位')),
                  TextField(
                      controller: threshold,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '低库存阈值')),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(expiry == null
                          ? '设置到期日期'
                          : '到期：${formatDate(expiry!).split(' ').first}'),
                      trailing: expiry == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => refresh(() => expiry = null)),
                      onTap: () async {
                        final now = DateTime.now();
                        final date = await showDatePicker(
                            context: context,
                            initialDate: expiry ?? now,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(now.year + 20));
                        if (date != null) refresh(() => expiry = date);
                      }),
                  TextField(
                      controller: advance,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: '到期前提醒天数（上午 9 点）')),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () {
                        final q = double.tryParse(quantity.text);
                        final t = double.tryParse(threshold.text);
                        final days = int.tryParse(advance.text);
                        if (name.text.trim().isEmpty ||
                            unit.text.trim().isEmpty ||
                            q == null ||
                            t == null ||
                            !q.isFinite ||
                            !t.isFinite ||
                            q < 0 ||
                            t < 0 ||
                            days == null ||
                            days < 0 ||
                            days > 3650) {
                          return;
                        }
                        Navigator.pop(context, {
                          'id': old?['id'] ?? newId(),
                          'name': name.text.trim(),
                          'quantity': q,
                          'unit': unit.text.trim(),
                          'threshold': t,
                          'expiry': expiry?.toIso8601String(),
                          'advance': days
                        });
                      },
                      child: const Text('保存'))
                ],
              )),
    );
    if (result == null || !mounted) return;
    if (result['expiry'] != null && widget.reminders != null) {
      final allowed = await widget.reminders!.requestPermission();
      if (!allowed && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('通知权限未开启，请在系统设置中启用')));
      }
    }
    setState(() {
      if (index == null) {
        items.add(result);
      } else {
        items[index] = result;
      }
    });
    await save();
    try {
      await syncItem(result);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('到期提醒设置失败')));
      }
    }
  }

  Future<void> exportBackup() async {
    try {
      final content =
          jsonEncode({'version': 1, 'tasks': tasks, 'items': items});
      final path = await FilePicker.platform.saveFile(
          dialogTitle: '保存备份',
          fileName: 'remember-backup.json',
          bytes: Uint8List.fromList(utf8.encode(content)));
      if (path != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('备份已保存')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('备份失败')));
      }
    }
  }

  Future<void> importBackup() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('恢复备份？'),
                content: const Text('恢复会替换本机现有待办和物品，建议先导出备份。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('恢复'))
                ]));
    if (confirmed != true) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (picked == null) return;
      final f = picked.files.single;
      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (data['version'] != 1 ||
          data['tasks'] is! List ||
          data['items'] is! List) {
        throw const FormatException();
      }
      final restoredTasks = (data['tasks'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final restoredItems = (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      for (final t in restoredTasks) {
        if (t['title'] is! String ||
            t['done'] is! bool ||
            t['note'] is! String ||
            (t['repeat'] != null &&
                !['none', 'daily', 'weekly', 'monthly']
                    .contains(t['repeat'])) ||
            (t['remindAt'] != null &&
                (t['remindAt'] is! String ||
                    DateTime.tryParse(t['remindAt'] as String) == null))) {
          throw const FormatException();
        }
      }
      for (final i in restoredItems) {
        if (i['name'] is! String ||
            i['unit'] is! String ||
            i['quantity'] is! num ||
            i['threshold'] is! num ||
            i['quantity'] < 0 ||
            i['threshold'] < 0 ||
            (i['expiry'] != null &&
                (i['expiry'] is! String ||
                    DateTime.tryParse(i['expiry'] as String) == null)) ||
            (i['advance'] != null &&
                (i['advance'] is! int ||
                    i['advance'] < 0 ||
                    i['advance'] > 3650))) {
          throw const FormatException();
        }
      }
      for (final t in tasks) {
        if (t['id'] is int) await widget.reminders?.cancel(t['id'] as int);
      }
      for (final t in restoredTasks) {
        t['id'] = newId();
      }
      for (final i in items) {
        if (i['id'] is int) await widget.reminders?.cancel(i['id'] as int);
      }
      for (final i in restoredItems) {
        i['id'] = newId();
      }
      setState(() {
        tasks = restoredTasks;
        items = restoredItems;
        error = null;
      });
      await save();
      for (final t in tasks) {
        await syncTask(t);
      }
      for (final i in items) {
        await syncItem(i);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('备份已恢复')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('恢复失败：文件无效或读取失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final low = items
        .where((e) => (e['quantity'] as num) <= (e['threshold'] as num))
        .length;
    final soon = items.where((item) {
      final expiry = DateTime.tryParse(item['expiry'] as String? ?? '');
      if (expiry == null) return false;
      final today = DateTime.now();
      return expiry.isBefore(DateTime(today.year, today.month, today.day + 4));
    }).length;
    return Scaffold(
      appBar: AppBar(title: Text(['记得', '待办', '物品'][tab]), actions: [
        PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export') {
                exportBackup();
              } else {
                importBackup();
              }
            },
            itemBuilder: (context) => const [
                  PopupMenuItem(value: 'export', child: Text('导出备份')),
                  PopupMenuItem(value: 'import', child: Text('恢复备份'))
                ])
      ]),
      body: error != null
          ? Center(child: Text(error!))
          : tab == 0
              ? ListView(padding: const EdgeInsets.all(20), children: [
                  Text('把重要的事，交给记得。',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  Card(
                      child: ListTile(
                          title: const Text('未完成的待办'),
                          trailing: Text(
                              '${tasks.where((e) => e['done'] != true).length}'),
                          onTap: () => setState(() => tab = 1))),
                  Card(
                      child: ListTile(
                          title: const Text('需要补充的物品'),
                          trailing: Text('$low'),
                          onTap: () => setState(() => tab = 2))),
                  Card(
                      child: ListTile(
                          title: const Text('临期或已过期'),
                          trailing: Text('$soon'),
                          onTap: () => setState(() => tab = 2))),
                  const SizedBox(height: 16),
                  Text('近期待办', style: Theme.of(context).textTheme.titleLarge),
                  ...tasks.where((t) => t['done'] != true).take(5).map((t) =>
                      ListTile(
                          title: Text(t['title'] as String),
                          subtitle: Text(t['remindAt'] == null
                              ? '未设置提醒'
                              : formatDate(
                                  DateTime.parse(t['remindAt'] as String))),
                          onTap: () => setState(() => tab = 1))),
                ])
              : tab == 1
                  ? tasks.isEmpty
                      ? const Center(child: Text('还没有待办，添加一件要记住的事吧'))
                      : ListView.builder(
                          itemCount: tasks.length,
                          itemBuilder: (context, i) => ListTile(
                                leading: Checkbox(
                                    value: tasks[i]['done'] == true,
                                    onChanged: (v) async {
                                      await toggleTask(i, v == true);
                                    }),
                                title: Text(tasks[i]['title'] as String),
                                subtitle: Text([
                                  tasks[i]['note'] as String? ?? '',
                                  if (tasks[i]['remindAt'] != null)
                                    formatDate(DateTime.parse(
                                        tasks[i]['remindAt'] as String))
                                ].where((x) => x.isNotEmpty).join(' · ')),
                                onTap: () => editTask(i),
                                trailing: IconButton(
                                    tooltip: '删除',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      final removed = tasks[i];
                                      setState(() => tasks.removeAt(i));
                                      await save();
                                      if (removed['id'] is int) {
                                        await widget.reminders
                                            ?.cancel(removed['id'] as int);
                                      }
                                    }),
                              ))
                  : items.isEmpty
                      ? const Center(child: Text('还没有物品，添加一个吧'))
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final item = items[i];
                            final q = item['quantity'] as num;
                            return ListTile(
                                title: Text(item['name'] as String),
                                subtitle: Text(
                                    '$q ${item['unit']}${q <= (item['threshold'] as num) ? ' · 需要补充' : ''}${item['expiry'] != null ? ' · 到期 ${formatDate(DateTime.parse(item['expiry'] as String)).split(' ').first}' : ''}'),
                                onTap: () => editItem(i),
                                trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                          tooltip: '减少数量',
                                          icon: const Icon(Icons.remove),
                                          onPressed: q <= 0
                                              ? null
                                              : () async {
                                                  setState(() =>
                                                      item['quantity'] = (q - 1)
                                                          .clamp(0,
                                                              double.infinity));
                                                  await save();
                                                }),
                                      IconButton(
                                          tooltip: '增加数量',
                                          icon: const Icon(Icons.add),
                                          onPressed: () async {
                                            setState(
                                                () => item['quantity'] = q + 1);
                                            await save();
                                          }),
                                      IconButton(
                                          tooltip: '删除',
                                          icon:
                                              const Icon(Icons.delete_outline),
                                          onPressed: () async {
                                            final removed = items[i];
                                            setState(() => items.removeAt(i));
                                            await save();
                                            if (removed['id'] is int) {
                                              await widget.reminders?.cancel(
                                                  removed['id'] as int);
                                            }
                                          }),
                                    ]));
                          }),
      floatingActionButton: error != null
          ? null
          : FloatingActionButton(
              onPressed: () {
                if (tab == 2) {
                  editItem();
                } else {
                  editTask();
                }
              },
              child: const Icon(Icons.add)),
      bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
            NavigationDestination(
                icon: Icon(Icons.check_circle_outline), label: '待办'),
            NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined), label: '物品'),
          ]),
    );
  }
}
