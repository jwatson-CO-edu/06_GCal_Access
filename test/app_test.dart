import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcal_access/add_task_dialog.dart';
import 'package:gcal_access/main.dart';
import 'package:gcal_access/services/auth_service.dart';
import 'package:gcal_access/services/calendar_service.dart';
import 'package:gcal_access/services/markdown_service.dart';
import 'package:gcal_access/services/status_log.dart';
// ignore: depend_on_referenced_packages
import 'package:_discoveryapis_commons/_discoveryapis_commons.dart'
    show ApiRequestErrorDetail, DetailedApiRequestError;

class FakeCalendar extends CalendarService {
  FakeCalendar() : super(AuthService());
  final added = <List<Object>>[];
  Object? failWith;

  @override
  Future<List<CalEvent>> eventsForDay(DateTime day) async => [
    CalEvent(
      'Standup',
      DateTime(day.year, day.month, day.day, 9),
      DateTime(day.year, day.month, day.day, 9, 30),
    ),
  ];

  @override
  Future<void> addEvent(
    String title,
    DateTime start,
    DateTime end, {
    String? colorId,
  }) async => failWith != null
      ? throw failWith!
      : added.add([title, start, end, colorId ?? '']);
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gcal_test');
    File('${tmp.path}/a.md')
        .writeAsStringSync('hi\n  - [ ] one  \n- [x] done\n- [ ] two\n');
    File('${tmp.path}/b.txt').writeAsStringSync('x');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('markdown helpers', () {
    expect(listMarkdownFiles(tmp.path), ['a.md']);
    expect(listMarkdownFiles('${tmp.path}/nope'), isNull);
    expect(extractTasks('${tmp.path}/a.md'), ['- [ ] one', '- [ ] two']);
  });

  testWidgets('main page shows files and tasks', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(GCalApp());
    await t.enterText(find.byType(TextField).first, '${tmp.path}/nope');
    await t.pump();
    expect(find.text('NO MARKDOWN HERE'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, tmp.path);
    await t.pump();
    expect(find.text('a.md'), findsOneWidget);

    await t.tap(find.text('a.md'));
    await t.pump();
    expect(find.text('- [ ] one\n- [ ] two'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, '${tmp.path}/nope');
    await t.pump();
    expect(find.text('NO MARKDOWN HERE'), findsOneWidget);
  });

  Future<FakeCalendar> openDialog(
    WidgetTester t,
    StatusLog log, {
    FakeCalendar? calendar,
  }) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final cal = calendar ?? FakeCalendar();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showDialog<void>(
                context: c,
                builder: (_) => AddTaskAppointmentDialog(
                  calendar: cal,
                  log: log,
                  initialTitle: 'one',
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    return cal;
  }

  // Dropdown order in the dialog: ints are [start day, start time, end day,
  // end time]; DateTimes are [start month, end month].
  Future<void> pick(
    WidgetTester t,
    Finder dropdown,
    String text, {
    bool up = false,
  }) async {
    await t.ensureVisible(dropdown);
    await t.tap(dropdown);
    await t.pumpAndSettle();
    // Menu items are built lazily, so scroll the open menu to the entry.
    final menu = find.byType(ListView).last;
    final item = find.descendant(of: menu, matching: find.text(text));
    if (item.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        item,
        up ? -60 : 60,
        scrollable: find
            .descendant(of: menu, matching: find.byType(Scrollable))
            .first,
      );
    }
    await t.ensureVisible(item.last);
    await t.pumpAndSettle();
    await t.tap(item.last);
    await t.pumpAndSettle();
  }

  final ints = find.byType(DropdownButton<int>);

  testWidgets('dialog schedules a default 30 minute appointment', (t) async {
    final log = StatusLog();
    final cal = await openDialog(t, log);
    expect(find.text('Add Task Appointment'), findsOneWidget);
    expect(find.text('Standup'), findsOneWidget);

    await t.tap(find.text('Schedule'));
    await t.pumpAndSettle();
    expect(cal.added.single[0], 'one');
    final s = cal.added.single[1] as DateTime,
        e = cal.added.single[2] as DateTime;
    expect(e.isAfter(s), isTrue);
    expect(find.text('Add Task Appointment'), findsNothing);
  });

  testWidgets('end follows start and can never precede it', (t) async {
    final cal = await openDialog(t, StatusLog());
    await pick(t, ints.at(0), '28'); // start day
    await pick(t, ints.at(1), '23:30'); // start time
    await t.tap(find.text('Schedule'));
    await t.pumpAndSettle();
    final s = cal.added.single[1] as DateTime,
        e = cal.added.single[2] as DateTime;
    expect([s.day, s.hour, s.minute], [28, 23, 30]);
    expect([e.day, e.hour, e.minute], [28, 23, 59]); // same day, last minute
  });

  testWidgets('multi-day appointment and colour', (t) async {
    final cal = await openDialog(t, StatusLog());
    await pick(t, ints.at(0), '27'); // start day -> end day follows
    await pick(t, ints.at(2), '28'); // end day
    await pick(
      t,
      ints.at(3),
      '00:30',
      up: true,
    ); // end time, earlier than start is fine across days
    await pick(t, find.byType(DropdownButton<String?>), 'Tomato');
    await t.tap(find.text('Schedule'));
    await t.pumpAndSettle();
    final s = cal.added.single[1] as DateTime,
        e = cal.added.single[2] as DateTime;
    expect([s.day, e.day, e.hour, e.minute], [27, 28, 0, 30]);
    expect(cal.added.single[3], '11');
  });

  testWidgets('changing start day resets end day', (t) async {
    final cal = await openDialog(t, StatusLog());
    await pick(t, ints.at(0), '27');
    await pick(t, ints.at(2), '28');
    await pick(t, ints.at(0), '26'); // end snaps back to the 26th
    await t.tap(find.text('Schedule'));
    await t.pumpAndSettle();
    final s = cal.added.single[1] as DateTime,
        e = cal.added.single[2] as DateTime;
    expect([s.day, e.day], [26, 26]);
    expect(e.isAfter(s), isTrue);
  });

  testWidgets('Google errors reach the status log', (t) async {
    final log = StatusLog();
    final cal = FakeCalendar()
      ..failWith = DetailedApiRequestError(
        403,
        'Forbidden',
        errors: [ApiRequestErrorDetail(reason: 'forbidden', domain: 'global')],
      );
    await openDialog(t, log, calendar: cal);
    await t.tap(find.text('Schedule'));
    await t.pumpAndSettle();
    expect(log.entries.last.level, StatusLevel.error);
    expect(log.entries.last.text, contains('Google API error 403: Forbidden'));
    expect(log.entries.last.text, contains('forbidden'));
    expect(find.text('Add Task Appointment'), findsOneWidget); // stays open
  });

  test('formatError', () {
    expect(
      formatError(DetailedApiRequestError(404, 'Not Found')),
      'Google API error 404: Not Found',
    );
    expect(formatError(StateError('bad')), contains('Bad state: bad'));
  });
}
