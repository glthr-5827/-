import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const OrbitPlanApp());
}

const _storageKey = 'orbitplan_v1_data';
final _dateFmt = DateFormat('yyyy-MM-dd');
final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm');

String uid() => '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}';
String todayKey() => _dateFmt.format(DateTime.now());

class OrbitPlanApp extends StatelessWidget {
  const OrbitPlanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OrbitPlan',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05060A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6675FF),
          brightness: Brightness.dark,
          background: const Color(0xFF05060A),
        ),
      ),
      home: const OrbitPlanShell(),
    );
  }
}

class OrbitPlanShell extends StatefulWidget {
  const OrbitPlanShell({super.key});

  @override
  State<OrbitPlanShell> createState() => _OrbitPlanShellState();
}

class _OrbitPlanShellState extends State<OrbitPlanShell> {
  AppData data = AppData.empty();
  bool loading = true;
  int tab = 0;

  List<String> get tabs => ['dashboard', 'habits', 'tasks', 'finance', 'notes', 'settings'];
  String get lang => data.language;
  bool get ru => lang == 'ru';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      data = AppData.sample(language: 'ru');
      await _save(schedule: true);
    } else {
      try {
        data = AppData.fromJson(jsonDecode(raw));
      } catch (_) {
        data = AppData.sample(language: 'ru');
      }
    }
    if (mounted) setState(() => loading = false);
    await _scheduleNotifications();
  }

  Future<void> _save({bool schedule = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(data.toJson()));
    if (schedule) await _scheduleNotifications();
  }

  Future<void> _scheduleNotifications() async {
    await NotificationService.instance.scheduleAll(data, t);
  }

  void mutate(void Function(AppData d) update, {bool schedule = true}) {
    setState(() => update(data));
    _save(schedule: schedule);
  }

  String t(String key) => translations[lang]?[key] ?? translations['ru']?[key] ?? key;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final accent = data.theme.primary;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              data.theme.bg,
              Color.alphaBlend(accent.withOpacity(0.08), data.theme.bg),
              data.theme.bg,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(title: t(tabs[tab]), onSeed: _confirmSeed, data: data, t: t),
              Expanded(child: _buildBody()),
              _BottomNav(
                current: tab,
                data: data,
                t: t,
                onTap: (i) => setState(() => tab = i),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: data.theme.primary,
        foregroundColor: Colors.white,
        onPressed: _quickAdd,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    switch (tab) {
      case 1:
        return HabitsScreen(data: data, t: t, mutate: mutate, onAdd: _addHabitDialog);
      case 2:
        return TasksScreen(data: data, t: t, mutate: mutate, onAdd: _addTaskDialog);
      case 3:
        return FinanceScreen(data: data, t: t, mutate: mutate, onAdd: _addMoneyDialog);
      case 4:
        return NotesScreen(data: data, t: t, mutate: mutate, onAdd: _addNoteDialog);
      case 5:
        return SettingsScreen(data: data, t: t, mutate: mutate, onTestNotification: _testNotification);
      default:
        return DashboardScreen(data: data, t: t, go: (i) => setState(() => tab = i));
    }
  }

  Future<void> _quickAdd() async {
    if (tab == 1) return _addHabitDialog();
    if (tab == 2) return _addTaskDialog();
    if (tab == 3) return _addMoneyDialog();
    if (tab == 4) return _addNoteDialog();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: data.theme.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _SheetButton(icon: Icons.repeat, label: t('habit'), onTap: () => Navigator.pop(context, 'habit')),
            _SheetButton(icon: Icons.check_circle_outline, label: t('task'), onTap: () => Navigator.pop(context, 'task')),
            _SheetButton(icon: Icons.account_balance_wallet_outlined, label: t('finance'), onTap: () => Navigator.pop(context, 'money')),
            _SheetButton(icon: Icons.note_alt_outlined, label: t('note'), onTap: () => Navigator.pop(context, 'note')),
          ]),
        ),
      ),
    );
    if (action == 'habit') await _addHabitDialog();
    if (action == 'task') await _addTaskDialog();
    if (action == 'money') await _addMoneyDialog();
    if (action == 'note') await _addNoteDialog();
  }

  Future<void> _confirmSeed() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: data.theme.card,
        title: Text(t('fillExamples')),
        content: Text(t('fillExamplesQuestion')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('fill'))),
        ],
      ),
    );
    if (ok == true) {
      mutate((d) {
        final newData = AppData.sample(language: d.language);
        newData.themeIndex = d.themeIndex;
        d.copyFrom(newData);
      });
    }
  }

  Future<void> _testNotification() async {
    await NotificationService.instance.requestPermissions();
    await NotificationService.instance.showNow(t('testNotification'), t('testNotificationBody'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('notificationSent'))));
    }
  }

  Future<void> _addHabitDialog() async {
    final title = TextEditingController();
    TimeOfDay reminder = const TimeOfDay(hour: 9, minute: 0);
    bool enabled = true;
    final result = await showDialog<Habit>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          backgroundColor: data.theme.card,
          title: Text(t('newHabit')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, autofocus: true, decoration: InputDecoration(labelText: t('habitName'))),
              const SizedBox(height: 12),
              SwitchListTile(
                value: enabled,
                onChanged: (v) => setLocal(() => enabled = v),
                title: Text(t('dailyReminder')),
                contentPadding: EdgeInsets.zero,
              ),
              if (enabled)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text('${t('time')}: ${reminder.format(ctx)}'),
                  onTap: () async {
                    final picked = await showTimePicker(context: ctx, initialTime: reminder);
                    if (picked != null) setLocal(() => reminder = picked);
                  },
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
            FilledButton(
              onPressed: () {
                final name = title.text.trim();
                if (name.isEmpty) return Navigator.pop(ctx);
                Navigator.pop(ctx, Habit(id: uid(), title: name, reminderTime: enabled ? timeToString(reminder) : null));
              },
              child: Text(t('save')),
            ),
          ],
        );
      }),
    );
    title.dispose();
    if (result != null) mutate((d) => d.habits.add(result));
  }

  Future<void> _addTaskDialog() async {
    final title = TextEditingController();
    String priority = 'medium';
    DateTime? dueAt;
    DateTime? reminderAt;
    final result = await showDialog<TaskItem>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        Future<DateTime?> pickDateTime(DateTime? initial) async {
          final base = initial ?? DateTime.now().add(const Duration(hours: 1));
          final date = await showDatePicker(context: ctx, initialDate: base, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365 * 2)));
          if (date == null) return null;
          final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(base));
          if (time == null) return null;
          return DateTime(date.year, date.month, date.day, time.hour, time.minute);
        }

        return AlertDialog(
          backgroundColor: data.theme.card,
          title: Text(t('newTask')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, autofocus: true, decoration: InputDecoration(labelText: t('taskName'))),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: priority,
                decoration: InputDecoration(labelText: t('priority')),
                items: ['low', 'medium', 'high'].map((p) => DropdownMenuItem(value: p, child: Text(t(p)))).toList(),
                onChanged: (v) => setLocal(() => priority = v ?? 'medium'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(dueAt == null ? t('setDeadline') : _dateTimeFmt.format(dueAt!)),
                trailing: dueAt == null ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setLocal(() => dueAt = null)),
                onTap: () async {
                  final dt = await pickDateTime(dueAt);
                  if (dt != null) setLocal(() => dueAt = dt);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(reminderAt == null ? t('setReminder') : _dateTimeFmt.format(reminderAt!)),
                trailing: reminderAt == null ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setLocal(() => reminderAt = null)),
                onTap: () async {
                  final dt = await pickDateTime(reminderAt ?? dueAt);
                  if (dt != null) setLocal(() => reminderAt = dt);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
            FilledButton(
              onPressed: () {
                final name = title.text.trim();
                if (name.isEmpty) return Navigator.pop(ctx);
                Navigator.pop(ctx, TaskItem(id: uid(), title: name, priority: priority, dueAt: dueAt, reminderAt: reminderAt));
              },
              child: Text(t('save')),
            ),
          ],
        );
      }),
    );
    title.dispose();
    if (result != null) mutate((d) => d.tasks.add(result));
  }

  Future<void> _addMoneyDialog() async {
    final title = TextEditingController();
    final amount = TextEditingController();
    final category = TextEditingController(text: ru ? 'Другое' : 'Other');
    String type = 'expense';
    final result = await showDialog<MoneyItem>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: data.theme.card,
        title: Text(t('newFinance')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: [ButtonSegment(value: 'expense', label: Text(t('expense'))), ButtonSegment(value: 'income', label: Text(t('income')))],
              selected: {type},
              onSelectionChanged: (v) => setLocal(() => type = v.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: title, decoration: InputDecoration(labelText: t('title'))),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('amount'))),
            TextField(controller: category, decoration: InputDecoration(labelText: t('category'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(
            onPressed: () {
              final name = title.text.trim();
              final value = double.tryParse(amount.text.replaceAll(',', '.'));
              if (name.isEmpty || value == null) return Navigator.pop(ctx);
              Navigator.pop(ctx, MoneyItem(id: uid(), title: name, amount: value, type: type, category: category.text.trim().isEmpty ? t('other') : category.text.trim(), date: DateTime.now()));
            },
            child: Text(t('save')),
          ),
        ],
      )),
    );
    title.dispose(); amount.dispose(); category.dispose();
    if (result != null) mutate((d) => d.money.add(result));
  }

  Future<void> _addNoteDialog({NoteItem? edit}) async {
    final title = TextEditingController(text: edit?.title ?? '');
    final body = TextEditingController(text: edit?.body ?? '');
    int color = edit?.color ?? noteColors[Random().nextInt(noteColors.length)].value;
    bool pinned = edit?.pinned ?? false;
    final result = await showDialog<NoteItem>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: data.theme.card,
        title: Text(edit == null ? t('newNote') : t('editNote')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: InputDecoration(labelText: t('noteTitle'))),
            const SizedBox(height: 10),
            TextField(controller: body, minLines: 4, maxLines: 8, decoration: InputDecoration(labelText: t('noteText'))),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: noteColors.map((c) => InkWell(
              onTap: () => setLocal(() => color = c.value),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: color == c.value ? Colors.white : Colors.transparent, width: 3)),
              ),
            )).toList()),
            SwitchListTile(value: pinned, onChanged: (v) => setLocal(() => pinned = v), title: Text(t('pinNote')), contentPadding: EdgeInsets.zero),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(
            onPressed: () {
              final name = title.text.trim();
              final text = body.text.trim();
              if (name.isEmpty && text.isEmpty) return Navigator.pop(ctx);
              Navigator.pop(ctx, NoteItem(id: edit?.id ?? uid(), title: name.isEmpty ? t('untitled') : name, body: text, color: color, pinned: pinned, createdAt: edit?.createdAt ?? DateTime.now()));
            },
            child: Text(t('save')),
          ),
        ],
      )),
    );
    title.dispose(); body.dispose();
    if (result != null) {
      mutate((d) {
        final i = d.notes.indexWhere((n) => n.id == result.id);
        if (i >= 0) d.notes[i] = result; else d.notes.add(result);
      });
    }
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onSeed;
  final AppData data;
  final String Function(String) t;
  const _TopBar({required this.title, required this.onSeed, required this.data, required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('EEE, d MMM').format(DateTime.now()), style: TextStyle(color: data.theme.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.7)),
        ])),
        IconButton.filledTonal(onPressed: onSeed, icon: const Icon(Icons.auto_awesome), tooltip: t('fillExamples')),
        const SizedBox(width: 10),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 2), boxShadow: [BoxShadow(color: data.theme.primary.withOpacity(.35), blurRadius: 20)]),
          clipBehavior: Clip.antiAlias,
          child: Image.asset('assets/logo.png', fit: BoxFit.cover),
        ),
      ]),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int current;
  final AppData data;
  final String Function(String) t;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.current, required this.data, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.dashboard_rounded, 'dashboard'),
      (Icons.repeat_rounded, 'habits'),
      (Icons.task_alt_rounded, 'tasks'),
      (Icons.account_balance_wallet_rounded, 'finance'),
      (Icons.note_alt_rounded, 'notes'),
      (Icons.settings_rounded, 'settings'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: data.theme.card.withOpacity(.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: data.theme.line),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: List.generate(items.length, (i) {
        final selected = i == current;
        return Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: selected ? data.theme.primary.withOpacity(.18) : Colors.transparent, borderRadius: BorderRadius.circular(22)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(items[i].$1, color: selected ? data.theme.primary : data.theme.muted),
                const SizedBox(height: 3),
                Text(t(items[i].$2), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: selected ? data.theme.primary : data.theme.muted)),
              ]),
            ),
          ),
        );
      })),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  final AppData data;
  final String Function(String) t;
  final ValueChanged<int> go;
  const DashboardScreen({super.key, required this.data, required this.t, required this.go});

  @override
  Widget build(BuildContext context) {
    final completedToday = data.habits.where((h) => h.doneToday).length;
    final activeTasks = data.tasks.where((x) => !x.done).length;
    final balance = data.income - data.expenses;
    final notes = data.notes.length;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 100), children: [
      _HeroCard(data: data, t: t),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.55,
        children: [
          StatCard(data: data, icon: Icons.repeat, label: t('habits'), value: '$completedToday/${data.habits.length}', onTap: () => go(1)),
          StatCard(data: data, icon: Icons.task_alt, label: t('tasks'), value: '$activeTasks', onTap: () => go(2)),
          StatCard(data: data, icon: Icons.wallet, label: t('balance'), value: money(balance), onTap: () => go(3)),
          StatCard(data: data, icon: Icons.note_alt, label: t('notes'), value: '$notes', onTap: () => go(4)),
        ],
      ),
      const SizedBox(height: 16),
      ActivityCard(data: data, t: t),
      const SizedBox(height: 16),
      _SectionCard(data: data, title: t('todayPlan'), child: Column(children: data.tasks.where((x) => !x.done).take(4).map((task) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(priorityIcon(task.priority), color: priorityColor(task.priority)),
        title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(task.dueAt == null ? t('noDeadline') : _dateTimeFmt.format(task.dueAt!), style: TextStyle(color: data.theme.muted)),
      )).toList())),
    ]);
  }
}

class _HeroCard extends StatelessWidget {
  final AppData data;
  final String Function(String) t;
  const _HeroCard({required this.data, required this.t});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(colors: [data.theme.primary.withOpacity(.24), data.theme.card, data.theme.card2]),
        border: Border.all(color: data.theme.line),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('OrbitPlan', style: TextStyle(color: data.theme.primary, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(t('heroTitle'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.05)),
          const SizedBox(height: 8),
          Text(t('heroText'), style: TextStyle(color: data.theme.muted, fontWeight: FontWeight.w600)),
        ])),
        const SizedBox(width: 10),
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(color: data.theme.primary.withOpacity(.14), shape: BoxShape.circle),
          child: Icon(Icons.auto_graph_rounded, color: data.theme.primary, size: 44),
        )
      ]),
    );
  }
}

class HabitsScreen extends StatelessWidget {
  final AppData data;
  final String Function(String) t;
  final void Function(void Function(AppData), {bool schedule}) mutate;
  final VoidCallback onAdd;
  const HabitsScreen({super.key, required this.data, required this.t, required this.mutate, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 100), children: [
      FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(t('newHabit'))),
      const SizedBox(height: 14),
      for (final habit in data.habits)
        Dismissible(
          key: ValueKey(habit.id),
          background: _deleteBg(),
          onDismissed: (_) => mutate((d) => d.habits.removeWhere((h) => h.id == habit.id)),
          child: _Card(data: data, child: ListTile(
            leading: CircleAvatar(backgroundColor: data.theme.primary.withOpacity(.15), child: Icon(Icons.repeat, color: data.theme.primary)),
            title: Text(habit.title, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${t('streak')}: ${habit.streak} · ${habit.reminderTime ?? t('noReminder')}', style: TextStyle(color: data.theme.muted)),
            trailing: Checkbox(
              value: habit.doneToday,
              onChanged: (_) => mutate((d) {
                final h = d.habits.firstWhere((x) => x.id == habit.id);
                h.toggleToday();
              }, schedule: false),
            ),
          )),
        ),
    ]);
  }
}

class TasksScreen extends StatelessWidget {
  final AppData data;
  final String Function(String) t;
  final void Function(void Function(AppData), {bool schedule}) mutate;
  final VoidCallback onAdd;
  const TasksScreen({super.key, required this.data, required this.t, required this.mutate, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final tasks = [...data.tasks]..sort((a, b) => (a.done ? 1 : 0).compareTo(b.done ? 1 : 0));
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 100), children: [
      FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(t('newTask'))),
      const SizedBox(height: 14),
      for (final task in tasks)
        Dismissible(
          key: ValueKey(task.id),
          background: _deleteBg(),
          onDismissed: (_) => mutate((d) => d.tasks.removeWhere((x) => x.id == task.id)),
          child: _Card(data: data, child: CheckboxListTile(
            value: task.done,
            onChanged: (v) => mutate((d) => d.tasks.firstWhere((x) => x.id == task.id).done = v ?? false),
            title: Text(task.title, style: TextStyle(fontWeight: FontWeight.w900, decoration: task.done ? TextDecoration.lineThrough : null)),
            subtitle: Text([
              t(task.priority),
              if (task.dueAt != null) _dateTimeFmt.format(task.dueAt!),
              if (task.reminderAt != null) '🔔 ${_dateTimeFmt.format(task.reminderAt!)}',
            ].join(' · '), style: TextStyle(color: data.theme.muted)),
            secondary: Icon(priorityIcon(task.priority), color: priorityColor(task.priority)),
          )),
        ),
    ]);
  }
}

class FinanceScreen extends StatelessWidget {
  final AppData data;
  final String Function(String) t;
  final void Function(void Function(AppData), {bool schedule}) mutate;
  final VoidCallback onAdd;
  const FinanceScreen({super.key, required this.data, required this.t, required this.mutate, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final balance = data.income - data.expenses;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 100), children: [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.55,
        children: [
          StatCard(data: data, icon: Icons.trending_up, label: t('income'), value: money(data.income)),
          StatCard(data: data, icon: Icons.trending_down, label: t('expense'), value: money(data.expenses)),
          StatCard(data: data, icon: Icons.savings, label: t('balance'), value: money(balance)),
          StatCard(data: data, icon: Icons.receipt_long, label: t('records'), value: '${data.money.length}'),
        ],
      ),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(t('newFinance'))),
      const SizedBox(height: 14),
      for (final item in data.money.reversed)
        Dismissible(
          key: ValueKey(item.id),
          background: _deleteBg(),
          onDismissed: (_) => mutate((d) => d.money.removeWhere((m) => m.id == item.id), schedule: false),
          child: _Card(data: data, child: ListTile(
            leading: CircleAvatar(backgroundColor: (item.type == 'income' ? Colors.green : Colors.red).withOpacity(.14), child: Icon(item.type == 'income' ? Icons.add : Icons.remove, color: item.type == 'income' ? Colors.greenAccent : Colors.redAccent)),
            title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${item.category} · ${_dateFmt.format(item.date)}', style: TextStyle(color: data.theme.muted)),
            trailing: Text((item.type == 'income' ? '+' : '-') + money(item.amount), style: const TextStyle(fontWeight: FontWeight.w900)),
          )),
        ),
    ]);
  }
}

class NotesScreen extends StatefulWidget {
  final AppData data;
  final String Function(String) t;
  final void Function(void Function(AppData), {bool schedule}) mutate;
  final Future<void> Function({NoteItem? edit}) onAdd;
  const NotesScreen({super.key, required this.data, required this.t, required this.mutate, required this.onAdd});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final notes = widget.data.notes.where((n) => (n.title + n.body).toLowerCase().contains(query.toLowerCase())).toList()
      ..sort((a, b) => (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0));
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 100), children: [
      TextField(
        onChanged: (v) => setState(() => query = v),
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: widget.t('searchNotes'), filled: true, fillColor: widget.data.theme.card, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: () => widget.onAdd(), icon: const Icon(Icons.add), label: Text(widget.t('newNote'))),
      const SizedBox(height: 14),
      for (final note in notes)
        Dismissible(
          key: ValueKey(note.id),
          background: _deleteBg(),
          onDismissed: (_) => widget.mutate((d) => d.notes.removeWhere((n) => n.id == note.id), schedule: false),
          child: NoteCard(data: widget.data, note: note, onTap: () => widget.onAdd(edit: note)),
        ),
    ]);
  }
}

class SettingsScreen extends StatelessWidget {
  final AppData data;
  final String Function(String) t;
  final void Function(void Function(AppData), {bool schedule}) mutate;
  final VoidCallback onTestNotification;
  const SettingsScreen({super.key, required this.data, required this.t, required this.mutate, required this.onTestNotification});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 100), children: [
      _SectionCard(data: data, title: t('language'), child: SegmentedButton<String>(
        selected: {data.language},
        segments: const [ButtonSegment(value: 'ru', label: Text('RU')), ButtonSegment(value: 'en', label: Text('EN'))],
        onSelectionChanged: (v) => mutate((d) => d.language = v.first, schedule: false),
      )),
      const SizedBox(height: 14),
      _SectionCard(data: data, title: t('theme'), child: Wrap(spacing: 10, runSpacing: 10, children: List.generate(themes.length, (i) {
        final th = themes[i];
        return ChoiceChip(
          label: Text(th.name),
          selected: data.themeIndex == i,
          onSelected: (_) => mutate((d) => d.themeIndex = i, schedule: false),
          avatar: CircleAvatar(backgroundColor: th.primary),
        );
      }))),
      const SizedBox(height: 14),
      _SectionCard(data: data, title: t('notifications'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('notificationsText'), style: TextStyle(color: data.theme.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: onTestNotification, icon: const Icon(Icons.notifications_active), label: Text(t('testNotification'))),
      ])),
      const SizedBox(height: 14),
      _SectionCard(data: data, title: t('aboutApp'), child: Text(t('aboutText'), style: TextStyle(color: data.theme.muted, fontWeight: FontWeight.w600))),
    ]);
  }
}

class StatCard extends StatelessWidget {
  final AppData data;
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const StatCard({super.key, required this.data, required this.icon, required this.label, required this.value, this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: _Card(data: data, child: Row(children: [
        CircleAvatar(radius: 28, backgroundColor: data.theme.primary.withOpacity(.16), child: Icon(icon, color: data.theme.primary, size: 28)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 6),
          Text(value, overflow: TextOverflow.ellipsis, style: TextStyle(color: data.theme.muted, fontWeight: FontWeight.w900, fontSize: 22)),
        ])),
      ])),
    );
  }
}

class ActivityCard extends StatelessWidget {
  final AppData data;
  final String Function(String) t;
  const ActivityCard({super.key, required this.data, required this.t});
  @override
  Widget build(BuildContext context) {
    final days = List.generate(84, (i) => DateTime.now().subtract(Duration(days: 83 - i)));
    return _SectionCard(data: data, title: t('activity'), subtitle: t('activitySubtitle'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 5, runSpacing: 5, children: days.map((day) {
        final key = _dateFmt.format(day);
        final count = data.habits.where((h) => h.completions[key] == true).length;
        final alpha = count == 0 ? .09 : min(.22 + count * .17, .95);
        return Container(width: 13, height: 13, decoration: BoxDecoration(color: count == 0 ? Colors.white.withOpacity(.08) : data.theme.primary.withOpacity(alpha), borderRadius: BorderRadius.circular(4)));
      }).toList()),
      const SizedBox(height: 14),
      Row(children: [Text(t('less'), style: TextStyle(color: data.theme.muted, fontWeight: FontWeight.w700)), const SizedBox(width: 8), ...List.generate(5, (i) => Container(margin: const EdgeInsets.only(right: 5), width: 14, height: 14, decoration: BoxDecoration(color: data.theme.primary.withOpacity(.15 + i * .17), borderRadius: BorderRadius.circular(4)))), const SizedBox(width: 4), Text(t('more'), style: TextStyle(color: data.theme.muted, fontWeight: FontWeight.w700))]),
    ]));
  }
}

class NoteCard extends StatelessWidget {
  final AppData data;
  final NoteItem note;
  final VoidCallback onTap;
  const NoteCard({super.key, required this.data, required this.note, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bg = Color(note.color);
    final fg = bg.computeLuminance() > 0.45 ? const Color(0xFF111827) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(note.title, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 18))), if (note.pinned) Icon(Icons.push_pin, color: fg)]),
          if (note.body.isNotEmpty) ...[const SizedBox(height: 8), Text(note.body, maxLines: 5, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withOpacity(.88), height: 1.35, fontWeight: FontWeight.w600))],
        ]),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final AppData data;
  final String title;
  final String? subtitle;
  final Widget child;
  const _SectionCard({required this.data, required this.title, this.subtitle, required this.child});
  @override
  Widget build(BuildContext context) {
    return _Card(data: data, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: TextStyle(color: data.theme.muted, fontWeight: FontWeight.w700))],
      const SizedBox(height: 14),
      child,
    ]));
  }
}

class _Card extends StatelessWidget {
  final AppData data;
  final Widget child;
  const _Card({required this.data, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: data.theme.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: data.theme.line),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: child,
    );
  }
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SheetButton({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(leading: Icon(icon), title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)), onTap: onTap);
}

Widget _deleteBg() => Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 22), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red.withOpacity(.25), borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.delete, color: Colors.redAccent));

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool ready = false;

  Future<void> init() async {
    tz.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {}
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    ready = true;
  }

  Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  NotificationDetails details() => const NotificationDetails(
    android: AndroidNotificationDetails(
      'orbitplan_reminders',
      'OrbitPlan reminders',
      channelDescription: 'Tasks and habits reminders',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    ),
  );

  Future<void> showNow(String title, String body) async {
    await requestPermissions();
    await _plugin.show(1, title, body, details());
  }

  Future<void> scheduleAll(AppData data, String Function(String) t) async {
    if (!ready) return;
    await _plugin.cancelAll();
    await requestPermissions();
    for (final habit in data.habits) {
      if (habit.reminderTime == null) continue;
      final tod = parseTime(habit.reminderTime!);
      var when = tz.TZDateTime(tz.local, DateTime.now().year, DateTime.now().month, DateTime.now().day, tod.hour, tod.minute);
      if (when.isBefore(tz.TZDateTime.now(tz.local))) when = when.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        100000 + stableId(habit.id),
        t('habitReminder'),
        habit.title,
        when,
        details(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
    for (final task in data.tasks) {
      if (task.done || task.reminderAt == null) continue;
      final when = tz.TZDateTime.from(task.reminderAt!, tz.local);
      if (when.isBefore(tz.TZDateTime.now(tz.local))) continue;
      await _plugin.zonedSchedule(
        200000 + stableId(task.id),
        t('taskReminder'),
        task.title,
        when,
        details(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}

class AppData {
  String language;
  int themeIndex;
  List<Habit> habits;
  List<TaskItem> tasks;
  List<MoneyItem> money;
  List<NoteItem> notes;

  AppData({required this.language, required this.themeIndex, required this.habits, required this.tasks, required this.money, required this.notes});
  factory AppData.empty() => AppData(language: 'ru', themeIndex: 0, habits: [], tasks: [], money: [], notes: []);
  AppTheme get theme => themes[themeIndex.clamp(0, themes.length - 1).toInt()];
  double get income => money.where((m) => m.type == 'income').fold(0, (s, m) => s + m.amount);
  double get expenses => money.where((m) => m.type == 'expense').fold(0, (s, m) => s + m.amount);

  void copyFrom(AppData other) {
    language = other.language;
    themeIndex = other.themeIndex;
    habits = other.habits;
    tasks = other.tasks;
    money = other.money;
    notes = other.notes;
  }

  Map<String, dynamic> toJson() => {
    'language': language,
    'themeIndex': themeIndex,
    'habits': habits.map((x) => x.toJson()).toList(),
    'tasks': tasks.map((x) => x.toJson()).toList(),
    'money': money.map((x) => x.toJson()).toList(),
    'notes': notes.map((x) => x.toJson()).toList(),
  };

  factory AppData.fromJson(Map<String, dynamic> json) => AppData(
    language: json['language'] ?? 'ru',
    themeIndex: json['themeIndex'] ?? 0,
    habits: (json['habits'] as List? ?? []).map((x) => Habit.fromJson(x)).toList(),
    tasks: (json['tasks'] as List? ?? []).map((x) => TaskItem.fromJson(x)).toList(),
    money: (json['money'] as List? ?? []).map((x) => MoneyItem.fromJson(x)).toList(),
    notes: (json['notes'] as List? ?? []).map((x) => NoteItem.fromJson(x)).toList(),
  );

  factory AppData.sample({required String language}) {
    final r = Random();
    final habitNames = language == 'ru'
        ? ['Вода', 'Спорт', 'Чтение', 'Английский', 'Сон до 23:30', 'Прогулка']
        : ['Water', 'Workout', 'Reading', 'English', 'Sleep before 23:30', 'Walk'];
    final taskNames = language == 'ru'
        ? ['Сделать домашнее задание', 'Оплатить интернет', 'Составить план недели', 'Купить продукты', 'Проверить бюджет']
        : ['Do homework', 'Pay internet bill', 'Plan the week', 'Buy groceries', 'Check budget'];
    final noteNames = language == 'ru'
        ? ['Идеи', 'План недели', 'Список покупок', 'Цели']
        : ['Ideas', 'Weekly plan', 'Shopping list', 'Goals'];
    final habits = habitNames.take(4 + r.nextInt(2)).map((name) {
      final h = Habit(id: uid(), title: name, reminderTime: '${8 + r.nextInt(12)}:${r.nextBool() ? '00' : '30'}');
      for (int i = 0; i < 40; i++) {
        if (r.nextDouble() > .42) h.completions[_dateFmt.format(DateTime.now().subtract(Duration(days: i)))] = true;
      }
      return h;
    }).toList();
    final tasks = taskNames.map((name) {
      final due = DateTime.now().add(Duration(days: r.nextInt(8), hours: r.nextInt(8) + 9));
      return TaskItem(id: uid(), title: name, priority: ['low', 'medium', 'high'][r.nextInt(3)], dueAt: due, reminderAt: due.subtract(const Duration(hours: 1)));
    }).toList();
    final money = <MoneyItem>[
      MoneyItem(id: uid(), title: language == 'ru' ? 'Зарплата' : 'Salary', amount: (65000 + r.nextInt(40000)).toDouble(), type: 'income', category: language == 'ru' ? 'Работа' : 'Work', date: DateTime.now()),
      MoneyItem(id: uid(), title: language == 'ru' ? 'Продукты' : 'Groceries', amount: (3500 + r.nextInt(3000)).toDouble(), type: 'expense', category: language == 'ru' ? 'Еда' : 'Food', date: DateTime.now()),
      MoneyItem(id: uid(), title: language == 'ru' ? 'Транспорт' : 'Transport', amount: (900 + r.nextInt(1200)).toDouble(), type: 'expense', category: language == 'ru' ? 'Дорога' : 'Travel', date: DateTime.now()),
      MoneyItem(id: uid(), title: language == 'ru' ? 'Книги' : 'Books', amount: (1200 + r.nextInt(2000)).toDouble(), type: 'expense', category: language == 'ru' ? 'Учёба' : 'Study', date: DateTime.now()),
    ];
    final notes = noteNames.map((name) => NoteItem(id: uid(), title: name, body: language == 'ru' ? 'Короткая заметка для планирования и быстрых мыслей.' : 'A short note for planning and quick thoughts.', color: noteColors[r.nextInt(noteColors.length)].value, pinned: r.nextBool(), createdAt: DateTime.now())).toList();
    return AppData(language: language, themeIndex: 0, habits: habits, tasks: tasks, money: money, notes: notes);
  }
}

class Habit {
  String id;
  String title;
  String? reminderTime;
  Map<String, bool> completions;
  Habit({required this.id, required this.title, this.reminderTime, Map<String, bool>? completions}) : completions = completions ?? {};
  bool get doneToday => completions[todayKey()] == true;
  int get streak {
    int s = 0;
    for (int i = 0; i < 365; i++) {
      if (completions[_dateFmt.format(DateTime.now().subtract(Duration(days: i)))] == true) s++; else break;
    }
    return s;
  }
  void toggleToday() {
    final k = todayKey();
    completions[k] = !(completions[k] == true);
  }
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'reminderTime': reminderTime, 'completions': completions};
  factory Habit.fromJson(Map<String, dynamic> j) => Habit(id: j['id'], title: j['title'], reminderTime: j['reminderTime'], completions: Map<String, bool>.from(j['completions'] ?? {}));
}

class TaskItem {
  String id;
  String title;
  String priority;
  bool done;
  DateTime? dueAt;
  DateTime? reminderAt;
  TaskItem({required this.id, required this.title, required this.priority, this.done = false, this.dueAt, this.reminderAt});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'priority': priority, 'done': done, 'dueAt': dueAt?.toIso8601String(), 'reminderAt': reminderAt?.toIso8601String()};
  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(id: j['id'], title: j['title'], priority: j['priority'] ?? 'medium', done: j['done'] ?? false, dueAt: parseDate(j['dueAt']), reminderAt: parseDate(j['reminderAt']));
}

class MoneyItem {
  String id;
  String title;
  double amount;
  String type;
  String category;
  DateTime date;
  MoneyItem({required this.id, required this.title, required this.amount, required this.type, required this.category, required this.date});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'amount': amount, 'type': type, 'category': category, 'date': date.toIso8601String()};
  factory MoneyItem.fromJson(Map<String, dynamic> j) => MoneyItem(id: j['id'], title: j['title'], amount: (j['amount'] as num).toDouble(), type: j['type'], category: j['category'], date: parseDate(j['date']) ?? DateTime.now());
}

class NoteItem {
  String id;
  String title;
  String body;
  int color;
  bool pinned;
  DateTime createdAt;
  NoteItem({required this.id, required this.title, required this.body, required this.color, required this.pinned, required this.createdAt});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'body': body, 'color': color, 'pinned': pinned, 'createdAt': createdAt.toIso8601String()};
  factory NoteItem.fromJson(Map<String, dynamic> j) => NoteItem(id: j['id'], title: j['title'], body: j['body'] ?? '', color: j['color'] ?? noteColors.first.value, pinned: j['pinned'] ?? false, createdAt: parseDate(j['createdAt']) ?? DateTime.now());
}

class AppTheme {
  final String name;
  final Color bg, card, card2, primary, muted, line;
  const AppTheme({required this.name, required this.bg, required this.card, required this.card2, required this.primary, required this.muted, required this.line});
}

const themes = [
  AppTheme(name: 'Orbit', bg: Color(0xFF05060A), card: Color(0xFF17181E), card2: Color(0xFF101116), primary: Color(0xFF6574FF), muted: Color(0xFFA7A9B8), line: Color(0xFF292B34)),
  AppTheme(name: 'Ocean', bg: Color(0xFF031014), card: Color(0xFF102027), card2: Color(0xFF08181E), primary: Color(0xFF28C6DD), muted: Color(0xFFA6BBC2), line: Color(0xFF1E3A43)),
  AppTheme(name: 'Violet', bg: Color(0xFF100A17), card: Color(0xFF201527), card2: Color(0xFF170F1D), primary: Color(0xFFB56CFF), muted: Color(0xFFBEAFC9), line: Color(0xFF372544)),
  AppTheme(name: 'Forest', bg: Color(0xFF06110C), card: Color(0xFF13231A), card2: Color(0xFF0C1911), primary: Color(0xFF42D685), muted: Color(0xFFA8BFAF), line: Color(0xFF234030)),
];

final noteColors = [
  const Color(0xFFFFD166), const Color(0xFFEF476F), const Color(0xFF06D6A0), const Color(0xFF118AB2),
  const Color(0xFF8338EC), const Color(0xFFFAF3DD), const Color(0xFF2B2D42), const Color(0xFF8D99AE),
];

DateTime? parseDate(dynamic value) => value == null || value == '' ? null : DateTime.tryParse(value.toString());
String timeToString(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
TimeOfDay parseTime(String raw) {
  final p = raw.split(':');
  return TimeOfDay(hour: int.tryParse(p.first) ?? 9, minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}
String money(double value) => NumberFormat.compactCurrency(symbol: '₽', decimalDigits: 0).format(value);
int stableId(String id) => id.codeUnits.fold(0, (a, b) => (a * 31 + b) & 0x7fffffff) % 90000;
IconData priorityIcon(String p) => p == 'high' ? Icons.priority_high_rounded : p == 'low' ? Icons.keyboard_arrow_down_rounded : Icons.remove_rounded;
Color priorityColor(String p) => p == 'high' ? Colors.redAccent : p == 'low' ? Colors.greenAccent : Colors.amberAccent;

const translations = {
  'ru': {
    'dashboard': 'Главная', 'habits': 'Привычки', 'tasks': 'Задачи', 'finance': 'Финансы', 'notes': 'Заметки', 'settings': 'Настройки',
    'habit': 'Привычка', 'task': 'Задача', 'note': 'Заметка', 'balance': 'Баланс', 'records': 'Записи',
    'heroTitle': 'Панель жизни в одном месте', 'heroText': 'Планы, привычки, деньги и заметки работают оффлайн и всегда под рукой.',
    'todayPlan': 'План на сегодня', 'activity': 'Активность', 'activitySubtitle': 'Отметки привычек за последние недели', 'less': 'Меньше', 'more': 'Больше',
    'newHabit': 'Новая привычка', 'habitName': 'Название привычки', 'dailyReminder': 'Ежедневное напоминание', 'time': 'Время', 'streak': 'Серия', 'noReminder': 'Без напоминания',
    'newTask': 'Новая задача', 'taskName': 'Название задачи', 'priority': 'Приоритет', 'low': 'Низкий', 'medium': 'Средний', 'high': 'Высокий', 'deadline': 'Дедлайн', 'setDeadline': 'Выбрать дедлайн', 'setReminder': 'Выбрать напоминание', 'noDeadline': 'Без дедлайна',
    'newFinance': 'Новая запись', 'income': 'Доходы', 'expense': 'Расходы', 'title': 'Название', 'amount': 'Сумма', 'category': 'Категория', 'other': 'Другое',
    'newNote': 'Новая заметка', 'editNote': 'Редактировать заметку', 'noteTitle': 'Заголовок', 'noteText': 'Текст', 'pinNote': 'Закрепить', 'untitled': 'Без названия', 'searchNotes': 'Поиск заметок',
    'language': 'Язык', 'theme': 'Тема', 'notifications': 'Уведомления', 'notificationsText': 'Привычки напоминают каждый день, задачи — по выбранной дате и времени. Приложение работает оффлайн.', 'testNotification': 'Тест уведомления', 'testNotificationBody': 'OrbitPlan готов отправлять напоминания.', 'notificationSent': 'Уведомление отправлено',
    'fillExamples': 'Заполнить примером', 'fillExamplesQuestion': 'Текущие данные будут заменены случайными примерами. Продолжить?', 'fill': 'Заполнить', 'cancel': 'Отмена', 'save': 'Сохранить',
    'habitReminder': 'Напоминание о привычке', 'taskReminder': 'Напоминание о задаче', 'aboutApp': 'О приложении', 'aboutText': 'OrbitPlan — бесплатное оффлайн-приложение для личного планирования без подписок и тарифов.',
  },
  'en': {
    'dashboard': 'Home', 'habits': 'Habits', 'tasks': 'Tasks', 'finance': 'Finance', 'notes': 'Notes', 'settings': 'Settings',
    'habit': 'Habit', 'task': 'Task', 'note': 'Note', 'balance': 'Balance', 'records': 'Records',
    'heroTitle': 'Your life dashboard', 'heroText': 'Plans, habits, money and notes work offline and stay close to you.',
    'todayPlan': 'Today plan', 'activity': 'Activity', 'activitySubtitle': 'Habit marks from recent weeks', 'less': 'Less', 'more': 'More',
    'newHabit': 'New habit', 'habitName': 'Habit name', 'dailyReminder': 'Daily reminder', 'time': 'Time', 'streak': 'Streak', 'noReminder': 'No reminder',
    'newTask': 'New task', 'taskName': 'Task name', 'priority': 'Priority', 'low': 'Low', 'medium': 'Medium', 'high': 'High', 'deadline': 'Deadline', 'setDeadline': 'Set deadline', 'setReminder': 'Set reminder', 'noDeadline': 'No deadline',
    'newFinance': 'New record', 'income': 'Income', 'expense': 'Expenses', 'title': 'Title', 'amount': 'Amount', 'category': 'Category', 'other': 'Other',
    'newNote': 'New note', 'editNote': 'Edit note', 'noteTitle': 'Title', 'noteText': 'Text', 'pinNote': 'Pin note', 'untitled': 'Untitled', 'searchNotes': 'Search notes',
    'language': 'Language', 'theme': 'Theme', 'notifications': 'Notifications', 'notificationsText': 'Habits remind you daily; tasks remind you by selected date and time. The app works offline.', 'testNotification': 'Test notification', 'testNotificationBody': 'OrbitPlan is ready to send reminders.', 'notificationSent': 'Notification sent',
    'fillExamples': 'Fill with examples', 'fillExamplesQuestion': 'Current data will be replaced with random examples. Continue?', 'fill': 'Fill', 'cancel': 'Cancel', 'save': 'Save',
    'habitReminder': 'Habit reminder', 'taskReminder': 'Task reminder', 'aboutApp': 'About app', 'aboutText': 'OrbitPlan is a free offline personal planning app without subscriptions or paid plans.',
  }
};
