import 'package:earplug/services/map_tile_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final url = Uri.parse('https://tiles.example.test/13/1310/3166@2x.png');

  test('retries 503 responses until a request succeeds', () async {
    var attempts = 0;
    final client = createMapTileClient(
      MockClient((request) async {
        expect(request.url, url);
        attempts++;
        return http.Response('', attempts < 3 ? 503 : 200);
      }),
      (_) => Duration.zero,
    );
    addTearDown(client.close);

    final response = await client.get(url);

    expect(response.statusCode, 200);
    expect(attempts, 3);
  });

  test('gives up after six retries and returns the final 503', () async {
    var attempts = 0;
    final client = createMapTileClient(
      MockClient((request) async {
        expect(request.url, url);
        attempts++;
        return http.Response('', 503);
      }),
      (_) => Duration.zero,
    );
    addTearDown(client.close);

    final response = await client.get(url);

    expect(response.statusCode, 503);
    expect(attempts, 7);
  });

  test('does not retry 404 responses', () async {
    var attempts = 0;
    final client = createMapTileClient(
      MockClient((request) async {
        expect(request.url, url);
        attempts++;
        return http.Response('', 404);
      }),
      (_) => Duration.zero,
    );
    addTearDown(client.close);

    final response = await client.get(url);

    expect(response.statusCode, 404);
    expect(attempts, 1);
  });
}
