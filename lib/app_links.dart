const publicWebOrigin = 'https://earplug.app';
const publicWebHost = 'earplug.app';

String publicWebUrl(String path) =>
    '$publicWebOrigin/${_trimLeadingSlash(path)}';

String publicWebDisplayUrl(String path) =>
    '$publicWebHost/${_trimLeadingSlash(path)}';

String _trimLeadingSlash(String path) =>
    path.startsWith('/') ? path.substring(1) : path;
