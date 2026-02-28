import 'package:flutter/services.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

class AppFormatter {
  const AppFormatter._();

  static String formatDate(DateTime date) {
    int year = date.year;
    String month = date.month.toString().padLeft(2, '0');
    String day = date.day.toString().padLeft(2, '0');
    String formatted = '$day.$month.$year';

    return formatted;
  }

  static String formatTimeFromMills(num mills, {bool hasSecond = false}) {
    DateTime date = DateTime.fromMillisecondsSinceEpoch(mills.toInt());
    String hour = date.hour.toString().padLeft(2, '0');
    String minute = date.minute.toString().padLeft(2, '0');
    String second = date.second.toString().padLeft(2, '0');

    String formatted = '$hour:$minute';
    String withSecond = '$hour:$minute:$second';
    return hasSecond ? withSecond : formatted;
  }

  static final dateFormatterDDMMYYY = MaskTextInputFormatter(
    mask: '##-##-####',
    filter: {"#": RegExp(r'[0-9]')},
  );

  static TextInputFormatter get formatYYYYMMDD =>
      TextInputFormatter.withFunction((oldValue, newValue) {
        String text = newValue.text.replaceAll(RegExp(r'\D'), '');

        if (text.length > 8) {
          text = text.substring(0, 8);
        }

        String formatted = '';
        for (int i = 0; i < text.length; i++) {
          if (i == 4 || i == 6) {
            formatted += ' ';
          }
          formatted += text[i];
        }

        return TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      });

  static final uzPhoneFormatter = MaskTextInputFormatter(
    mask: '+998 (##) ### ## ##',
    filter: {"#": RegExp(r'[0-9]')},
  );

  static final plusPhoneFormatter = MaskTextInputFormatter(
    mask: '+### ## ### ## ##',
    filter: {"#": RegExp(r'\d')},
  );

  static final numberOnlyFormatter = FilteringTextInputFormatter.digitsOnly;
}

class AtSignUsernameFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;

    if (!text.startsWith('@')) {
      text = '@${text.replaceAll('@', '')}';
    }

    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class PriceFormatter extends TextInputFormatter {
  final String additional;
  final int? limit;

  PriceFormatter({this.additional = '', this.limit});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    int number = int.parse(text);

    if (additional == '%' && number > 100) {
      number = 100;
    }

    if (limit != null && number > limit!) {
      number = limit!;
    }

    final formatted = number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]} ',
    );

    return TextEditingValue(
      text: "$formatted $additional",
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
