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

* POST `/conduct/<network>/<snnapshot>/topology`
  * `label`: Label (description) of the physical snapshot
  * `phy_ss_only`: [optional] Flag to target only physical snapshots
  * `use_parallel`: [optional] Flag to use parallel processing for query-to-topology data generation stage
  * `off_node`: [optional] Node name to draw-off
  * `off_intf_re`: [optional] Interface name (regexp match) to draw-off in `off_node`

```shell
# model-info.json
# -> { "label": "description of the snapshot", ... }
curl -X POST -H "Content-Type: application/json" -d @model-info.json \
  http://localhost:9292/conduct/pushed_configs/mddo_network
```

### Static verification of network structure

Fetch subsets of a snapshot

* GET `/conduct/<network>/<snapshot>/subsets`

```shell
curl http://localhost:9292/conduct/pusheed_configs/mddo_network/subsets
```

Fetch subset comparison data between physical and logical snapshots in a network

* GET `/conduct/<network>/<physical-snapshot>/subsets_diff`
  * `min_score`: [optional] Ignore comparison data lower than this score (default: 0)

```shell
curl http://localhost:9292/conduct/pushed_configs/mddo_network/subsets_diff
```

### L3 Reachability test

Run reachability test with test-pattern definition

* GET `/conduct/<network>/reachability`
  * `snapshoots`: List of snapshot to test reachability
  * `test_pattern`: Test pattern definition

```shell
# test_pattern.json
# -> { "snapshots": ["mddo_network_linkdown_01", ...], "test_pattern": <test-pattern> }
curl -X POST -H "Content-Type: application/json" -d @test_pattern.json \
  http://localhost:9292/conduct/pushed_configs/reachability
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
