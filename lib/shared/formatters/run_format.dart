String formatRunDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String formatPaceDuration(Duration? pace) {
  if (pace == null || pace.inSeconds <= 0) return '--:--';
  final seconds = pace.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${pace.inMinutes}:$seconds';
}
