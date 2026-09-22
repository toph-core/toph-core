import 'package:intl/intl.dart';

extension NumberFormatExt on num {
  String get formatN => NumberFormat.currency(
    symbol: "so'm",
    locale: 'uz',
    decimalDigits: 0,
  ).format(this);

  String get formatNWithoutS => NumberFormat.currency(
    symbol: '',
    locale: 'uz',
    decimalDigits: 0,
  ).format(this);

  String get toKMB {
    return NumberFormat.compact(
      // locale: inject<SettingsCubit>().state.language,
    ).format(this);
  }

  /// `HH:MM:SS`, or `MM:SS` under an hour.
  ///
  /// Every field is zero-padded, including the hours. The two running-timer
  /// badges — `_TimerCompact` in the order actions bar and `_TimerBadgeRow` in
  /// the order sidebar — each carried a private copy of this that padded the
  /// hour, while this one did not, so the same elapsed time read `1:05:12` in
  /// one place and `01:05:12` in the other. Padding is the version the badges
  /// used and the one that keeps a ticking clock from changing width under the
  /// operator's eye; the copies are gone.
  String get toHHMMSS {
    final duration = Duration(seconds: toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final hStr = hours.toString().padLeft(2, '0');
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hStr:$mStr:$sStr';
    }
    return '$mStr:$sStr';
  }
}
