create schema if not exists ny;


create table if not exists ny.raw_market_data (
  date date not null,
  symbol text not null,
  id text not null,
  event_timestamp timestamptz not null,
  receive_timestamp timestamptz not null,
  recording_timestamp timestamptz not null,
  type text not null,
  raw_data jsonb,

  primary key(date, symbol, id)
);

create index if not exists raw_md_timestamp_idx ON ny.raw_market_data(event_timestamp);
create index if not exists raw_md_type_idx ON ny.raw_market_data(type);

create table if not exists ny.parsed_market_data (
  date date not null,
  symbol text not null,
  id text not null,
  type text not null,
  parsed_data jsonb,

  primary key(date, symbol, id)
);


CREATE OR REPLACE VIEW ny.market_data_time_diffs AS
SELECT
  date,
  symbol,
	id,
  event_timestamp at time zone 'America/New_York' as ev_ts,
  receive_timestamp at time zone 'America/New_York' as rcv_ts,
  recording_timestamp at time zone 'America/New_York' as rcd_ts,
  
  extract(epoch from receive_timestamp - event_timestamp) as network_time_sec,
  extract(epoch from recording_timestamp - receive_timestamp) as internal_time_sec,
  extract(epoch from (recording_timestamp - event_timestamp)) as total_time_sec
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
  date date not null,
  symbol text not null,
  id text not null,

  order_id text not null,
  client_order_id text not null,
  
  event_timestamp timestamptz not null,
  receive_timestamp timestamptz not null,
  recording_timestamp timestamptz not null,

  event_type text not null,
  side text not null,
  size text not null,
  price text not null,

  order_type text not null,
  tif text not null,

  raw_data jsonb,

  primary key(date, symbol, id)
);


create table if not exists ny.parsed_order_updates (
  date date not null,
  symbol text not null,
  id text not null,

  order_id text not null,
  client_order_id text not null,

  event_type text not null,
  side text not null,
  size text not null,
  price text not null,

  order_type text not null,
  tif text not null,

  parsed_data jsonb,

  primary key(date, symbol, id)
);
