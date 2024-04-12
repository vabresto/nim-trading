## This is a market data recorder
## It subscribes to a redis stream, and forwards the data into a db

import std/net
import std/options
import std/os
import std/strformat
import std/strutils
import std/times

import chronicles except toJson
import db_connector/db_postgres
import nim_redis

import ny/core/db/mddb
import ny/core/env/envs
import ny/core/types/timestamp
import ny/core/utils/rec_parseopt

import ny/core/services/postgres
import ny/core/services/redis
import ny/core/services/streams

logScope:
  topics = "ny-eod"


iterator iterateOverDates(startDateStr: string, endDateStr: string): DateTime =
  let startDate = parse(startDateStr, "yyyy-MM-dd")
  let endDate = parse(endDateStr, "yyyy-MM-dd")
  
  var currentDate = startDate

  while currentDate <= endDate:
      yield currentDate
      currentDate += days(1)


proc sleepUntilNextHour() =
    let now = now()
    var nextHour = now.getDateStr.parse("yyyy-MM-dd")
    nextHour.hour = now.hour + 1
    let dur = (nextHour - now).inMilliseconds
    info "Sleeping", now, nextHour, dur
    sleep dur


iterator iterateNextWeekBusinessDays(startDateStr: string): DateTime =
    let startDate = parse(startDateStr, "yyyy-MM-dd")
    let endDate = startDate + initDuration(days=7)

    var currentDate = startDate
    while currentDate <= endDate:
        if currentDate.weekday != dSat and currentDate.weekday != dSun:
            yield currentDate
        currentDate += days(1)


proc main() {.raises: [].} =
  let _ = parseCliArgs()

  while true:
    try:
      info "Starting connections ..."
      withDb(db):
        withRedis(redis):
          let curTime = getNowUtc()
          
          let curHour = curTime.toDateTime.hour
          if curHour > 7:
            # Don't do anything if it is after 7 am
            info "Current hour after cutoff, sleeping ...", curHour
            sleep initDuration(hours=1).inMilliseconds
            continue

          # Prune any redis keys older than 3 days
          let redisMaxPruneDate = (curTime - initDuration(days=5)).getDateStr
          let redisRes = redis.cmd("SCAN", "0")
          if redisRes.isErr:
            error "Failed to scan redis!", error=redisRes.error.msg
          else:
            try:
              let keys = redisRes[].arr[1].arr
              for key in keys:
                let splitted = key.str.split(":")
                if splitted.len != 3:
                  continue
                let keyDate = splitted[1]
                if keyDate < redisMaxPruneDate:
                  info "Pruning key", key, keyDate, redisMaxPruneDate
                  let delRes = redis.cmd("DEL", key.str)
                  if delRes.isErr:
                    error "Failed to prune redis key", key, error=delRes.error.msg
            except KeyError:
              error "Key error trying to prune redis keys", msg=getCurrentExceptionMsg()

          # Prune any market data older than 30 days (could probably go more than this np)
          let dbMaxPruneDate = (curTime - initDuration(days=30)).getDateStr

          for table in ["parsed_market_data", "raw_market_data"]:
            info "Pruning table ...", table, dbMaxPruneDate
            db.exec(sql(fmt"""
            DELETE FROM ny.{table} WHERE date < ?;
            """), dbMaxPruneDate)
            info "Done pruning table", table, dbMaxPruneDate

          # Get last date we have breakdown stats for
          let curDate = curTime.getDateStr
          for row in db.getAllRows(sql("""
            WITH LatestDate AS (
                SELECT MAX(date) AS max_date FROM ny.latency_stats_breakdown
            )
            SELECT max_date FROM LatestDate
            WHERE EXISTS (SELECT 1 FROM ny.latency_stats_breakdown);
          """)):
            let lastExistingDataDate = row[0]

            for date in iterateOverDates(lastExistingDataDate, curDate):
              info "Aggregating latency_stats_breakdown", date
              let dateStr = date.format("yyyy-MM-dd")
              db.exec(sql(fmt"""
                WITH RECURSIVE intervals AS (
                  SELECT 
                    '{dateStr} 09:30:00'::timestamp AS interval_start,
                    '{dateStr} 09:35:00'::timestamp AS interval_end
                  UNION ALL
                  SELECT 
                    interval_end,
                    interval_end + interval '5 minutes'
                  FROM intervals
                  WHERE interval_end < '{dateStr} 18:00:00'::timestamp
                ), 
                latency_stats AS (
                  SELECT
                    date,
                    intervals.interval_start,
                    intervals.interval_end,
                    count(*) as num_events,
                    COALESCE(AVG(network_time_sec), 0) AS avg_network_time_sec,
                    COALESCE(AVG(internal_time_sec), 0) AS avg_internal_time_sec,
                    COALESCE(AVG(total_time_sec), 0) AS avg_total_time_sec,
                    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY network_time_sec) AS p50_network_time_sec,
                    PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY network_time_sec) AS p75_network_time_sec,
                    PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY network_time_sec) AS p99_network_time_sec,
                    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY internal_time_sec) AS p50_internal_time_sec,
                    PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY internal_time_sec) AS p75_internal_time_sec,
                    PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY internal_time_sec) AS p99_internal_time_sec,
                    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY total_time_sec) AS p50_total_time_sec,
                    PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY total_time_sec) AS p75_total_time_sec,
                    PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_time_sec) AS p99_total_time_sec
                  FROM intervals
                  LEFT JOIN ny.market_data_time_diffs mdtd ON
                    mdtd.rcd_ts >= intervals.interval_start AND
                    mdtd.rcd_ts < intervals.interval_end
                  WHERE mdtd.date = '{dateStr}'
                  GROUP BY date, intervals.interval_start, intervals.interval_end
                )
                INSERT INTO ny.latency_stats_breakdown
                  (date, interval_start, interval_end, num_events,
                    avg_network_time_sec, avg_internal_time_sec, avg_total_time_sec,
                    p50_network_time_sec, p75_network_time_sec, p99_network_time_sec,
                    p50_internal_time_sec, p75_internal_time_sec, p99_internal_time_sec,
                    p50_total_time_sec, p75_total_time_sec, p99_total_time_sec)
                SELECT
                  date,
                  interval_start,
                  interval_end,
                  num_events,
                  avg_network_time_sec,
                  avg_internal_time_sec,
                  avg_total_time_sec,
                  p50_network_time_sec,
                  p75_network_time_sec,
                  p99_network_time_sec,
                  p50_internal_time_sec,
                  p75_internal_time_sec,
                  p99_internal_time_sec,
                  p50_total_time_sec,
                  p75_total_time_sec,
                  p99_total_time_sec
                FROM latency_stats
                ON CONFLICT (date, interval_start, interval_end) DO UPDATE SET
                  num_events = EXCLUDED.num_events,
                  avg_network_time_sec = EXCLUDED.avg_network_time_sec,
                  avg_internal_time_sec = EXCLUDED.avg_internal_time_sec,
                  avg_total_time_sec = EXCLUDED.avg_total_time_sec,
                  p50_network_time_sec = EXCLUDED.p50_network_time_sec,
                  p75_network_time_sec = EXCLUDED.p75_network_time_sec,
                  p99_network_time_sec = EXCLUDED.p99_network_time_sec,
                  p50_internal_time_sec = EXCLUDED.p50_internal_time_sec,
                  p75_internal_time_sec = EXCLUDED.p75_internal_time_sec,
                  p99_internal_time_sec = EXCLUDED.p99_internal_time_sec,
                  p50_total_time_sec = EXCLUDED.p50_total_time_sec,
                  p75_total_time_sec = EXCLUDED.p75_total_time_sec,
                  p99_total_time_sec = EXCLUDED.p99_total_time_sec
                  ;
              """))

          # Get last date we have daily stats for
          for row in db.getAllRows(sql("""
            WITH LatestDate AS (
                SELECT MAX(date) AS max_date FROM ny.latency_stats_daily
            )
            SELECT max_date FROM LatestDate
            WHERE EXISTS (SELECT 1 FROM ny.latency_stats_daily);
          """)):
            let lastExistingDataDate = row[0]

            for date in iterateOverDates(lastExistingDataDate, curDate):
              info "Aggregating latency_stats_daily", date
              # Generate aggregated stats
              db.exec(sql(fmt"""
                WITH time_diffs AS (
                    SELECT
                        date,
                        greatest(0, EXTRACT(EPOCH FROM (receive_timestamp - event_timestamp))) AS network_time_sec,
                        greatest(0, EXTRACT(EPOCH FROM (recording_timestamp - receive_timestamp))) AS internal_time_sec,
                        greatest(0, EXTRACT(EPOCH FROM (recording_timestamp - event_timestamp))) AS total_time_sec
                    FROM ny.raw_market_data
                    WHERE type IN ('Trade', 'Quote')
                    AND date = ?
                )
                INSERT INTO ny.latency_stats_daily
                  (date, num_events,
                    avg_network_time_sec, avg_internal_time_sec, avg_total_time_sec,
                    p50_network_time_sec, p75_network_time_sec, p99_network_time_sec,
                    p50_internal_time_sec, p75_internal_time_sec, p99_internal_time_sec,
                    p50_total_time_sec, p75_total_time_sec, p99_total_time_sec)
                SELECT
                    date,
                    COUNT(*) AS num_events,
                    AVG(network_time_sec) AS avg_network_time_sec,
                    AVG(internal_time_sec) AS avg_internal_time_sec,
                    AVG(total_time_sec) AS avg_total_time_sec,
                    PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY network_time_sec) AS p50_network_time_sec,
                    PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY network_time_sec) AS p75_network_time_sec,
                    PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY network_time_sec) AS p99_network_time_sec,
                    PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY internal_time_sec) AS p50_internal_time_sec,
                    PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY internal_time_sec) AS p75_internal_time_sec,
                    PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY internal_time_sec) AS p99_internal_time_sec,
                    PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY total_time_sec) AS p50_total_time_sec,
                    PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY total_time_sec) AS p75_total_time_sec,
                    PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_time_sec) AS p99_total_time_sec
                FROM time_diffs
                GROUP BY date
                ON CONFLICT (date) DO UPDATE SET
                  num_events = EXCLUDED.num_events,
                  avg_network_time_sec = EXCLUDED.avg_network_time_sec,
                  avg_internal_time_sec = EXCLUDED.avg_internal_time_sec,
                  avg_total_time_sec = EXCLUDED.avg_total_time_sec,
                  p50_network_time_sec = EXCLUDED.p50_network_time_sec,
                  p75_network_time_sec = EXCLUDED.p75_network_time_sec,
                  p99_network_time_sec = EXCLUDED.p99_network_time_sec,
                  p50_internal_time_sec = EXCLUDED.p50_internal_time_sec,
                  p75_internal_time_sec = EXCLUDED.p75_internal_time_sec,
                  p99_internal_time_sec = EXCLUDED.p99_internal_time_sec,
                  p50_total_time_sec = EXCLUDED.p50_total_time_sec,
                  p75_total_time_sec = EXCLUDED.p75_total_time_sec,
                  p99_total_time_sec = EXCLUDED.p99_total_time_sec;
              """), date.format("yyyy-MM-dd"))

          # Add the symbols + feeds to register to next based on what we are currently registered for
          var processedAnyFeedsToRegister = false
          for curSubRow in db.getAllRows(sql("""
            WITH LatestDate AS (
                SELECT feed, MAX(date) AS max_date FROM ny.md_subscriptions group by feed
            )
            SELECT
              feed,
              max_date,
              case
                when feed = 'sip' then 3
                when feed = 'iex' then 2
                when feed = 'test' then 1
            end as feed_priority
            FROM LatestDate
            WHERE EXISTS (SELECT 1 FROM ny.md_subscriptions)
            order by feed_priority DESC
          """)):
            if processedAnyFeedsToRegister:
              continue
            processedAnyFeedsToRegister = true

            let symbols = block:
              var symbols = newSeq[tuple[feed: string, symbol: string]]()
              for symbolRow in db.getAllRows(sql("""
                SELECT
                  feed,
                  symbol
                FROM ny.md_subscriptions
                WHERE feed = ?
                 AND date = ?
              """), curSubRow[0], curSubRow[1]):
                symbols.add((symbolRow[0], symbolRow[1]))
              symbols

            db.exec(sql("BEGIN;"))
            for date in iterateNextWeekBusinessDays(curDate):
              info "Updating market data subscriptions setting", date, symbols
              db.exec(sql("DELETE FROM ny.md_subscriptions WHERE date = ?"), date)
              for (feed, symbol) in symbols:
                db.exec(sql("""
                  INSERT INTO ny.md_subscriptions (date, feed, symbol)
                  VALUES (?, ?, ?);
                """), date, feed, symbol)
            db.exec(sql("COMMIT;"))

          # Sleep until roughly the next hour mark
          sleepUntilNextHour()

    except OSError:
      error "OSError", msg=getCurrentExceptionMsg()

    except Exception:
      error "Generic uncaught exception", msg=getCurrentExceptionMsg()

    sleep initDuration(seconds=15).inMilliseconds


when isMainModule:
  main()
