import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/site/server_url.dart';

void main() {
  test('the server address loses a pasted API path and trailing slashes', () {
    const origin = 'https://abc.supabase.co';
    expect(supabaseOrigin(origin), origin);
    expect(supabaseOrigin('$origin/'), origin);
    expect(supabaseOrigin('$origin/rest/v1'), origin);
    expect(supabaseOrigin('$origin/rest/v1/'), origin);
    expect(supabaseOrigin(' $origin/auth/v1 '), origin);
    expect(supabaseOrigin(''), '');
  });
}
