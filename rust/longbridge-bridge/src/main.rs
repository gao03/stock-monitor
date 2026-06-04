use std::{collections::BTreeSet, env, io::Write, sync::Arc};

use anyhow::{anyhow, Context, Result};
use longbridge::{
    oauth::{FileTokenStorage, OAuthBuilder, OAuthResult, StoredToken, TokenStorage},
    quote::{
        PrePostQuote, PushEvent, PushEventDetail, PushQuote, PushTrades, QuoteContext,
        SecurityQuote, SubFlags,
    },
    Config,
};
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::{
    io::{self, AsyncBufReadExt, BufReader},
    sync::mpsc,
    task::JoinHandle,
    time::{timeout, Duration},
};

#[derive(Debug, Deserialize)]
struct Request {
    id: String,
    method: String,
    #[serde(default)]
    params: Value,
}

#[derive(Debug, Deserialize)]
struct ConfigureParams {
    client_id: String,
    #[serde(default = "default_callback_port")]
    callback_port: u16,
    #[serde(default)]
    region: LongbridgeRegion,
    #[serde(default = "default_language")]
    language: String,
    #[serde(default)]
    enable_overnight: bool,
    #[serde(default)]
    force_reauthorize: bool,
    #[serde(default = "default_oauth_timeout_secs")]
    oauth_timeout_secs: u64,
}

#[derive(Debug, Deserialize)]
struct SymbolsParams {
    symbols: Vec<String>,
}

#[derive(Debug, Clone, Copy, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
enum LongbridgeRegion {
    #[default]
    Auto,
    Cn,
    Hk,
}

impl LongbridgeRegion {
    fn environment_value(self) -> Option<&'static str> {
        match self {
            Self::Auto => None,
            Self::Cn => Some("cn"),
            Self::Hk => Some("hk"),
        }
    }
}

struct BridgeState {
    ctx: Option<QuoteContext>,
    receiver_task: Option<JoinHandle<()>>,
    subscribed_symbols: BTreeSet<String>,
}

impl BridgeState {
    fn new() -> Self {
        Self {
            ctx: None,
            receiver_task: None,
            subscribed_symbols: BTreeSet::new(),
        }
    }

    async fn configure(
        &mut self,
        params: ConfigureParams,
        tx: mpsc::UnboundedSender<Value>,
    ) -> Result<()> {
        if params.client_id.trim().is_empty() {
            return Err(anyhow!("client_id is required"));
        }

        apply_environment(&params);

        let auth_tx = tx.clone();
        let mut oauth_builder =
            OAuthBuilder::new(params.client_id.trim()).callback_port(params.callback_port);
        if params.force_reauthorize {
            oauth_builder = oauth_builder.token_storage(ReauthorizeTokenStorage);
        }

        let oauth = timeout(
            Duration::from_secs(params.oauth_timeout_secs.max(1)),
            oauth_builder.build(move |url| {
                let _ = auth_tx.send(json!({
                    "event": "oauth.authorize",
                    "data": {
                        "url": url.to_string()
                    }
                }));
            }),
        )
        .await
        .context("longbridge oauth timed out")?
        .context("longbridge oauth failed")?;

        let config = Arc::new(Config::from_oauth(oauth));
        let (ctx, mut receiver) = QuoteContext::new(config);
        if let Some(task) = self.receiver_task.take() {
            task.abort();
        }

        self.receiver_task = Some(tokio::spawn(async move {
            while let Some(event) = receiver.recv().await {
                if let Some(payload) = quote_payload_from_push_event(&event) {
                    let _ = tx.send(json!({
                        "event": "quote",
                        "data": payload
                    }));
                } else {
                    let _ = tx.send(json!({
                        "event": "sdk.push",
                        "data": {
                            "symbol": event.symbol,
                            "kind": push_event_kind(&event.detail)
                        }
                    }));
                }
            }
            let _ = tx.send(json!({
                "event": "error",
                "data": {
                    "message": "longbridge quote receiver stopped"
                }
            }));
        }));

        self.ctx = Some(ctx);
        self.subscribed_symbols.clear();
        Ok(())
    }

    async fn subscribe(&mut self, params: SymbolsParams) -> Result<()> {
        let ctx = self
            .ctx
            .as_ref()
            .ok_or_else(|| anyhow!("longbridge is not configured"))?;
        let symbols = clean_symbols(params.symbols);
        if symbols.is_empty() {
            return Ok(());
        }

        ctx.subscribe(symbols.iter().map(String::as_str), realtime_quote_flags())
            .await
            .context("longbridge subscribe failed")?;
        self.subscribed_symbols.extend(symbols);
        Ok(())
    }

    async fn unsubscribe(&mut self, params: SymbolsParams) -> Result<()> {
        let ctx = self
            .ctx
            .as_ref()
            .ok_or_else(|| anyhow!("longbridge is not configured"))?;
        let symbols = clean_symbols(params.symbols);
        if symbols.is_empty() {
            return Ok(());
        }

        ctx.unsubscribe(symbols.iter().map(String::as_str), realtime_quote_flags())
            .await
            .context("longbridge unsubscribe failed")?;
        for symbol in symbols {
            self.subscribed_symbols.remove(&symbol);
        }
        Ok(())
    }

    async fn snapshot(&self, params: SymbolsParams) -> Result<Value> {
        let ctx = self
            .ctx
            .as_ref()
            .ok_or_else(|| anyhow!("longbridge is not configured"))?;
        let symbols = clean_symbols(params.symbols);
        if symbols.is_empty() {
            return Ok(json!({ "quotes": [] }));
        }

        let quotes = ctx
            .quote(symbols)
            .await
            .context("longbridge quote snapshot failed")?;
        let items = quotes
            .iter()
            .map(quote_payload_from_security_quote)
            .collect::<Vec<_>>();
        Ok(json!({ "quotes": items }))
    }

    fn subscriptions(&self) -> Value {
        json!({
            "symbols": self.subscribed_symbols.iter().cloned().collect::<Vec<_>>()
        })
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let (out_tx, mut out_rx) = mpsc::unbounded_channel::<Value>();
    let writer = tokio::spawn(async move {
        while let Some(value) = out_rx.recv().await {
            if let Err(error) = write_json_line(value) {
                eprintln!("failed to write bridge output: {error:?}");
                break;
            }
        }
    });

    let _ = out_tx.send(json!({
        "event": "started",
        "data": {
            "protocol": 1
        }
    }));

    let stdin = BufReader::new(io::stdin());
    let mut lines = stdin.lines();
    let mut state = BridgeState::new();

    while let Some(line) = lines.next_line().await? {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        let request = match serde_json::from_str::<Request>(line) {
            Ok(request) => request,
            Err(error) => {
                let _ = out_tx.send(json!({
                    "event": "error",
                    "data": {
                        "message": format!("invalid request json: {error}")
                    }
                }));
                continue;
            }
        };

        let id = request.id.clone();
        let result = handle_request(&mut state, request, out_tx.clone()).await;
        match result {
            Ok(Some(value)) => {
                let _ = out_tx.send(json!({
                    "id": id,
                    "ok": true,
                    "result": value
                }));
            }
            Ok(None) => {
                let _ = out_tx.send(json!({
                    "id": id,
                    "ok": true,
                    "result": {}
                }));
            }
            Err(error) => {
                let _ = out_tx.send(json!({
                    "id": id,
                    "ok": false,
                    "error": error.to_string()
                }));
            }
        }
    }

    drop(out_tx);
    let _ = writer.await;
    Ok(())
}

async fn handle_request(
    state: &mut BridgeState,
    request: Request,
    tx: mpsc::UnboundedSender<Value>,
) -> Result<Option<Value>> {
    match request.method.as_str() {
        "auth.configure" => {
            let params: ConfigureParams = serde_json::from_value(request.params)?;
            state.configure(params, tx.clone()).await?;
            let _ = tx.send(json!({
                "event": "ready",
                "data": {}
            }));
            Ok(None)
        }
        "auth.reauthorize" => {
            let mut params: ConfigureParams = serde_json::from_value(request.params)?;
            params.force_reauthorize = true;
            state.configure(params, tx.clone()).await?;
            let _ = tx.send(json!({
                "event": "ready",
                "data": {}
            }));
            Ok(None)
        }
        "quote.subscribe" => {
            let params: SymbolsParams = serde_json::from_value(request.params)?;
            state.subscribe(params).await?;
            Ok(Some(state.subscriptions()))
        }
        "quote.unsubscribe" => {
            let params: SymbolsParams = serde_json::from_value(request.params)?;
            state.unsubscribe(params).await?;
            Ok(Some(state.subscriptions()))
        }
        "quote.snapshot" => {
            let params: SymbolsParams = serde_json::from_value(request.params)?;
            Ok(Some(state.snapshot(params).await?))
        }
        "quote.subscriptions" => Ok(Some(state.subscriptions())),
        "shutdown" => std::process::exit(0),
        other => Err(anyhow!("unsupported method: {other}")),
    }
}

struct ReauthorizeTokenStorage;

impl TokenStorage for ReauthorizeTokenStorage {
    fn load(&self, _client_id: &str) -> Option<StoredToken> {
        None
    }

    fn save(&self, token: &StoredToken) -> OAuthResult<()> {
        FileTokenStorage.save(token)
    }
}

fn apply_environment(params: &ConfigureParams) {
    env::set_var("LONGBRIDGE_LANGUAGE", params.language.trim());
    env::set_var(
        "LONGBRIDGE_ENABLE_OVERNIGHT",
        if params.enable_overnight {
            "true"
        } else {
            "false"
        },
    );

    match params.region.environment_value() {
        Some(region) => env::set_var("LONGBRIDGE_REGION", region),
        None => env::remove_var("LONGBRIDGE_REGION"),
    }

    env::set_var("LONGBRIDGE_PRINT_QUOTE_PACKAGES", "false");
}

fn default_callback_port() -> u16 {
    60355
}

fn default_language() -> String {
    "zh-CN".to_string()
}

fn default_oauth_timeout_secs() -> u64 {
    180
}

fn clean_symbols(symbols: Vec<String>) -> Vec<String> {
    symbols
        .into_iter()
        .map(|symbol| symbol.trim().to_uppercase())
        .filter(|symbol| !symbol.is_empty())
        .collect()
}

fn realtime_quote_flags() -> SubFlags {
    SubFlags::QUOTE | SubFlags::TRADE
}

fn write_json_line(value: Value) -> Result<()> {
    let mut stdout = std::io::stdout().lock();
    serde_json::to_writer(&mut stdout, &value)?;
    stdout.write_all(b"\n")?;
    stdout.flush()?;
    Ok(())
}

fn quote_payload_from_push_event(event: &PushEvent) -> Option<Value> {
    match &event.detail {
        PushEventDetail::Quote(quote) => Some(quote_payload_from_push_quote(&event.symbol, quote)),
        PushEventDetail::Trade(trades) => Some(quote_payload_from_push_trades(&event.symbol, trades)?),
        _ => None,
    }
}

fn quote_payload_from_push_quote(symbol: &str, quote: &PushQuote) -> Value {
    json!({
        "symbol": symbol,
        "last_done": quote.last_done.to_string(),
        "open": quote.open.to_string(),
        "high": quote.high.to_string(),
        "low": quote.low.to_string(),
        "timestamp": quote.timestamp.unix_timestamp(),
        "trade_session": format!("{:?}", quote.trade_session)
    })
}

fn quote_payload_from_push_trades(symbol: &str, trades: &PushTrades) -> Option<Value> {
    let trade = trades
        .trades
        .iter()
        .max_by_key(|trade| trade.timestamp.unix_timestamp())?;
    Some(json!({
        "symbol": symbol,
        "last_done": trade.price.to_string(),
        "timestamp": trade.timestamp.unix_timestamp(),
        "trade_session": format!("{:?}", trade.trade_session)
    }))
}

fn quote_payload_from_security_quote(quote: &SecurityQuote) -> Value {
    json!({
        "symbol": quote.symbol,
        "last_done": quote.last_done.to_string(),
        "prev_close": quote.prev_close.to_string(),
        "open": quote.open.to_string(),
        "high": quote.high.to_string(),
        "low": quote.low.to_string(),
        "timestamp": quote.timestamp.unix_timestamp(),
        "pre_market_quote": quote.pre_market_quote.as_ref().map(pre_post_quote_payload),
        "post_market_quote": quote.post_market_quote.as_ref().map(pre_post_quote_payload),
        "over_night_quote": quote.overnight_quote.as_ref().map(pre_post_quote_payload)
    })
}

fn pre_post_quote_payload(quote: &PrePostQuote) -> Value {
    json!({
        "last_done": quote.last_done.to_string(),
        "prev_close": quote.prev_close.to_string(),
        "high": quote.high.to_string(),
        "low": quote.low.to_string(),
        "timestamp": quote.timestamp.unix_timestamp()
    })
}

fn push_event_kind(detail: &PushEventDetail) -> &'static str {
    match detail {
        PushEventDetail::Quote(_) => "quote",
        PushEventDetail::Depth(_) => "depth",
        PushEventDetail::Brokers(_) => "brokers",
        PushEventDetail::Trade(_) => "trade",
        PushEventDetail::Candlestick(_) => "candlestick",
    }
}
