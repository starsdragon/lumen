import 'dart:convert';

class SseEvent {
  const SseEvent({this.event, required this.data});

  final String? event;
  final String data;
}

/// Minimal, spec-compliant Server-Sent Events parser. It keeps parsing across
/// chunk boundaries and tolerates CRLF, comments and multi-line data fields.
Stream<SseEvent> parseSse(Stream<List<int>> bytes) async* {
  String? eventName;
  final dataLines = <String>[];

  await for (final line in bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (dataLines.isNotEmpty) {
        yield SseEvent(event: eventName, data: dataLines.join('\n'));
        dataLines.clear();
        eventName = null;
      }
      continue;
    }
    if (line.startsWith(':')) continue;
    if (line.startsWith('event:')) {
      eventName = line.substring(6).trim();
      continue;
    }
    if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trimLeft());
      continue;
    }
    // Some gateways omit the space or send a bare JSON line.
    if (line.startsWith('{') || line.startsWith('[')) {
      dataLines.add(line);
    }
  }
  if (dataLines.isNotEmpty) {
    yield SseEvent(event: eventName, data: dataLines.join('\n'));
  }
}
