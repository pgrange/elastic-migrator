#!/bin/bash

pwd=$(cd $(dirname $BASH_SOURCE); pwd)
cmd_under_test=$pwd/elastic_migrator
export ELASTIC_PORT=12044

# test index creation

test_create_index_for_given_version() {
  assert "$cmd_under_test test 1"

  assert_index_exists test_1
  assert_alias test test_1
}

test_create_index_with_default_settings_when_none_defined() {
  assert "$cmd_under_test test 1"

  assert_settings test_1 null
}

test_create_index_with_defined_settings() {
  assert "$cmd_under_test test 2"

  assert_settings test_2 '{
    "index.mappings.person.properties.name.type": "string",
    "index.mappings.person.properties.address.type": "string"
  }'
}

# test pre-conditions

test_fail_when_index_already_exists_for_this_version() {
  assert "$cmd_under_test test 1"

  assert_status_code 2 "$cmd_under_test test 1" \
    "$cmd_under_test should exit with status 2 when index \
     already exists for this version"
}

test_fail_when_index_not_defined_in_mappings() {
  assert_status_code 3 "$cmd_under_test no_mapping_index 1" \
    "$cmd_under_test should exit with status 3 when index \
     not defined in mappings"
}

test_fail_when_version_not_defined_for_this_index_in_mappings() {
  assert_status_code 4 "$cmd_under_test test 12043" \
    "$cmd_under_test should exit with status 4 when version \
     not defined for index in mappings"
}

test_fail_when_version_is_not_an_integer() {
  assert_status_code 5 "$cmd_under_test test version" \
    "$cmd_under_test should exit with status 5 when version \
     is not an integer"
}

# test version migration

test_update_alias_when_migrating_from_previous_version() {
  assert "$cmd_under_test test 1"

  assert "$cmd_under_test test 2"

  assert_index_exists test_2
  assert_alias test test_2
}

test_copy_data_from_previous_to_next_version() {
  assert "$cmd_under_test test 1"
  assert "insert test_1 person charles '{\"name\": \"Charles\"}'"
  assert "insert test_1 person henry '{\"name\": \"Henry\"}'"
  assert "insert test_1 shop ikea '{\"name\": \"ikea\"}'"

  assert "curl -sf localhost:$ELASTIC_PORT/_all/_refresh" #force elastic refresh

  assert "$cmd_under_test test 2"

  assert "curl -sf localhost:$ELASTIC_PORT/_all/_refresh" #force elastic refresh

#FIXME refactor !!!!

  assert_contains test_2 \
    '{"_type": "person", "_id": "charles", "_source": {"name": "Charles"}}' \
    '{"_type": "person", "_id": "henry", "_source": {"name": "Henry"}}' \
    '{"_type": "shop", "_id": "ikea", "_source": {"name": "ikea"}}' 
}

#TODO test_migrate_data_from_a_previous_previous_version

###

assert_index_exists() {
  index=$1
  assert \
    "curl -f -XGET localhost:$ELASTIC_PORT/$index/_settings" \
    "it seems index [$index] does not exist"
}

assert_alias() {
  alias=$1
  target=$2

  assert "curl -f -XGET localhost:$ELASTIC_PORT/_alias/$alias" \
    "alias $alias does not exist"

  assert_equals "$index" \
    "$(curl -f -XGET localhost:$ELASTIC_PORT/_alias/$alias 2>/dev/null | jq -r 'keys | .[]')"
}

assert_settings() {
  local index="$1"
  local expected_settings=$(echo $2 | jq -c .) #reformat json

  assert_index_exists "$index"

  # GET index settings, removing elements added by elasticsearch
  local actual_settings=$(\
    curl -fs -XGET localhost:$ELASTIC_PORT/$index/_settings |\
      jq -c "
        def filter_keys(k): 
          k - [\"index.number_of_replicas\", \"index.version.created\",
               \"index.uuid\", \"index.number_of_shards\"];
        def key_value(k): . + {__key: k[]} | {(.__key): .[.__key]}; 
        .$index.settings | [key_value(filter_keys(keys))] | add " |\
      jq -c . #reformat json
  )
  assert_equals "$expected_settings" "$actual_settings"
}

assert_contains() {
  local index=$1
  shift
  local expected=$(echo $* | jq -c --slurp .) #format json
  local actual=$(curl -sf -XGET localhost:$ELASTIC_PORT/${index}/_search?size=100 -d '{"query": {"match_all": {}}}' | jq -c '.hits | .hits[] | {_source,_type,_id}' | jq -c --slurp 'sort')

  local to_compare="{\"expected\": $expected,\"actual\": $actual}"

  assert $(echo $to_compare | jq '.actual == .expected') \
    "JSON objects are different: $(echo $to_compare | jq -C .)"
}

setup() {
  # clean test index if exists
  curl -XDELETE localhost:$ELASTIC_PORT/test_1 >/dev/null 2>&1
  curl -XDELETE localhost:$ELASTIC_PORT/test_2 >/dev/null 2>&1
  curl -XDELETE localhost:$ELASTIC_PORT/test_12043 >/dev/null 2>&1
  curl -XDELETE localhost:$ELASTIC_PORT/no_mapping_index >/dev/null 2>&1
}

###


insert() {
  index=$1
  type=$2
  id=$3
  value="$4"
  curl -f -XPUT "localhost:$ELASTIC_PORT/${index}/${type}/${id}" -d "$value"
}
