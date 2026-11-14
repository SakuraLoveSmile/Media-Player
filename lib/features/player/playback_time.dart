/// `mm:ss`, widened to `hh:mm:ss` only for long items.
String formatPlaybackTime(Duration value) {
  final total = value.isNegative ? Duration.zero : value;
  final minutes = total.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (total.inHours > 0) {
    return '${total.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
