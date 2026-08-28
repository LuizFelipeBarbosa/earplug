const publicWebOrigin = 'https://earplug.dev';
const publicWebHost = 'earplug.dev';

String publicWebUrl(String path) =>
    '$publicWebOrigin/${_trimLeadingSlash(path)}';

String publicWebDisplayUrl(String path) =>
    '$publicWebHost/${_trimLeadingSlash(path)}';

String _trimLeadingSlash(String path) =>
    path.startsWith('/') ? path.substring(1) : path;
