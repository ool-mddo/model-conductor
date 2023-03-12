# model-conductor

"Conductor" of model construction (frontend api of MDDO demo system).

## Directories

```text
+ model-conductor/     # https://github.com/ool-mddo/model-conductor (THIS repository)
  + doc/               # class documents (generated w/yard)
  + lib/               # library for appliation
```

## Setup

### Requirements

- Ruby >3.1.0 (development under ruby/3.1.0 and bundler/2.3.5)

### Optional: Install ruby gems

```shell
# If you install gems into project local
# bundle config set --local path 'vendor/bundle'
bundle install
```

## Environment variables

API entrypoints:
* `BATFISH_WRAPPER_HOST` : batfish-wrapper host 
* `NETOMOX_EXP_HOST` : netomox-exp host

Log level variable:
* `MODEL_CONDUCTOR_LOG_LEVEL` (default `info`)
* select a value from `fatal`, `error`, `warn`, `info` and `debug`

## Run REST API server

```shell
bundle exec rackup -s webrick -o 0.0.0.0 -p 9292
```

For development: `rerun` watches file update and reload the server.
* `--force-polling` in container with volume mount

```shell
rerun [--force-polling] bundle exec rackup -s webrick -o 0.0.0.0 -p 9292
```

## REST API

### Operate model data

Generate snapshot topology from query data for all snapshots in a network 

* POST `/model-conductor/generate-topology`
  * `model-info`: Physical snapshot info (list)
  * `phy_ss_only`: [optional] Flag to target only physical snapshots
  * `use_parallel`: [optional] Flag to use parallel processing for query-to-topology data generation stage
  * `off_node`: [optional] Node name to draw-off
  * `off_intf_re`: [optional] Interface name (regexpp match) to draw-off in `off_node`

```shell
# model-info.json
# -> { "model-info": <model-info list> }
curl -X POST -H "Content-Type: application/json" -d @model-info.json \
  http://localhost:9292/model-conductor/generate-topology
```

### Static verification of network structure

Fetch subsets of a snapshot

* GET `/model-conductor/subsets/<network>/<snapshot>`

```shell
curl http://localhost:9292/model-constructor/subsets/pusheed_configs/mddo_network
```

Fetch subset comparison data between physical and logical snapshots in a network

* GET `/model-conductor/subsets/<network>/<physical-snapshot>/compare`
  * `min_score`: [optional] Ignore comparison data lower than this score (default: 0)

```shell
curl http://localhost:9292/model-constructor/subsets/pushed_configs/mddo_network/compare
```

### L3 Reachability test

Run reachability test with test-pattern definition

* GET `/model-consstructor/reach_test`
  * `snapshot_re`: Snapshot name (regexp match) to test reachability
  * `test_pattern`: Test pattern definition

```shell
# test_pattern.json
# -> { "snapshot_re": "linkdown", "test_pattern": <test-patteren> }
curl -X POST -H "Content-Type: application/json" -d @test_pattern.json \
  http://localhost:9292/model-conductor/reach_test
```

## Development

### Optional: Build netomox container

```shell
docker build -t model-conductor .
```

### Generate YARD documents

YARD options are in `.yardopts` file.

```shell
bundle exec rake yard
```

Run yard document server (access `http://localhost:8808/` with browser)

```shell
bundle exec yard server
```

### Code analysis

```shell
bundle exec rake rubocop
# or
bundle exec rake rubocop:auto_correct
```
