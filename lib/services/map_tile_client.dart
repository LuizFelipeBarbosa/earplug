import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

const _mapTileRetryDelays = [
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 3),
  Duration(seconds: 4),
  Duration(seconds: 5),
];

http.Client createMapTileClient([
  http.Client? inner,
  Duration Function(int retryCount)? delay,
]) {
  return RetryClient(
    inner ?? http.Client(),
    retries: _mapTileRetryDelays.length,
    when: (response) =>
        response.statusCode == 503 || response.statusCode == 429,
    whenError: (_, _) => true,
    delay: delay ?? (retryCount) => _mapTileRetryDelays[retryCount],
  );
}
