import 'package:flutter/material.dart';

/// Google Calendar event colours: `colorId` (as accepted by the API) -> name/swatch.
class EventColor {
  const EventColor(this.id, this.name, this.color);
  final String? id; // null = the calendar's own default colour
  final String name;
  final Color color;
}

const eventColors = [
  EventColor(null, 'Calendar default', Color(0xFF9E9E9E)),
  EventColor('1', 'Lavender', Color(0xFF7986CB)),
  EventColor('2', 'Sage', Color(0xFF33B679)),
  EventColor('3', 'Grape', Color(0xFF8E24AA)),
  EventColor('4', 'Flamingo', Color(0xFFE67C73)),
  EventColor('5', 'Banana', Color(0xFFF6BF26)),
  EventColor('6', 'Tangerine', Color(0xFFF4511E)),
  EventColor('7', 'Peacock', Color(0xFF039BE5)),
  EventColor('8', 'Graphite', Color(0xFF616161)),
  EventColor('9', 'Blueberry', Color(0xFF3F51B5)),
  EventColor('10', 'Basil', Color(0xFF0B8043)),
  EventColor('11', 'Tomato', Color(0xFFD50000)),
];

EventColor eventColorFor(String? id) =>
    eventColors.firstWhere((c) => c.id == id, orElse: () => eventColors.first);
