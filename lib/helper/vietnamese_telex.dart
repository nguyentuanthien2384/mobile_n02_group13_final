import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bật/tắt gõ tiếng Việt (Telex) toàn cục. Cho phép người dùng chuyển sang gõ
/// tiếng Anh khi cần (tránh việc "oo" bị biến thành "ô"...).
final ValueNotifier<bool> vietnameseInputEnabled = ValueNotifier<bool>(true);

class _Vowel {
  final String base; // a, e, i, o, u, y
  final int mark; // 0 không, 1 mũ (â/ê/ô), 2 á»­ (ă), 3 móc (ơ/ư)
  final int tone; // 0..5: không, sắc, huyền, hỏi, ngã, nặng
  const _Vowel(this.base, this.mark, this.tone);
}

// Mỗi nhóm: [chuỗi 6 dấu thanh, nguyên âm gốc, loại dấu mũ/á»­/móc]
const List<List<dynamic>> _groups = [
  ['aáàảãạ', 'a', 0],
  ['ăắằẳẵặ', 'a', 2],
  ['âấầẩẫậ', 'a', 1],
  ['eéèẻẽẹ', 'e', 0],
  ['êếềểễệ', 'e', 1],
  ['iíìỉĩị', 'i', 0],
  ['oóòỏõọ', 'o', 0],
  ['ôốồổỗộ', 'o', 1],
  ['ơớờởỡợ', 'o', 3],
  ['uúùủũụ', 'u', 0],
  ['ưứừửữự', 'u', 3],
  ['yýỳỷỹỵ', 'y', 0],
];

final Map<String, _Vowel> _decomp = {};
final Map<String, String> _compose = {};
bool _inited = false;

void _init() {
  if (_inited) return;
  for (final g in _groups) {
    final chars = g[0] as String;
    final base = g[1] as String;
    final mark = g[2] as int;
    for (int t = 0; t < chars.length; t++) {
      _decomp[chars[t]] = _Vowel(base, mark, t);
      _compose['$base|$mark|$t'] = chars[t];
    }
  }
  _inited = true;
}

bool _isLetter(String c) => c.toLowerCase() != c.toUpperCase();

String _make(String base, int mark, int tone, bool upper) {
  final s = _compose['$base|$mark|$tone'] ?? base;
  return upper ? s.toUpperCase() : s;
}

int _toneOf(String key) {
  switch (key) {
    case 's':
      return 1;
    case 'f':
      return 2;
    case 'r':
      return 3;
    case 'x':
      return 4;
    case 'j':
      return 5;
    default:
      return 0; // z
  }
}

int _wordStart(List<String> out) {
  int i = out.length;
  while (i > 0 && _isLetter(out[i - 1])) {
    i--;
  }
  return i;
}

bool _tryTone(List<String> out, String key) {
  final start = _wordStart(out);
  if (start >= out.length) return false;
  final end = out.length;

  // Tách phụ âm cuối
  int ce = end;
  while (ce > start && _decomp[out[ce - 1].toLowerCase()] == null) {
    ce--;
  }
  final hasFinal = ce < end;
  // Cụm nguyên âm cuối
  int vs = ce;
  while (vs > start && _decomp[out[vs - 1].toLowerCase()] != null) {
    vs--;
  }
  if (vs >= ce) return false; // không có nguyên âm

  int target = -1;
  for (int i = vs; i < ce; i++) {
    if (_decomp[out[i].toLowerCase()]!.mark != 0) target = i;
  }
  if (target == -1) {
    final len = ce - vs;
    if (len == 1) {
      target = vs;
    } else if (len >= 3) {
      target = vs + 1;
    } else {
      // len == 2
      final cluster = (out[vs] + out[vs + 1]).toLowerCase();
      if (hasFinal || cluster == 'oa' || cluster == 'oe' || cluster == 'uy') {
        target = ce - 1;
      } else {
        target = vs;
      }
    }
  }

  final ch = out[target];
  final upper = ch != ch.toLowerCase();
  final v = _decomp[ch.toLowerCase()]!;
  final newTone = _toneOf(key);

  if (key == 'z') {
    if (v.tone == 0) return false;
    out[target] = _make(v.base, v.mark, 0, upper);
    return true;
  }
  if (v.tone == newTone) {
    // gõ lại đúng dấu đang có -> bỏ dấu và chèn phím thường (thoát)
    out[target] = _make(v.base, v.mark, 0, upper);
    return false;
  }
  out[target] = _make(v.base, v.mark, newTone, upper);
  return true;
}

bool _tryW(List<String> out, bool upper) {
  if (out.isNotEmpty) {
    final prev = out.last;
    final v = _decomp[prev.toLowerCase()];
    if (v != null) {
      final pUpper = prev != prev.toLowerCase();
      if (v.base == 'a' && v.mark == 0) {
        out[out.length - 1] = _make('a', 2, v.tone, pUpper);
        return true;
      }
      if (v.base == 'o' && v.mark == 0) {
        out[out.length - 1] = _make('o', 3, v.tone, pUpper);
        return true;
      }
      if (v.base == 'u' && v.mark == 0) {
        out[out.length - 1] = _make('u', 3, v.tone, pUpper);
        return true;
      }
      if ((v.base == 'a' && v.mark == 2) ||
          (v.base == 'o' && v.mark == 3) ||
          (v.base == 'u' && v.mark == 3)) {
        out[out.length - 1] = _make(v.base, 0, v.tone, pUpper);
        return false; // thoát -> chèn 'w' thường
      }
    }
  }
  out.add(upper ? 'Ư' : 'ư');
  return true;
}

bool _tryCircumflex(List<String> out, String lower, bool upper) {
  if (out.isEmpty) return false;
  final prev = out.last;
  final v = _decomp[prev.toLowerCase()];
  if (v == null || v.base != lower) return false;
  final pUpper = prev != prev.toLowerCase();
  if (v.mark == 1) {
    // đang là dấu mũ -> thoát
    out[out.length - 1] = _make(v.base, 0, v.tone, pUpper);
    return false;
  }
  if (v.mark != 0) return false;
  out[out.length - 1] = _make(v.base, 1, v.tone, pUpper);
  return true;
}

bool _tryDd(List<String> out) {
  if (out.isEmpty) return false;
  final prev = out.last;
  final pl = prev.toLowerCase();
  final upper = prev != prev.toLowerCase();
  if (pl == 'd') {
    out[out.length - 1] = upper ? 'Đ' : 'đ';
    return true;
  }
  if (pl == 'đ') {
    out[out.length - 1] = upper ? 'D' : 'd';
    return false; // thoát -> "dd"
  }
  return false;
}

/// Chuyển chuỗi gõ kiểu Telex thành tiếng Việt có dấu.
String processTelex(String input) {
  _init();
  final out = <String>[];
  for (int i = 0; i < input.length; i++) {
    final ch = input[i];
    final lower = ch.toLowerCase();
    final upper = ch != lower;
    if ('sfrxjz'.contains(lower) && lower.length == 1 && _tryTone(out, lower)) {
      continue;
    }
    if (lower == 'w' && _tryW(out, upper)) continue;
    if ((lower == 'a' || lower == 'e' || lower == 'o') &&
        _tryCircumflex(out, lower, upper)) {
      continue;
    }
    if (lower == 'd' && _tryDd(out)) continue;
    out.add(ch);
  }
  return out.join();
}

/// TextInputFormatter áp dụng Telex khi người dùng gõ thêm ký tá»± á»Ÿ cuối.
class VietnameseTelexFormatter extends TextInputFormatter {
  const VietnameseTelexFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!vietnameseInputEnabled.value) return newValue;
    final sel = newValue.selection;
    // Chỉ xử lý khi con trỏ á»Ÿ cuối và văn bản đang dài thêm (gõ nối tiếp).
    if (!sel.isCollapsed || sel.baseOffset != newValue.text.length) {
      return newValue;
    }
    if (newValue.text.length <= oldValue.text.length) return newValue;
    final converted = processTelex(newValue.text);
    if (converted == newValue.text) return newValue;
    return TextEditingValue(
      text: converted,
      selection: TextSelection.collapsed(offset: converted.length),
    );
  }
}
