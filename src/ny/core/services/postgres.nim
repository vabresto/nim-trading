## # Overview
## 
## This module implements a wrapper for postgres db access, injecting the relevant variables into scope.

import chronicles except toJson
import db_connector/db_postgres

import ny/core/env/envs


template withDb*(db, actions: untyped): untyped =
  var db: DbConn
  var dbInitialized = false
  
  try:
    info "Starting postgres db connection ..."
    db = getMdDb(loadOrQuit("MD_PG_HOST"), loadOrQuit("MD_PG_USER"), loadOrQuit("MD_PG_PASS"), loadOrQuit("MD_PG_NAME"))
    dbInitialized = true
    info "Postgres db connected"

    actions

  except DbError:
    if not dbInitialized:
      # This branch reflects failing to initialize the db conn itself
      warn "DbError", msg=getCurrentExceptionMsg()  
    else:
      error "DbError", msg=getCurrentExceptionMsg()

  finally:
    if dbInitialized:
      try:
        db.close()
      finally:
        dbInitialized = false
