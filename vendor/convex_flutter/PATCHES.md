# Local patches vs convex_flutter 3.0.1 (pub.dev)

This is a vendored copy of convex_flutter 3.0.1 with fixes to the pure-Dart web
client (`lib/src/impl/convex_client_web.dart`). Native (Rust FFI) paths untouched.

1. **Surface server QueryFailed errors** (from the pre-adoption spike): the web
   client dropped `QueryFailed` modifications in `_handleTransition`, so failing
   queries timed out instead of erroring. Now forwarded to `onError`.

2. **Authenticate message shape**: the client sent `{type: 'Authenticate',
   token}` — the sync protocol requires `{type, baseVersion, tokenType:
   'User'|'None', value?}`. The server rejected the old shape with
   `missing field 'baseVersion'` and closed the socket. Added per-connection
   identity-version tracking; clearing auth now sends `tokenType: 'None'`
   instead of an empty User token.

3. **Real token refresh in `setAuthWithRefresh`** (was a TODO): stores the
   fetcher, decodes the JWT `exp`, refreshes 60s before expiry, and re-fetches
   a fresh token after every reconnect.

4. **Subscription replay on reconnect**: subscriptions now retain
   `udfPath`/`args` and are re-added in one `ModifyQuerySet` after the Connect
   handshake; previously every disconnect silently killed all live queries.
