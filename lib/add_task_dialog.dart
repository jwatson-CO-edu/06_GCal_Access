import 'package:flutter/material.dart';

import 'event_colors.dart';
import 'services/calendar_service.dart';
import 'services/status_log.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Last minute of the day (23:59), offered as the final end time.
const _endOfDay = 23 * 60 + 59;

/// Minutes since midnight as 24-hour `HH:MM`.
String _hhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class AddTaskAppointmentDialog extends StatefulWidget {
  const AddTaskAppointmentDialog({
    super.key,
    required this.calendar,
    required this.log,
    required this.initialTitle,
  });

  final CalendarService calendar;
  final StatusLog log;
  final String initialTitle;

  @override
  State<AddTaskAppointmentDialog> createState() =>
      _AddTaskAppointmentDialogState();
}

class _AddTaskAppointmentDialogState extends State<AddTaskAppointmentDialog> {
  late final List<DateTime>
  _monthChoices; // first day of each of the next 12 months
  late DateTime _startMonth;
  late int _startDay;
  late int _startMin; // minutes since midnight, half-hour steps (00:00-23:30)
  late DateTime _endMonth;
  late int _endDay;
  late int _endMin; // half-hour steps, plus 23:59
  late final TextEditingController _titleCtl;
  String? _colorId;

  List<CalEvent>? _events;
  String? _eventsError;
  int _loadSeq = 0;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monthChoices = [
      for (var i = 0; i < 12; i++) DateTime(now.year, now.month + i),
    ];
    _startMonth = _endMonth = _monthChoices.first;
    _startDay = _endDay = now.day;
    _startMin = (now.hour * 60 + now.minute) ~/ 30 * 30;
    _endMin = _startMin + 30; // _startMin <= 23:30, so this is at most 24:00...
    _fixEndTime(); // ...which is clamped to 23:59 here.
    _titleCtl = TextEditingController(text: widget.initialTitle);
    _loadEvents();
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    super.dispose();
  }

  static int _daysIn(DateTime month) =>
      DateTime(month.year, month.month + 1, 0).day;

  bool get _sameDay => _endMonth == _startMonth && _endDay == _startDay;
  DateTime get _startDate =>
      DateTime(_startMonth.year, _startMonth.month, _startDay);
  DateTime _stamp(DateTime month, int day, int min) =>
      DateTime(month.year, month.month, day, min ~/ 60, min % 60);

  // The end can never precede the start: month/day choices start at the start
  // date, and on the same day only times after the start time are offered.

  /// Moves the end date to the start date (called whenever the start date changes).
  void _syncEndToStart() {
    _endMonth = _startMonth;
    _endDay = _startDay;
    _fixEndTime();
  }

  /// On a single-day appointment, keeps the end time strictly after the start time.
  void _fixEndTime() {
    if (_sameDay && _endMin <= _startMin) {
      _endMin = (_startMin + 30).clamp(0, _endOfDay);
    }
  }

  Future<void> _loadEvents() async {
    final seq = ++_loadSeq;
    setState(() {
      _events = null;
      _eventsError = null;
    });
    try {
      final events = await widget.calendar.eventsForDay(_startDate);
      if (!mounted || seq != _loadSeq) return;
      setState(() => _events = events);
    } catch (e, st) {
      if (!mounted || seq != _loadSeq) return;
      widget.log.error(e, st, 'Loading calendar events');
      setState(() => _eventsError = formatError(e));
    }
  }

  Future<void> _schedule() async {
    final title = _titleCtl.text.trim();
    final start = _stamp(_startMonth, _startDay, _startMin);
    final end = _stamp(_endMonth, _endDay, _endMin);
    if (title.isEmpty) {
      setState(() => _saveError = 'Enter a title.');
      return;
    }
    if (!end.isAfter(start)) {
      setState(
        () => _saveError = 'End must be after start.',
      ); // defensive; UI prevents it
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await widget.calendar.addEvent(title, start, end, colorId: _colorId);
    } catch (e, st) {
      widget.log.error(e, st, 'Scheduling "$title"');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = formatError(e);
      });
      return;
    }
    widget.log.info('Scheduled "$title" ${_fmtRange(start, end)}');
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Scheduled "$title"')));
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _fmtDate(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static String _fmtTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
  static String _fmtRange(DateTime s, DateTime e) =>
      '${_fmtDate(s)} ${_fmtTime(s)} - ${_fmtDate(e)} ${_fmtTime(e)}';

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    double width = 110,
  }) => SizedBox(
    width: width,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          items: items,
          onChanged: _saving ? null : onChanged,
        ),
      ),
    ),
  );

  List<DropdownMenuItem<DateTime>> _monthItems(Iterable<DateTime> months) => [
    for (final m in months)
      DropdownMenuItem(
        value: m,
        child: Text('${_months[m.month - 1]} ${m.year}'),
      ),
  ];

  List<DropdownMenuItem<int>> _dayItems(int from, int to) => [
    for (var d = from; d <= to; d++)
      DropdownMenuItem(value: d, child: Text('$d')),
  ];

  List<DropdownMenuItem<int>> _timeItems(Iterable<int> minutes) => [
    for (final m in minutes) DropdownMenuItem(value: m, child: Text(_hhmm(m))),
  ];

  Widget _eventsPanel(BuildContext context) {
    final dayStart = _startDate;
    final nextDay = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
    // Times in 24-hour form; an event spilling past the viewed day gets a date.
    String stamp(DateTime d, {bool isEnd = false}) {
      if (isEnd && d == nextDay) return '23:59';
      final inDay = !d.isBefore(dayStart) && d.isBefore(nextDay);
      return inDay ? _fmtTime(d) : '${_fmtDate(d)} ${_fmtTime(d)}';
    }

    Widget body;
    if (_eventsError != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _eventsError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _loadEvents, child: const Text('Retry')),
        ],
      );
    } else if (_events == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_events!.isEmpty) {
      body = const Text('No appointments this day.');
    } else {
      body = ListView(
        children: [
          for (final e in _events!)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: _Swatch(eventColorFor(e.colorId).color),
              title: Text(e.title),
              subtitle: Text(
                e.allDay
                    ? 'All day'
                    : '${stamp(e.start)} - ${stamp(e.end, isEnd: true)}',
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Appointments on ${_fmtDate(dayStart)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const Divider(),
        Expanded(child: body),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final halfHours = [for (var m = 0; m < 1440; m += 30) m];
    final startIdx = _monthChoices.indexOf(_startMonth);
    final endDayMin = _endMonth == _startMonth ? _startDay : 1;
    final endTimes = [
      ...halfHours,
      _endOfDay,
    ].where((m) => !_sameDay || m > _startMin);

    return AlertDialog(
      title: const Text('Add Task Appointment'),
      content: SizedBox(
        width: 820,
        height: 420,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _eventsPanel(context)),
            const VerticalDivider(width: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 12,
                      children: [
                        _dropdown<DateTime>(
                          label: 'Month',
                          value: _startMonth,
                          width: 130,
                          items: _monthItems(_monthChoices),
                          onChanged: (m) {
                            if (m == null) return;
                            setState(() {
                              _startMonth = m;
                              _startDay = _startDay.clamp(1, _daysIn(m));
                              _syncEndToStart();
                            });
                            _loadEvents();
                          },
                        ),
                        _dropdown<int>(
                          label: 'Day',
                          value: _startDay,
                          width: 80,
                          items: _dayItems(1, _daysIn(_startMonth)),
                          onChanged: (d) {
                            if (d == null) return;
                            setState(() {
                              _startDay = d;
                              _syncEndToStart();
                            });
                            _loadEvents();
                          },
                        ),
                        _dropdown<int>(
                          label: 'Time',
                          value: _startMin,
                          width: 90,
                          items: _timeItems(halfHours),
                          onChanged: (v) => setState(() {
                            if (v == null) return;
                            _startMin = v;
                            _fixEndTime();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('End', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 12,
                      children: [
                        _dropdown<DateTime>(
                          label: 'Month',
                          value: _endMonth,
                          width: 130,
                          items: _monthItems(_monthChoices.skip(startIdx)),
                          onChanged: (m) {
                            if (m == null) return;
                            setState(() {
                              _endMonth = m;
                              final lo = m == _startMonth ? _startDay : 1;
                              _endDay = _endDay.clamp(lo, _daysIn(m));
                              _fixEndTime();
                            });
                          },
                        ),
                        _dropdown<int>(
                          label: 'Day',
                          value: _endDay,
                          width: 80,
                          items: _dayItems(endDayMin, _daysIn(_endMonth)),
                          onChanged: (d) => setState(() {
                            if (d == null) return;
                            _endDay = d;
                            _fixEndTime();
                          }),
                        ),
                        _dropdown<int>(
                          label: 'Time',
                          value: _endMin,
                          width: 90,
                          items: _timeItems(endTimes),
                          onChanged: (v) =>
                              setState(() => _endMin = v ?? _endMin),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleCtl,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _dropdown<String?>(
                      label: 'Color',
                      value: _colorId,
                      width: 260,
                      items: [
                        for (final c in eventColors)
                          DropdownMenuItem<String?>(
                            value: c.id,
                            child: Row(
                              children: [
                                _Swatch(c.color),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    c.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _colorId = v),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _saving ? null : _schedule,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Schedule'),
                    ),
                    if (_saveError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _saveError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
