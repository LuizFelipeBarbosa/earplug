typedef BrowserBackHandler = void Function();

void pushBrowserPath(String path) {}

void replaceBrowserPath(String path) {}

bool requestBrowserBack() => false;

void Function() listenForBrowserBack(BrowserBackHandler handler) => () {};
