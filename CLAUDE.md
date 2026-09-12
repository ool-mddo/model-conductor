# model-conductor

## Overview

MDDO システムのフロントエンド REST API サーバー（Ruby / Grape）。
バックエンドの **batfish-wrapper** と **netomox-exp** をオーケストレーションし、RFC8345 形式のネットワークトポロジーデータの構築・変換・検証・操作を担う。

## Setup

```sh
# netomox gem は GitHub Packages から取得（認証必要）
export BUNDLE_RUBYGEMS__PKG__GITHUB__COM="USERNAME:GITHUB_PAT"
bundle install
```

## Commands

| 目的 | コマンド |
|------|---------|
| サーバー起動 | `bundle exec rackup -s webrick -o 0.0.0.0 -p 9292` |
| 開発（自動リロード） | `rerun bundle exec rackup -s webrick -o 0.0.0.0 -p 9292` |
| コンテナ内（ボリューム） | `rerun --force-polling bundle exec rackup -s webrick -o 0.0.0.0 -p 9292` |
| Lint | `bundle exec rake rubocop` |
| Lint 自動修正 | `bundle exec rake rubocop:auto_correct` |
| ドキュメント生成 | `bundle exec rake yard` |
| Docker ビルド | `ghp_credential="USER:TOKEN" docker buildx build -t model-conductor --secret id=ghp_credential .` |

## Environment Variables

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `BATFISH_WRAPPER_HOST` | `batfish-wrapper:5000` | batfish-wrapper のホスト |
| `NETOMOX_EXP_HOST` | `netomox-exp:9292` | netomox-exp のホスト |
| `MODEL_CONDUCTOR_LOG_LEVEL` | `info` | ログレベル（`fatal/error/warn/info/debug`） |

## Critical Constraints

### JSON の symbolize_names は文脈で使い分ける

`MddoRestApiClient` 内の `DO NOT symbolize` コメントは必ず守ること。ホスト名・インターフェース名をハッシュキーとして使う箇所（`ns_convert_table`、`converted_topology` など）は `symbolize_names: false` のまま扱う必要がある。Symbol 化すると文字列キーによるアクセスが壊れる。

### バックエンド URL はパスプレフィックスで振り分けられる

`MddoRestApiClient#dispatch_url` が API パスの第 1 セグメントで転送先を決定する：

- `topologies`, `usecases` → netomox-exp
- それ以外（`queries`, `configs`, `batfish`, `tools`）→ batfish-wrapper

新しいバックエンド API を追加する際は `NETOMOX_EXP_URL_RESOURCE` 定数の更新要否を確認すること。

### netomox gem のオープンクラスパッチが 3 か所ある

以下のファイルで `Netomox::Topology::*` クラスを reopen して機能追加している。gem バージョンアップ時は非互換を確認すること。

- `lib/splice_topology/netomox_patch.rb`
- `lib/topology_ops/netomox_patch.rb`
- `lib/generate_candidate_topologies/netomox_topology.rb`

### スナップショット命名規則に依存するロジックがある

- `original` → `emulated` の変換はハードコードされている（`topology_ops.rb`）
- `original_asis_preallocated_N` の N を正規表現でインクリメントするロジックがある

この命名規則を変更すると広範に影響する。

### CandidateTopologyGenerator のユースケースは固定

`ALLOWED_USECASES = %w[pni_te multi_region_te multi_src_as_te]`（`candidate_topology_generator.rb`）。他のユースケースは拒否される。

### json 3.x では symbolize_names をキーワード引数で渡す

json 2.x まで許容されていた `JSON.parse(str, { symbolize_names: true })` はjson 3.x で `ArgumentError` になる。必ずキーワード引数形式を使うこと:

```ruby
# NG (json 3.x では ArgumentError)
JSON.parse(str, { symbolize_names: true })

# OK
JSON.parse(str, symbolize_names: true)
```

### Ruby 3.4 以降は標準ライブラリの gem を明示的に Gemfile に列挙する

Ruby 3.4 から `csv` がデフォルト gem から外れた（`ostruct` は Ruby 4.0 で外れる予定）。
`require 'csv'` などが `LoadError` になる場合は Gemfile に該当 gem を追加すること。

## Testing

**テストファイルは存在しない。** 変更後は実際の API を叩いて手動確認が必要。
