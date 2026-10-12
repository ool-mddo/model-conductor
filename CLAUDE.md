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
| **テスト実行** | `bundle exec rspec` |
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

### conduit の layer3 TP 属性は新規構築される

`Layer3ConduitBuilder#build_router_conduit_tp` は Router グループの conduit TP の属性を `ip-address` / `flag` (と必要なら `fhrp`) で
**新規に作る** (元 TP の属性を引き継がない)。layer3 TP に新しい属性を追加した場合は、ここ (Firewall グループは丸ごと `dup` されるので不要) を更新しないと conduit で落ちる。

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

### FHRP (VRRP/HSRP) TP アトリビュート JSON スキーマ

layer3 TP の `fhrp` アトリビュートの canonical definition:
**`playground/docs/fhrp_termination_point_attributes.md`**
(conduit topology での扱いは本ファイルの「土管化ルール」を参照。netomox 0.14.0 以降が必要)

### FW ノードアトリビュート JSON スキーマ

FW ノードに関する JSON スキーマの canonical definition:
**`playground/docs/firewall_node_attributes.md`**

conduit topology 生成時の FW ノード識別は top-level `"flag": ["firewall"]` で行う
(`node.attribute.firewall` は全ノードで常に non-nil のため使用不可)。

### ConduitTopologyGenerator の土管化ロジック

`lib/generate_conduit_topology/` に以下のファイルが実装済み:

- `blueprint_network.rb` — BlueprintNetwork クラス。blueprint の node supports を layer3 ノード名まで再帰的に解決。NodeGroup struct を定義。
- `layer3_conduit_builder.rb` — Layer3ConduitBuilder クラス。conduit layer3 ネットワーク・node_mapping・tp_mapping を生成。
- `fhrp_gateway_resolver.rb` — FhrpGatewayResolver クラス。`fhrp` (VRRP/HSRP) を持つ TP の扱い (冗長を維持できるかの判定、代表 TP の選択、VIP への変換) を担う。
- `ospf_conduit_builder.rb` — OspfConduitBuilder クラス。node_mapping/tp_mapping を使って各 ospf_area conduit を生成。
- `conduit_topology_generator.rb` — ConduitTopologyGenerator クラス。blueprint ネットワーク 1 つあたり 1 つの conduit topology を生成するオーケストレーター。

**土管化ルール:**
- Firewall ノード (top-level `flag` に `"firewall"` を含む): 全ての元ノードを個別に保持。TP 名・属性はそのまま
- Router ノード (blueprint でグループ化): 代表ノード 1 つに集約。外部接続 TP のみ eth1, eth2, ... に rename
  - 例外: `fhrp` (VRRP/HSRP) を持つ **unlinked TP (セグメントに接続していない TP = エッジ)** は、外部 TP の連番に続けて `ethN+1...` として残す
    (目的: エッジセグメントのエンドポイントのデフォルトゲートウェイを変えない)。`FhrpGatewayResolver` が次のように決める:
    - 冗長を維持できる (同じ FHRP グループ `(protocol, group-id, virtual-address)` のメンバーが、blueprint に含まれるノードの範囲で
      2 つ以上の異なる conduit ノードにいる): `ip-address` と `fhrp` を元 TP のまま引き継ぐ
    - 冗長を維持できない (1 つの conduit ノードに畳まれた / パートナーが blueprint に無い): `fhrp` は付けず、`ip-address` を
      **virtual-address + source-address のプレフィックス長** (例 `192.168.100.1/24`) にする
    - 1 conduit ノード・1 FHRP グループにつき TP は 1 つ。代表は Master/Active に選ばれるメンバー
      (priority 最大、同値なら source-address の数値が最大。VRRP/HSRP 共通。VRRP の 255 が最優先、0 が最後、同値ならメンバー順)
    - 外部 TP (他グループとのセグメントに接続) が `fhrp` を持つ場合は IP を変えず、冗長を維持できるときだけ `fhrp` を引き継ぐ
  - `fhrp` を持たない unlinked TP は従来どおり残らない。現行の blueprint (cr ノードを含まない) の出力は変わらない
- Segment ノード: グループ間をまたぐ(外部)セグメントのみ自動生成。同一グループ内の内部セグメントは除外
- ospf_area: layer3 の node_mapping/tp_mapping を共有して同様の変換を適用

**注意:** `parse_seg_tp` は ospf_area の Seg TP 名 (`{orig_node}_{orig_tp}`) を tp_mapping への逆引きで解決。
TP 名に `_` を含むノード名がある場合は曖昧性が生じる可能性があるが、現行データでは問題なし。

### conduit_topology API エンドポイント

`POST /conduct/:network/:snapshot/conduit_topology`

パラメータ:
- `usecase` (String) — ユースケース名（例: `refocus_topology`）
- `blueprint_snapshot` (String) — blueprint snapshot 名（例: `original_asis_blueprint`）

処理:
1. 既存の `*_conduitN` スナップショットを削除
2. blueprint topology を netomox-exp から取得
3. original topology を netomox-exp から取得（`upper_layer3: false`）
4. `ConduitTopologyGenerator` で conduit topology を生成
5. 各 conduit を `{snapshot}_conduit1`, `{snapshot}_conduit2`, ... として保存
   (各 topology の `ietf-network:networks` 直下に `mddo-topology:networks-attributes` の `flag: ["blueprint=<blueprint_snapshot>"]` を付ける。
   スキーマ: [docs/networks_attributes.md](../../docs/networks_attributes.md))

レスポンス: `[{snapshot: "original_asis_conduit1"}, ...]`

### MddoRestApiClient の追加メソッド

- `delete_snapshot(network, snapshot)` — `DELETE /topologies/:nw/:ss` を呼び出してスナップショットを削除
- `fetch_blueprint_topology_data(usecase, network, snapshot)` — `GET /usecases/:uc/:nw/:ss/topology` で blueprint topology を取得（`symbolize_names: false`）

### ns_convert_table API はスナップショット単位

変換テーブルは per-network ではなく **per-snapshot** で管理される（netomox-exp v1.19.0-dev 以降）。

| メソッド | 旧 URL | 新 URL |
|---|---|---|
| `fetch_ns_convert_table(network, snapshot)` | `GET /topologies/:nw/ns_convert_table` | `GET /topologies/:nw/:ss/ns_convert_table` |
| `post_init_ns_convert_table(network, origin_ss, ...)` | `POST /topologies/:nw/ns_convert_table` (body に `origin_snapshot`) | `POST /topologies/:nw/:ss/ns_convert_table` (`:ss` が source snapshot) |
| `post_update_ns_convert_table(network, snapshot, table)` | `POST /topologies/:nw/ns_convert_table` (body に `convert_table`) | `POST /topologies/:nw/:ss/ns_convert_table` (body に `convert_table`) |

**`topology_ops.rb` での使用:**
- `fetch_ns_convert_table(network, curr_orig_pa_ss_name)` — 現在の preallocated snapshot のテーブルを読む
- `post_update_ns_convert_table(network, next_orig_pa_ss_name, ...)` — 次の preallocated snapshot にテーブルを保存

**`ns_convert.rb` での使用:**
- `exist_ns_convert_table!(network, src_ss)` — src snapshot のテーブル存在チェック
- `post_init_ns_convert_table(network, origin_ss, usecase)` — origin snapshot からテーブル生成・保存
- `fetch_ns_convert_table` + `post_update_ns_convert_table(network, dst_ss, table)` — 変換後に同一テーブルを dst snapshot にも保存 (元テーブルは `table_origin` があればそれ、なければ `src_ss`)

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

RSpec を使用する。テスト関連 gem は `group :test`（Gemfile）で管理し、Docker イメージには含まれない。

```sh
bundle exec rspec                              # 全テスト
bundle exec rspec spec/nw_subsets/            # ディレクトリ指定
bundle exec rspec -e "node_groups"            # テスト名で絞り込み
```

テスト戦略・クラス分類（Tier 1〜3）・モッキング方針の詳細は [`docs/testing.md`](docs/testing.md) を参照。

### テストを追加する際の注意点

- **Tier 1**（HTTP 依存なし）: `spec/fixtures/*.json` のフィクスチャを渡すだけでテスト可能。新しい純粋変換クラスはここに追加する。
- **Tier 3**（`ModelConductor.rest_api` が必要）: `include_context 'with mocked rest_api'` を使い `instance_double(ModelConductor::MddoRestApiClient)` で差し替える。
- `raise_error` マッチャーは必ず型を指定する（例: `raise_error(StandardError, /message/)`）。型なしだと `NoMethodError` 等で偽陽性になる。
