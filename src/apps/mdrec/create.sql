create schema if not exists ny;

create table if not exists ny.raw_market_data (
  id text not null primary key,
  date date not null,
  timestamp timestamptz not null,
  symbol text not null,
  type text not null,
  data jsonb
);

create index if not exists raw_md_date_idx ON ny.raw_market_data(date);
create index if not exists raw_md_timestamp_idx ON ny.raw_market_data(timestamp);
create index if not exists raw_md_symbol_idx ON ny.raw_market_data(symbol);
create index if not exists raw_md_type_idx ON ny.raw_market_data(type);
