/// Normalises Vietnamese text for a forgiving, accent-insensitive search.
String normaliseSearchText(String value) {
  const replacements = <String, String>{
    'àáạảãâầấậẩẫăằắặẳẵ': 'a',
    'èéẹẻẽêềếệểễ': 'e',
    'ìíịỉĩ': 'i',
    'òóọỏõôồốộổỗơờớợởỡ': 'o',
    'ùúụủũưừứựửữ': 'u',
    'ỳýỵỷỹ': 'y',
    'đ': 'd',
  };

  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    var replacement = char;
    for (final entry in replacements.entries) {
      if (entry.key.contains(char)) {
        replacement = entry.value;
        break;
      }
    }
    buffer.write(replacement);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Matches every typed word independently, so word order and Vietnamese
/// diacritics do not matter. A small typo in a longer word is accepted too.
bool matchesNoteSearch({
  required String query,
  String? title,
  String? content,
}) {
  final terms = normaliseSearchText(
    query,
  ).split(' ').where((term) => term.isNotEmpty).toList();
  if (terms.isEmpty) return true;

  final searchable = normaliseSearchText('${title ?? ''} ${content ?? ''}');
  if (searchable.isEmpty) return false;
  final words = searchable.split(' ');

  return terms.every((term) {
    if (searchable.contains(term)) return true;
    if (term.length < 4) return false;
    return words.any(
      (word) =>
          (word.length - term.length).abs() <= 1 &&
          _levenshteinDistance(word, term) <= 1,
    );
  });
}

int _levenshteinDistance(String first, String second) {
  var previous = List<int>.generate(second.length + 1, (index) => index);
  for (var i = 0; i < first.length; i++) {
    final current = <int>[i + 1];
    for (var j = 0; j < second.length; j++) {
      final cost = first[i] == second[j] ? 0 : 1;
      current.add(
        [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        ].reduce((a, b) => a < b ? a : b),
      );
    }
    previous = current;
  }
  return previous.last;
}
