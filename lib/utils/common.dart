/// Args:
///   name: The name (String) to be converted.
///
/// Returns:
///   The converted ID (String).
String generateId(String name) {
  // Replace all non-alphanumeric characters with a space and lowercase.
  // Dart RegExp: [^a-zA-Z0-9] matches anything NOT a letter or number.
  // The global case-insensitive flag 'i' is often implicit in Dart String methods,
  // but here we use toLowerCase() after the substitution for certainty.
  final RegExp nonAlphanumeric = RegExp(r"[^a-zA-Z0-9]");
  String part1 = name.replaceAll(nonAlphanumeric, " ").toLowerCase();

  // 3 & 4: Collapse multiple spaces (" +") into a single space (" "), then trim.
  // Dart RegExp: " +" matches one or more spaces.
  final RegExp multipleSpaces = RegExp(r" +");
  String result = part1.replaceAll(multipleSpaces, " ").trim();

  // 5. Replace spaces with hyphens ("-").
  result = result.replaceAll(" ", "-");

  // 6. Handle the empty string case.
  if (result.isEmpty) {
    result = "default";
  }

  return result;
}
