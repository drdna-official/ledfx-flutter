import 'dart:io';

void main() {
  final file = File('src/libsamplerate/src/fastest_coeffs.h');
  final content = file.readAsStringSync();
  
  // Regex to find the coefficients array content
  final regExp = RegExp(r'fastest_coeffs\s*=\s*\{[^,]+,\s*\{([^}]+)\}', dotAll: true);
  final match = regExp.firstMatch(content);
  
  if (match == null) {
      print('Error: Could not find coefficient array in fastest_coeffs.h');
      return;
  }

  final numsStr = match.group(1)!;
  final nums = numsStr
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty && !e.startsWith('/*'))
      .toList();
  
  final out = File('lib/dsp/sinc_fastest_coeffs.dart');
  final outContent = '''
import 'dart:typed_data';

const int sincFastestIncrement = 128;
final Float32List sincFastestCoeffs = Float32List.fromList(const [
  ${nums.join(',\n  ')}
]);
''';
  out.writeAsStringSync(outContent);
  print('Generated lib/dsp/sinc_fastest_coeffs.dart with ${nums.length} coefficients.');
}
