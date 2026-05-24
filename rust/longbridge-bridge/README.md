# Longbridge Bridge

Internal sidecar process for StockMonitorNative.

The Swift app talks to this process through newline-delimited JSON on stdin/stdout.
Longbridge authentication and token refresh stay inside the official Rust SDK.

## Build

```bash
cargo build --manifest-path rust/longbridge-bridge/Cargo.toml
```

The app looks for the development binary at:

```text
rust/longbridge-bridge/target/debug/longbridge-bridge
```

You can override the lookup path while developing:

```bash
export STOCK_MONITOR_LONGBRIDGE_BRIDGE=/absolute/path/to/longbridge-bridge
```

For a packaged app, copy the binary into the app bundle next to the main executable
or into `Contents/Resources`.

## Live Test

The live integration test starts the bridge process, completes OAuth
configuration, subscribes to one symbol, fetches a quote snapshot, and
unsubscribes. It is ignored by default because it needs a real registered OAuth
client, network access, and a local callback.

```bash
LONGBRIDGE_LIVE_CLIENT_ID=your-client-id \
cargo test --manifest-path rust/longbridge-bridge/Cargo.toml --test live_longbridge -- --ignored --nocapture
```

Optional variables:

```bash
LONGBRIDGE_LIVE_SYMBOL=AAPL.US
LONGBRIDGE_LIVE_REGION=auto
LONGBRIDGE_LIVE_CALLBACK_PORT=60355
LONGBRIDGE_LIVE_AUTH_TIMEOUT_SECS=180
LONGBRIDGE_LIVE_FORCE_REAUTHORIZE=1
LONGBRIDGE_LIVE_OPEN_BROWSER=1
```

When `LONGBRIDGE_LIVE_FORCE_REAUTHORIZE=1` is set, the test ignores the cached
token and forces the OAuth browser flow. Run with `--nocapture` so the authorize
URL is visible.

## Protocol

Requests:

```json
{"id":"...","method":"auth.configure","params":{"client_id":"...","callback_port":60355,"region":"auto","language":"zh-CN","enable_overnight":false,"oauth_timeout_secs":180}}
{"id":"...","method":"auth.reauthorize","params":{"client_id":"...","callback_port":60355,"region":"auto","language":"zh-CN","enable_overnight":false,"oauth_timeout_secs":180}}
{"id":"...","method":"quote.subscribe","params":{"symbols":["AAPL.US"]}}
{"id":"...","method":"quote.unsubscribe","params":{"symbols":["AAPL.US"]}}
{"id":"...","method":"quote.snapshot","params":{"symbols":["AAPL.US"]}}
{"id":"...","method":"quote.subscriptions","params":{}}
{"id":"...","method":"shutdown","params":{}}
```

Responses:

```json
{"id":"...","ok":true,"result":{}}
{"id":"...","ok":false,"error":"..."}
```

Events:

```json
{"event":"oauth.authorize","data":{"url":"https://..."}}
{"event":"ready","data":{}}
{"event":"quote","data":{"symbol":"AAPL.US","last_done":"309.25","open":"306.00","high":"311.40","low":"304.80","timestamp":1770000000,"trade_session":"Normal"}}
```

Snapshot quote payloads include `prev_close` and may include
`pre_market_quote`, `post_market_quote`, or `over_night_quote`; streaming push
payloads do not currently include `prev_close`.
