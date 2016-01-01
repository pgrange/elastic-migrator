#!/bin/bash

export ELASTIC_PORT=12044

function init_scroll() {
  index="$1"
  curl -s -XGET "localhost:$ELASTIC_PORT/${index}/_search?search_type=scan&pretty&size=100&scroll=10m" -d '
  {
   "query": {"match_all" : {}}
  }' \
  | jq -r "._scroll_id,.hits.total"
}

function scroll() {
  scroll_id=$1
  curl -s -XGET "localhost:$ELASTIC_PORT/_search/scroll?scroll=10m" -d  ${scroll_id} \
  | jq .
  #| jq ".hits.hits | .[]"
}

dump_index() {
  index="$1"
  set $(init_scroll "$index")
  scroll_id=$1
  total=$2

  while scroll ${scroll_id}
  do
    echo -n
  done
}

dump_index immo

