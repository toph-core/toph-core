import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// XPRINTER_SETUP.md: a printer that is "80mm class" can still wrap at 32
/// characters (58mm template). The width is chosen per printer and stored on
/// this device (the backend has no column for it), then carried into the
/// `PrinterConfig` the receipt builders render against.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PrinterConfigStorage> freshStorage() async {
    SharedPreferences.setMockInitialValues({});
    return PrinterConfigStorage(await SharedPreferences.getInstance());
  }

  group('paper-size code mapping', () {
    test('unknown / null falls back to 80mm (unchanged behaviour)', () {
      expect(paperSizeFromCode(null), PaperSize.mm80);
      expect(paperSizeFromCode(''), PaperSize.mm80);
      expect(paperSizeFromCode('nonsense'), PaperSize.mm80);
      expect(paperSizeFromCode(kPaperSizeCode80), PaperSize.mm80);
    });

    test('mm58 maps to the 32-char template', () {
      expect(paperSizeFromCode(kPaperSizeCode58), PaperSize.mm58);
    });

    test('round-trips through toCode', () {
      expect(paperSizeToCode(PaperSize.mm58), kPaperSizeCode58);
      expect(paperSizeToCode(PaperSize.mm80), kPaperSizeCode80);
    });
  });

  group('PrinterConfigStorage paper size', () {
    test('defaults to 80mm when nothing is saved', () async {
      final storage = await freshStorage();
      expect(storage.getPaperSizeCode('entry-1'), isNull);
      expect(storage.getPaperSize('entry-1'), PaperSize.mm80);
    });

    test('saves, reads back, and clears', () async {
      final storage = await freshStorage();
      await storage.savePaperSizeCode('entry-1', kPaperSizeCode58);
      expect(storage.getPaperSize('entry-1'), PaperSize.mm58);
      // A different entry is untouched.
      expect(storage.getPaperSize('entry-2'), PaperSize.mm80);

      await storage.removePaperSize('entry-1');
      expect(storage.getPaperSizeCode('entry-1'), isNull);
      expect(storage.getPaperSize('entry-1'), PaperSize.mm80);
    });

    test('persists across a new storage instance over the same prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await PrinterConfigStorage(prefs).savePaperSizeCode('e', kPaperSizeCode58);
      // A fresh instance (e.g. next launch) still sees it — it is not lost on
      // the login re-sync the way an entry-list field would be.
      expect(PrinterConfigStorage(prefs).getPaperSize('e'), PaperSize.mm58);
    });
  });

  group('resolved PrinterConfig carries the width', () {
    test('close-check printer picks up the saved 58mm width', () async {
      final storage = await freshStorage();
      await storage.applyPrinterSettingsList(const [
        PrinterSettingEntry(
          id: 'cc-1',
          ip: '192.168.1.50',
          port: 9100,
          type: 'close_check',
          connectedEntityIds: [],
        ),
      ]);
      await storage.savePaperSizeCode('cc-1', kPaperSizeCode58);

      final config = storage.getCloseCheckPrinter();
      expect(config, isNotNull);
      expect(config!.paperSize, PaperSize.mm58);
      expect(config.entryId, 'cc-1');
    });

    test('category printer defaults to 80mm without a saved width', () async {
      final storage = await freshStorage();
      await storage.applyPrinterSettingsList(const [
        PrinterSettingEntry(
          id: 'cat-1',
          ip: '192.168.1.60',
          port: 9100,
          type: 'category',
          connectedEntityIds: ['cat-food'],
        ),
      ]);

      final config = storage.categoryPrinterForOrNull('cat-food');
      expect(config, isNotNull);
      expect(config!.paperSize, PaperSize.mm80);
    });
  });
}
