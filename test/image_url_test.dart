import 'package:earplug/services/image_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('displayImageUrl', () {
    const convexUrl =
        'https://my-deployment-123.convex.cloud/api/storage/abc-def';

    test('rewrites Convex storage URLs on earplug.dev', () {
      final result = displayImageUrl(
        convexUrl,
        width: 320,
        base: Uri.parse('https://earplug.dev/'),
      );
      final uri = Uri.parse(result);

      expect(uri.origin, 'https://earplug.dev');
      expect(uri.path, '/.netlify/images');
      expect(uri.queryParameters['url'], convexUrl);
      expect(uri.queryParameters['w'], '320');
      expect(uri.queryParameters['fit'], 'cover');
      expect(uri.queryParameters['q'], '75');
      expect(result, contains('url=${Uri.encodeQueryComponent(convexUrl)}'));
    });

    test('rewrites Convex storage URLs on Netlify deploy previews', () {
      final result = displayImageUrl(
        convexUrl,
        width: 200,
        base: Uri.parse('https://deploy-preview-7--earplug.netlify.app/'),
      );
      final uri = Uri.parse(result);

      expect(uri.host, 'deploy-preview-7--earplug.netlify.app');
      expect(uri.path, '/.netlify/images');
      expect(uri.queryParameters['url'], convexUrl);
    });

    test('leaves Convex storage URLs unchanged on localhost', () {
      expect(
        displayImageUrl(
          convexUrl,
          width: 320,
          base: Uri.parse('http://localhost:8080/'),
        ),
        convexUrl,
      );
    });

    test('leaves non-storage URLs unchanged', () {
      final base = Uri.parse('https://earplug.dev/');
      const otherCdnUrl = 'https://images.example.com/flyer.jpg';
      const otherConvexPath =
          'https://my-deployment-123.convex.cloud/api/query/abc-def';

      expect(displayImageUrl(otherCdnUrl, width: 320, base: base), otherCdnUrl);
      expect(
        displayImageUrl(otherConvexPath, width: 320, base: base),
        otherConvexPath,
      );
      expect(displayImageUrl('not a URL', width: 320, base: base), 'not a URL');
    });

    test('caps device pixel ratio at two', () {
      final uri = Uri.parse(
        displayImageUrl(
          convexUrl,
          width: 100,
          base: Uri.parse('https://earplug.dev/'),
          devicePixelRatio: 3,
        ),
      );

      expect(uri.queryParameters['w'], '200');
    });

    test('includes a scaled height when provided', () {
      final uri = Uri.parse(
        displayImageUrl(
          convexUrl,
          width: 100,
          height: 75,
          base: Uri.parse('https://earplug.dev/'),
          devicePixelRatio: 1.5,
        ),
      );

      expect(uri.queryParameters['w'], '150');
      expect(uri.queryParameters['h'], '113');
    });
  });
}
