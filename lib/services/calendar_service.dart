import 'package:googleapis/calendar/v3.dart' as gcal;

import 'auth_service.dart';

class CalEvent {
  CalEvent(
    this.title,
    this.start,
    this.end, {
    this.allDay = false,
    this.colorId,
  });
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? colorId;
}

class CalendarService {
  CalendarService(this._auth);
  final AuthService _auth;

  Future<gcal.CalendarApi> _api() async =>
      gcal.CalendarApi(await _auth.client());

  /// Events on the primary calendar that overlap local calendar [day].
  Future<List<CalEvent>> eventsForDay(DateTime day) async {
    final api = await _api();
    final from = DateTime(day.year, day.month, day.day);
    final to = DateTime(day.year, day.month, day.day + 1);
    final res = await api.events.list(
      'primary',
      timeMin: from.toUtc(),
      timeMax: to.toUtc(),
      singleEvents: true,
      orderBy: 'startTime',
    );
    return [
      for (final e in res.items ?? <gcal.Event>[])
        if (e.status != 'cancelled')
          if (e.start?.dateTime != null)
            CalEvent(
              e.summary ?? '(no title)',
              e.start!.dateTime!.toLocal(),
              (e.end?.dateTime ?? e.start!.dateTime!).toLocal(),
            )
          else if (e.start?.date != null)
            CalEvent(
              e.summary ?? '(no title)',
              e.start!.date!,
              e.start!.date!,
              allDay: true,
            ),
    ];
  }

  Future<void> addEvent(
    String title,
    DateTime start,
    DateTime end, {
    String? colorId,
  }) async {
    final api = await _api();
    await api.events.insert(
      gcal.Event(
        summary: title,
        colorId: colorId,
        start: gcal.EventDateTime(dateTime: start.toUtc()),
        end: gcal.EventDateTime(dateTime: end.toUtc()),
      ),
      'primary',
    );
  }
}
