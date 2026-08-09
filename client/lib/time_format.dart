/// Split out of about_dialog.dart so devices/device_overview_screen.dart can
/// show the same "last synced" wording per device instead of duplicating it.
String formatRelativeTime(DateTime? time) {
  if (time == null) return 'Aldri';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'nå nettopp';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return 'for $m ${m == 1 ? 'minutt' : 'minutter'} siden';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return 'for $h ${h == 1 ? 'time' : 'timer'} siden';
  }
  final d = diff.inDays;
  return 'for $d ${d == 1 ? 'dag' : 'dager'} siden';
}
