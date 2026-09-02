/// Proxies Convex-hosted files through Netlify's Image CDN for web callers so
/// images are resized before they are downloaded and decoded.
String displayImageUrl(
  String url, {
  required int width,
  int? height,
  required Uri base,
  double devicePixelRatio = 1,
}) {
  final imageUri = Uri.tryParse(url);
  if (imageUri == null ||
      !imageUri.isAbsolute ||
      imageUri.host.isEmpty ||
      !imageUri.host.toLowerCase().endsWith('.convex.cloud') ||
      !imageUri.path.startsWith('/api/storage/')) {
    return url;
  }

  final baseHost = base.host.toLowerCase();
  if (!baseHost.endsWith('earplug.dev') && !baseHost.endsWith('netlify.app')) {
    return url;
  }

  final dpr = devicePixelRatio.clamp(1, 2);
  final queryParameters = <String, String>{
    'url': url,
    'w': (width * dpr).round().toString(),
    if (height != null) 'h': (height * dpr).round().toString(),
    'fit': 'cover',
    'q': '75',
  };
  return base
      .resolveUri(
        Uri(path: '/.netlify/images', queryParameters: queryParameters),
      )
      .toString();
}
