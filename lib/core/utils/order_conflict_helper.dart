/// Backend `POST /api/v1/orders` 409 qaytarsa, javob matni
/// ("... allaqachon faol buyurtmaga ega: uuid") ichidan mavjud
/// buyurtma id'sini ajratib oladi. Topilmasa — null.
String? extractExistingOrderIdFromConflict(String? rawMessage) {
  if (rawMessage == null || rawMessage.isEmpty) return null;
  final uuidMatch = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  ).firstMatch(rawMessage);
  return uuidMatch?.group(0);
}
