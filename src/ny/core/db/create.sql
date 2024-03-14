create schema if not exists ny;


create table if not exists ny.raw_market_data (
  id text not null,
  date date not null,
  timestamp timestamptz not null,
  symbol text not null,
  type text not null,
  data jsonb,

  primary key(id, symbol),

  receive_timestamp timestamptz not null,
  recording_timestamp timestamptz not null
);

create index if not exists raw_md_date_idx ON ny.raw_market_data(date);
create index if not exists raw_md_timestamp_idx ON ny.raw_market_data(timestamp);
create index if not exists raw_md_symbol_idx ON ny.raw_market_data(symbol);
create index if not exists raw_md_type_idx ON ny.raw_market_data(type);

CREATE OR REPLACE VIEW ny.market_data_time_diffs AS
SELECT
	id,
  symbol,
  timestamp at time zone 'America/New_York' as ev_ts,
  receive_timestamp at time zone 'America/New_York' as rcv_ts,
  recording_timestamp at time zone 'America/New_York' as rcd_ts,
  
  extract(epoch from receive_timestamp - timestamp) as network_time_sec,
  extract(epoch from recording_timestamp - receive_timestamp) as internal_time_sec,
  extract(epoch from (recording_timestamp - timestamp)) as total_time_sec
FROM ny.raw_market_data
WHERE type != 'BarMinute';


create table if not exists ny.md_subscriptions (
  date date not null,
  feed text not null,
  symbol text not null,

  primary key (date, feed, symbol),

  constraint md_subscriptions_known_feeds check (
    (feed = 'sip') or (feed = 'iex') or (feed = 'test')
  ),

  constraint md_subscriptions_test_feed_symbol check (
    (feed != 'test') or (feed = 'test' and symbol = 'FAKEPACA')
  )
);


create table if not exists ny.raw_order_updates (
  id text not null,
  date date not null,
  timestamp timestamptz not null,
  symbol text not null,

  order_id text not null,
  client_order_id text not null,

  event text not null,
  side text not null,
  size text not null,
  price text not null,

  kind text not null,
  tif text not null,
  
  data jsonb,

  receive_timestamp timestamptz not null,
  recording_timestamp timestamptz not null,

  primary key(id, symbol)
);
