create schema if not exists ny;

create table if not exists ny.raw_market_data (
  id text not null,
  date date not null,
  timestamp timestamptz not null,
  symbol text not null,
  type text not null,
  data jsonb,

  primary key(id, symbol),

  recording_timestamp timestamptz not null
);

create index if not exists raw_md_date_idx ON ny.raw_market_data(date);
create index if not exists raw_md_timestamp_idx ON ny.raw_market_data(timestamp);
create index if not exists raw_md_symbol_idx ON ny.raw_market_data(symbol);
create index if not exists raw_md_type_idx ON ny.raw_market_data(type);


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
