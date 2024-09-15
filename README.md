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

### Snapshot diff

Take snapshot diff in a network

* GET `/conduct/<network>/snapshot_diff/<src_snapshot>/<dst_snapshot>`
  * `upper_layer3`: [optional] compare layer3 or upper layer

```shell
curl -s "http://localhost:9292/conduct/mddo-ospf/snapshot_diff/emulated_asis/emulated_tobe?upper_layer3=true"
```

Take snapshot diff and write back (overwrite) as destination snapshot

* POST `/conduct/<network>/snapshot_diff/<src_snapshot>/<dst_snapshot>`
  * `upper_layer3`: [optional] compare layer3 or upper layer

```shell
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{ "upper_layer3": true }' \
  http://localhost:9292/conduct/mddo-ospf/snapshot_diff/emulated_asis/emulated_tobe
```

### Convert snapshot namespace

Convert namespace of source snapshot and post it as destination snapshot

* POST `/conduct/<network>/ns_convert/<src_snapshot>/<dst_snapshot>`
  * `table_origin`: [optional] Origin snapshot name to initialize convert table,
    Force update the convert table of a network if this option used.

```shell
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{ "table_origin": "original_asis" }' \
  http://localhost:9292/conduct/mddo-ospf/ns_convert/original_asis/emulated_asis
```

### Splice external topology

Splice external topology (external-AS topology) to snapshot topology.

* POST `/conduct/<network>/<snapshot>/splice_topology`
  * `ext_topology_data`: external topology data (RFC8345 json) to splice
  * `overwrite`: [optional] true to write snapshot topology (default: true).
    If false, it does not modify snapshot topology (Only get spliced topology data)

```shell
# ext_topology.json : external topology data to splice (RFC8345 json)
curl -s -X POST -H "Content-Type: application/json" \
  -d @<(jq '{ "overwrite": true, "ext_topology_data": . }' ext_topology.json) \
  http://localhost:9292/conduct/biglobe_deform/original_asis/splice_topology
```

### Add node/term-point attribute data

> [!NOTE]
> Currently, for bgp-proc only (to "patch" bgp policy or other attribute data).
> It used in bgp-policy-parser in PNI use-case of copy-to-emulated-env demo.

Add node/term-point attribute.

* POST `/conduct/<network>/<snapshot>/topology/<layer>/policies`
  * `node`: node/term-point attribute (RFC8345-json format)

<details>
<summary>Patch data (bgp-policy-patch.json)</summary>

```json
{
    "node": [
        {
            "node-id": "192.168.255.7",
            "ietf-network-topology:termination-point": [
                {
                    "tp-id": "peer_192.168.255.2",
                    "mddo-topology:bgp-proc-termination-point-attributes": {
                        "import-policy": ["ibgp-export"]
                    }
                }
            ]
        }
    ]
}
```

</details>

```shell
curl -s -X POST -H 'Content-Type: application/json' \
  -d @bgp-policy-patch.json \
  http://localhost:9292/conduct/biglobe_deform/original_asis/topology/bgp_proc/policies
```

### Generate candidate config

Generate candidate configs from original_asis snapshot

* POST `/conduct/<network>/<snapshot>/candidate_topology`
  * `candidate_number`: Number of candidate configs
  * `usecase`: Usecase parameter
    * `name`: Usecase name
    * `sources`: Data sources for the usecase

```shell
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"candidate_number": 3, "usecase": { "name": "pni_te", "sources": ["params", "flow_data"]}}' \
  http://localhost:9292/conduct/mddo-bgp/original_asis/candidate_topology
```

## Development

### Optional: Build model-conductor container

model-conductor uses [netomox](https://github.com/ool-mddo/netomox) gem that pushed on github packages.
So, it need authentication to exec `bundle install` when building its container image.
You have to pass authetication credential via `ghp_credential` environment variable like below:

- `USERNAME` : your github username
- `TOKEN` : your github personal access token (need `read:packages` scope)

```shell
ghp_credential="USERNAME:TOKEN" docker buildx build -t model-conductor --secret id=ghp_credential .
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
