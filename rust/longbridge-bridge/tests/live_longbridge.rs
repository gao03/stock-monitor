use std::{
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    process::{Child, ChildStdin, Command, Stdio},
    sync::mpsc::{self, Receiver},
    thread,
    time::{Duration, Instant},
};

use anyhow::{anyhow, bail, Context, Result};
use serde_json::{json, Value};

#[test]
#[ignore = "requires a real Longbridge OAuth client and network access"]
fn live_oauth_subscribe_snapshot_and_unsubscribe() -> Result<()> {
    let client_id = std::env::var("LONGBRIDGE_LIVE_CLIENT_ID")
        .context("set LONGBRIDGE_LIVE_CLIENT_ID to a registered Longbridge OAuth client_id")?;
    let symbol = std::env::var("LONGBRIDGE_LIVE_SYMBOL").unwrap_or_else(|_| "AAPL.US".to_string());
    let region = std::env::var("LONGBRIDGE_LIVE_REGION").unwrap_or_else(|_| "auto".to_string());
    let callback_port = std::env::var("LONGBRIDGE_LIVE_CALLBACK_PORT")
        .ok()
        .and_then(|value| value.parse::<u16>().ok())
        .unwrap_or(60355);
    let auth_timeout = std::env::var("LONGBRIDGE_LIVE_AUTH_TIMEOUT_SECS")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(180);
    let force_reauthorize = env_flag("LONGBRIDGE_LIVE_FORCE_REAUTHORIZE");

    let mut bridge = BridgeProcess::spawn()?;
    let auth_method = if force_reauthorize {
        "auth.reauthorize"
    } else {
        "auth.configure"
    };
    let auth_id = bridge.send(
        auth_method,
        json!({
            "client_id": client_id,
            "callback_port": callback_port,
            "region": region,
            "language": "zh-CN",
            "enable_overnight": true,
            "oauth_timeout_secs": auth_timeout
        }),
    )?;
    bridge.wait_for_response(&auth_id, Duration::from_secs(auth_timeout))?;

    let normalized_symbol = symbol.trim().to_uppercase();
    let subscribe_id = bridge.send(
        "quote.subscribe",
        json!({
            "symbols": [normalized_symbol]
        }),
    )?;
    let subscribe_result = bridge.wait_for_response(&subscribe_id, Duration::from_secs(30))?;
    assert_symbols_contain(&subscribe_result, &normalized_symbol)?;

    let subscriptions_id = bridge.send("quote.subscriptions", json!({}))?;
    let subscriptions_result =
        bridge.wait_for_response(&subscriptions_id, Duration::from_secs(10))?;
    assert_symbols_contain(&subscriptions_result, &normalized_symbol)?;

    let snapshot_id = bridge.send(
        "quote.snapshot",
        json!({
            "symbols": [normalized_symbol]
        }),
    )?;
    let snapshot_result = bridge.wait_for_response(&snapshot_id, Duration::from_secs(30))?;
    assert_snapshot_contains_price(&snapshot_result, &normalized_symbol)?;

    let unsubscribe_id = bridge.send(
        "quote.unsubscribe",
        json!({
            "symbols": [normalized_symbol]
        }),
    )?;
    let unsubscribe_result = bridge.wait_for_response(&unsubscribe_id, Duration::from_secs(30))?;
    assert_symbols_not_contain(&unsubscribe_result, &normalized_symbol)?;

    Ok(())
}

struct BridgeProcess {
    child: Child,
    stdin: ChildStdin,
    rx: Receiver<Value>,
    next_id: u64,
    opened_auth_url: bool,
}

impl BridgeProcess {
    fn spawn() -> Result<Self> {
        let mut child = Command::new(bridge_executable()?)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("spawn longbridge bridge")?;

        let stdin = child
            .stdin
            .take()
            .context("bridge stdin is not available")?;
        let stdout = child
            .stdout
            .take()
            .context("bridge stdout is not available")?;
        let stderr = child
            .stderr
            .take()
            .context("bridge stderr is not available")?;
        let (tx, rx) = mpsc::channel();

        thread::spawn(move || {
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                match line {
                    Ok(line) if line.trim().is_empty() => {}
                    Ok(line) => match serde_json::from_str::<Value>(&line) {
                        Ok(value) => {
                            if tx.send(value).is_err() {
                                break;
                            }
                        }
                        Err(error) => eprintln!("[bridge stdout parse error] {error}: {line}"),
                    },
                    Err(error) => {
                        eprintln!("[bridge stdout read error] {error}");
                        break;
                    }
                }
            }
        });

        thread::spawn(move || {
            let reader = BufReader::new(stderr);
            for line in reader.lines().map_while(Result::ok) {
                if !line.trim().is_empty() {
                    eprintln!("[bridge stderr] {line}");
                }
            }
        });

        Ok(Self {
            child,
            stdin,
            rx,
            next_id: 1,
            opened_auth_url: false,
        })
    }

    fn send(&mut self, method: &str, params: Value) -> Result<String> {
        let id = format!("live-test-{}", self.next_id);
        self.next_id += 1;
        let command = json!({
            "id": id,
            "method": method,
            "params": params
        });
        serde_json::to_writer(&mut self.stdin, &command)?;
        self.stdin.write_all(b"\n")?;
        self.stdin.flush()?;
        Ok(id)
    }

    fn wait_for_response(&mut self, id: &str, timeout: Duration) -> Result<Value> {
        let deadline = Instant::now() + timeout;
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                bail!("timed out waiting for bridge response {id}");
            }

            let message = self
                .rx
                .recv_timeout(remaining)
                .with_context(|| format!("bridge stopped before response {id}"))?;

            if let Some(event) = message.get("event").and_then(Value::as_str) {
                self.handle_event(event, &message)?;
                continue;
            }

            if message.get("id").and_then(Value::as_str) != Some(id) {
                continue;
            }

            if message.get("ok").and_then(Value::as_bool) == Some(true) {
                return Ok(message.get("result").cloned().unwrap_or_else(|| json!({})));
            }

            bail!(
                "bridge request {id} failed: {}",
                message
                    .get("error")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown error")
            );
        }
    }

    fn handle_event(&mut self, event: &str, message: &Value) -> Result<()> {
        match event {
            "started" | "ready" | "sdk.push" | "quote" => Ok(()),
            "oauth.authorize" => {
                let url = message
                    .pointer("/data/url")
                    .and_then(Value::as_str)
                    .ok_or_else(|| anyhow!("oauth.authorize event missing data.url"))?;
                eprintln!("[longbridge oauth] authorize URL: {url}");
                eprintln!(
                    "[longbridge oauth] open it in a browser, finish authorization, then wait for the local callback"
                );

                if env_flag("LONGBRIDGE_LIVE_OPEN_BROWSER") && !self.opened_auth_url {
                    self.opened_auth_url = true;
                    let status = Command::new("open")
                        .arg(url)
                        .status()
                        .context("open OAuth URL")?;
                    if !status.success() {
                        bail!("failed to open OAuth URL with macOS open");
                    }
                }
                Ok(())
            }
            "error" => {
                let message = message
                    .pointer("/data/message")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown bridge error");
                bail!("bridge emitted error event: {message}")
            }
            _ => Ok(()),
        }
    }
}

impl Drop for BridgeProcess {
    fn drop(&mut self) {
        let _ = self.send("shutdown", json!({}));
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn assert_symbols_contain(result: &Value, symbol: &str) -> Result<()> {
    let symbols = result
        .get("symbols")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("result does not contain symbols array: {result}"))?;
    if symbols.iter().any(|item| item.as_str() == Some(symbol)) {
        Ok(())
    } else {
        bail!("subscriptions did not contain {symbol}: {result}")
    }
}

fn assert_symbols_not_contain(result: &Value, symbol: &str) -> Result<()> {
    let symbols = result
        .get("symbols")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("result does not contain symbols array: {result}"))?;
    if symbols.iter().any(|item| item.as_str() == Some(symbol)) {
        bail!("subscriptions still contained {symbol}: {result}")
    } else {
        Ok(())
    }
}

fn assert_snapshot_contains_price(result: &Value, symbol: &str) -> Result<()> {
    let quotes = result
        .get("quotes")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("snapshot result does not contain quotes array: {result}"))?;
    let quote = quotes
        .iter()
        .find(|quote| quote.get("symbol").and_then(Value::as_str) == Some(symbol))
        .ok_or_else(|| anyhow!("snapshot did not contain {symbol}: {result}"))?;
    let last_done = quote
        .get("last_done")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("snapshot quote missing last_done: {quote}"))?;
    let price = last_done
        .parse::<f64>()
        .with_context(|| format!("last_done is not numeric: {last_done}"))?;
    if price > 0.0 {
        Ok(())
    } else {
        bail!("snapshot price must be positive for {symbol}: {quote}")
    }
}

fn bridge_executable() -> Result<PathBuf> {
    if let Some(path) = option_env!("CARGO_BIN_EXE_longbridge-bridge") {
        return Ok(PathBuf::from(path));
    }

    let mut path = std::env::current_exe().context("current test executable path")?;
    path.pop();
    if path.ends_with("deps") {
        path.pop();
    }
    path.push(format!("longbridge-bridge{}", std::env::consts::EXE_SUFFIX));
    Ok(path)
}

fn env_flag(name: &str) -> bool {
    std::env::var(name)
        .map(|value| {
            let value = value.trim();
            value == "1" || value.eq_ignore_ascii_case("true") || value.eq_ignore_ascii_case("yes")
        })
        .unwrap_or(false)
}
