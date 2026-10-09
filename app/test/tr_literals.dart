/// The string literals of a Dart source, for tr_coverage_test (122) — a
/// small tokenizer, not a parser: comments are skipped, raw and
/// triple-quoted strings read, adjacent literals ('a' 'b') joined, and an
/// interpolation (`$x`, `${…}` with quotes and braces inside) known for
/// what it is.
class Literal {
  Literal(this.line, this.before, this.text, this.interpolated);

  /// 1-based line of the literal's first quote.
  final int line;

  /// The 80 characters of code before the literal, spaces collapsed.
  final String before;

  /// The words of the literal, every interpolation replaced by a space.
  final String text;

  final bool interpolated;
}

List<Literal> literals(String src) => _Scanner(src).run();

class _Scanner {
  _Scanner(this.src);

  final String src;
  int get n => src.length;
  static final _ident = RegExp(r'[A-Za-z0-9_]');
  static final _identStart = RegExp(r'[A-Za-z_]');

  bool _isQuoteAt(int i) {
    final c = src[i];
    if (c == "'" || c == '"') return true;
    return c == 'r' &&
        i + 1 < n &&
        (src[i + 1] == "'" || src[i + 1] == '"') &&
        (i == 0 || !_ident.hasMatch(src[i - 1]));
  }

  /// Skips a comment at [i]; returns the index after it, or -1.
  int _comment(int i) {
    if (src.startsWith('//', i)) {
      final e = src.indexOf('\n', i);
      return e < 0 ? n : e;
    }
    if (src.startsWith('/*', i)) {
      final e = src.indexOf('*/', i + 2);
      return e < 0 ? n : e + 2;
    }
    return -1;
  }

  /// Reads the string at [at]; returns its end, its text in [buf].
  int _string(int at, StringBuffer buf, List<bool> interp) {
    var raw = false;
    if (src[at] == 'r') {
      raw = true;
      at++;
    }
    final q = src[at];
    final triple = at + 2 < n && src[at + 1] == q && src[at + 2] == q;
    final close = triple ? '$q$q$q' : q;
    at += triple ? 3 : 1;
    while (at < n) {
      if (src.startsWith(close, at)) return at + close.length;
      final c = src[at];
      if (!triple && c == '\n') return at;
      if (!raw && c == '\\') {
        buf.write(src.substring(at, at + 2 > n ? n : at + 2));
        at += 2;
        continue;
      }
      if (!raw && c == r'$' && at + 1 < n) {
        if (src[at + 1] == '{') {
          interp[0] = true;
          buf.write(' ');
          at = _code(at + 2);
          continue;
        }
        if (_identStart.hasMatch(src[at + 1])) {
          interp[0] = true;
          buf.write(' ');
          at++;
          while (at < n && _ident.hasMatch(src[at])) {
            at++;
          }
          continue;
        }
      }
      buf.write(c);
      at++;
    }
    return at;
  }

  /// Skips the code of an interpolation up to its closing brace.
  int _code(int at) {
    var depth = 0;
    while (at < n) {
      final skip = _comment(at);
      if (skip >= 0) {
        at = skip;
        continue;
      }
      if (_isQuoteAt(at)) {
        at = _string(at, StringBuffer(), [false]);
        continue;
      }
      final c = src[at];
      if (c == '{') depth++;
      if (c == '}') {
        if (depth == 0) return at + 1;
        depth--;
      }
      at++;
    }
    return at;
  }

  List<Literal> run() {
    final out = <Literal>[];
    var i = 0;
    var line = 1;
    var counted = 0;
    var lastEnd = -1;
    int lineOf(int at) {
      line += '\n'.allMatches(src.substring(counted, at)).length;
      counted = at;
      return line;
    }

    while (i < n) {
      final skip = _comment(i);
      if (skip >= 0) {
        i = skip;
        continue;
      }
      if (_isQuoteAt(i)) {
        final buf = StringBuffer();
        final interp = [false];
        final end = _string(i, buf, interp);
        final between = lastEnd >= 0 ? src.substring(lastEnd, i) : 'x';
        if (out.isNotEmpty && between.trim().isEmpty) {
          final prev = out.removeLast();
          out.add(Literal(prev.line, prev.before, prev.text + buf.toString(),
              prev.interpolated || interp[0]));
        } else {
          final start = i < 80 ? 0 : i - 80;
          out.add(Literal(lineOf(i), src.substring(start, i).replaceAll(RegExp(r'\s+'), ' ').trim(),
              buf.toString(), interp[0]));
        }
        i = end;
        lastEnd = end;
        continue;
      }
      i++;
    }
    return out;
  }
}
