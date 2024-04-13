# Nim Trading (Project NY Trading)

## Overview

This project is a simple exploration of using the [Alpaca Markets API](https://alpaca.markets/) to build a trading
system. The project focus is more around developing a wholistic understanding of the various moving components of
building a trading system, rather than on developing trading strategies.

**System Overview Website:** http://142.93.153.5:8080/
**Docs:** https://vabresto.github.io/nim-trading/


## Setup

To run a local version of this trading system, the only requirement is Docker, as there are pre-built images available
from [Github](https://github.com/vabresto/nim-trading). In order to do trading, an Alpaca API key will also be
required. Simply copy the [`docker-compose.yml`](./docker-compose.yml) and [`.env.example`](./.env.example) files,
rename `.env.example` to `.env`, edit the environment variables as necessary, and run `docker compose up`.

Lastly, connect to the postgres db and manually insert the following:

```sql
INSERT INTO ny.md_subscriptions (date, feed, symbol)
VALUES
  ('DATE', 'iex', 'SYMBOL1'),
  ('DATE', 'iex', 'SYMBOL2');

-- For example:
-- INSERT INTO ny.md_subscriptions (date, feed, symbol)
-- VALUES
--   ('2024-01-01', 'iex', 'AMD'),
--   ('2024-01-01', 'iex', 'MSFT');
```

Where `'DATE'` is a postgres-compatible date string for which the system should run in a non-simulated manner (ex. 
`2024-01-01`), `'iex'` is the data feed to register (can also be `sip` if using a premium Alpaca API key, or `test`
if trading against the `FAKEPACA` test symbol), and `'SYMBOL'` is the symbol the system should trade, for example,
`'AMD'` or `'MSFT'`. Multiple symbols can be added, and the system will trade all of them.

> **IMPORTANT NOTE:** This project is purely for educational purposes, and has never been tested with real money.


## Trading Strategy

The only strategy implemented so far is the `dummy` strategy, which is a very simple momentum based strategy. It will
attempt to enter into a position if it sees 3 minutes of consecutive growth. If it enters a position, it will try to
exit; first optimistically, then pessimistically. This process repeats until the end of the day, at which point the
strategy sends an MOC order to close out any held position so it can end the day flat.

One interesting aspect of this project is that it implements a "functional core, imperative shell" pattern, where the
trading strategy itself is statically enforced by the Nim compiler to be a pure-functional, side-effect-free message-
passing strategy.


## Market Data

This project uses the free market data provided by IEX via Alpaca. Consequently, it only has a small subset of all
actual market data, because only activity on IEX itself is available.

Paying Alpaca members should instead use the SIP data feed, as that provides complete market coverage. Another
possible market data provider to consider is [Polygon](https://polygon.io).

Lastly, note that for testing purposes, Alpca also provides a `test` feed with the `FAKEPACA` symbol. This is an
undocumented feature, but has the advantage of streaming fake market data even outside of market hours, which
is very useful for testing and development.


## Components

### EoD Tool

The [eod (ny-eod)](src/ny/apps/eod/main.nim) app runs at the end of the day, and is primarily responsible for managing
various post-trade tasks. In particular, it erases logged market and order update data in order to preserve disk
space, as well as computing some aggregated analytics stats.

It currently keeps 7 days of raw data in redis, and 30 days of raw market data in the postgres db.

Lastly, it propagates the current configuration of feeds and symbols to which the system should subscribe, so that once
configured, it can be left to run independently.

### MD Rec

The [market data recorder (ny-md-rec)](src/ny/apps/md_rec/main.nim) app is responsible for transcribing market data the
system receives to store it into the database. This can then be used for backtesting, running locally, analytics, and any
other desired uses.

### MD WS

The [market data websocket (ny-md-ws)](src/ny/apps/md_ws/main.nim) app is responsible for directly connecting to the
Alpaca Markets API and ingesting the market data received. It then forwards that data into a redis stream, which other
consumers can process. We do this because Alpaca limits us to one market data websocket connection per API key.

In a production system, we may prefer to convert the market data into an internal format before passing it on, however,
for this side project it makes more sense to store the raw market data so that we only need to implement handling for
the parts we care about, and ignore everything else until we have a need for it.

### Monitor

The [monitor (ny-monitor)](src/ny/apps/monitor/main.nim) app is the user interface for visibility into the system. All
of the other components are pinged by the monitor to provide simple overviews into the trading system. The paper
trading demo is running and accessible at http://142.93.153.5:8080/

It provides:
- visibility into currently running services
- info about historical system latency
- live and historical info about strategy trading performance

### OU Rec

The [order update recorder (ny-ou-rec)](src/ny/apps/ou_rec/main.nim) is similar to the [market data recorder](#md-rec)
except it records order updates instead of market data.

### OU WS

The [order update websocket (ny-ou-ws)](src/ny/apps/ou_ws/main.nim) is similar to the [market data ws](#md-ws) except
it connects to the Alpaca order updates websocket instead of the market data websocket. There are more meaningful
differences here as the order update websocket returns binary frames and has a slightly different protocol response
structure.

### Runner

The [runner (ny-runner)](src/ny/apps/runner/main.nim) is the process that actually does trading. It supports running
in both a `live` and `simulation` mode, and executes user-implemented (pure functional) strategies.

In live mode, it connects to a redis server for market data and order update streams.

In simulation mode, it implements a (very very very basic) exchange matching engine that interacts with the model's
orders.

> **IMPORTANT NOTE:** This project is purely for educational purposes, and has never been tested with real money.

### Redis

Redis is used for the real-time portion of the trading system, in particular for its streams feature which allow
multiple consumers to subscribe to the same data feed, and read from it as they wish. Streams were chosen over
pub-sub because streams store the data after receiving it, so if there is an issue with the recording process or
the trading process, recovery is possible and data is not lost.

### Postgres

Postgres is used for long term data retention of market and order update data, as well as analytical data such as
system latency performance.


## Development

The entire system was written in the [Nim](https://nim-lang.org/) programming language, which is a high-performance,
low-level language, in part as a learning exercise. For local development, the only requirement is the Nim
compiler and package manager (Nimble).
