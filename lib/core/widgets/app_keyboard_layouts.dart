import 'package:virtual_keyboard_multi_language/virtual_keyboard_multi_language.dart';

/// POS klaviaturasi uchun ikki tilli layout: Lotin (index 0) va Rus kirilli
/// (index 1). Paket faqat Arab/Ingliz/Kurd layoutlarini beradi — kirill yo'q,
/// shuning uchun qatorlarni shu yerda o'zimiz aniqlaymiz.
///
/// Til almashtirish pastki qatordagi globus (`SwithLanguage`) tugmasi orqali
/// amalga oshiriladi — paketning o'zi bosilganda `switchLanguage()` chaqirib
/// `activeIndex` ni 0↔1 aylantiradi. Obyekt tashqarida `late final` sifatida
/// bir marta yaratilib, o'zgarmas saqlanadi (aks holda har rebuild'da
/// activeIndex 0 ga tushib, tanlangan til yo'qolardi).
class AppKeyboardLayoutKeys extends VirtualKeyboardLayoutKeys {
  AppKeyboardLayoutKeys({int initialIndex = 0}) {
    activeIndex = initialIndex;
  }

  @override
  int getLanguagesCount() => 2;

  @override
  List<List> getLanguage(int index) =>
      index == 1 ? _russianLayout : _latinLayout;
}

/// Lotin QWERTY. Row 2 oxirida Backspace, row 3 oxirida Return,
/// row 4 chetlarida Shift.
const List<List> _latinLayout = [
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
  [
    'q',
    'w',
    'e',
    'r',
    't',
    'y',
    'u',
    'i',
    'o',
    'p',
    VirtualKeyboardKeyAction.Backspace,
  ],
  [
    'a',
    's',
    'd',
    'f',
    'g',
    'h',
    'j',
    'k',
    'l',
    ';',
    '\'',
    VirtualKeyboardKeyAction.Return,
  ],
  [
    VirtualKeyboardKeyAction.Shift,
    'z',
    'x',
    'c',
    'v',
    'b',
    'n',
    'm',
    ',',
    '.',
    '/',
    VirtualKeyboardKeyAction.Shift,
  ],
  [
    VirtualKeyboardKeyAction.SwithLanguage,
    '@',
    ',',
    VirtualKeyboardKeyAction.Space,
    '.',
    '-',
    '_',
  ],
];

/// Ruscha ЙЦУКЕН layout (33 harf). Tuzilishi lotin layoutga mos.
const List<List> _russianLayout = [
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
  [
    'й',
    'ц',
    'у',
    'к',
    'е',
    'н',
    'г',
    'ш',
    'щ',
    'з',
    'х',
    'ъ',
    VirtualKeyboardKeyAction.Backspace,
  ],
  [
    'ф',
    'ы',
    'в',
    'а',
    'п',
    'р',
    'о',
    'л',
    'д',
    'ж',
    'э',
    VirtualKeyboardKeyAction.Return,
  ],
  [
    VirtualKeyboardKeyAction.Shift,
    'я',
    'ч',
    'с',
    'м',
    'и',
    'т',
    'ь',
    'б',
    'ю',
    'ё',
    VirtualKeyboardKeyAction.Shift,
  ],
  [
    VirtualKeyboardKeyAction.SwithLanguage,
    '@',
    ',',
    VirtualKeyboardKeyAction.Space,
    '.',
    '-',
    '_',
  ],
];
