# model-conductor テスト・CI 追加計画

## Context

model-conductor にはテストが一切存在せず、CI もコンテナビルドのみ（lint はコメントアウト済み）。
RSpec テストを追加し、lint → test → build_and_push の順でゲートする CI を構築する。
コンテナイメージにはテスト関連 gem を含めない。

---

## テスト戦略

### 方針：純粋なデータ変換ロジックを優先的にテストする

model-conductor の主な役割は「バックエンド API（batfish-wrapper / netomox-exp）を呼び出してトポロジデータを変換・組み合わせる」ことである。
バックエンドサービスが必要な E2E テストは実行環境の制約が大きいため、まず **外部 I/O に依存しない純粋なデータ変換クラスをユニットテスト** する。

### クラスの分類

```
Tier 1: HTTP 依存なし ─ フィクスチャ JSON を渡すだけでテスト可能
  BlueprintNetwork, Layer3ConduitBuilder, OspfConduitBuilder,
  ConduitTopologyGenerator, RouterNodeAttrMerger
  TopologySplicer
  BgpPolicyPatcher, FirewallPolicyPatcher
  NameConverter
  NetworkSubset, NetworkSet, NetworkSets
  ReachResultConverter, BFTracerouteResults

Tier 2: Netomox オブジェクト経由 ─ フィクスチャ JSON → Netomox::Topology::Networks に変換して渡す
  TopologyOpsCommander, LinkOpsCommander, ShutOpsCommander

Tier 3: ModelConductor.rest_api をモックに差し替える必要あり
  NetworkSetsDiff          ── initialize 時に fetch_topology_data x2 呼び出し
  ReachPatternHandler      ── initialize 時に fetch_networks 等 + exit 1 あり
  CandidateTopologyGenerator ── read_base_topology で fetch_topology_object 呼び出し
```

### モッキング戦略

`ModelConductor.rest_api` はモジュールレベルのシングルトン。テストでは 1 行で差し替えられる：

```ruby
allow(ModelConductor).to receive(:rest_api).and_return(instance_double(ModelConductor::MddoRestApiClient))
```

これを `shared_context 'with mocked rest_api'` として `spec/support/rest_api_helpers.rb` に定義し、Tier 3 のテスト全体で再利用する。

### `exit 1` 対策

`ReachPatternHandler` はバリデーション失敗時に `exit 1` を呼ぶ。RSpec では `SystemExit` 例外として補足できるため：

```ruby
expect { described_class.new(bad_pattern_def) }.to raise_error(SystemExit)
```

### フィクスチャ方針

実際の API レスポンスの完全コピーではなく、**テストしたいロジックを動かすのに最低限必要な構造** を持つ JSON を自作する。

| ファイル | 内容 | 利用クラス |
|---|---|---|
| `spec/fixtures/minimal_layer3_topology.json` | router1・router2・Seg ノード + リンク（layer3 ネットワーク 1 つ） | conduit, splice, subset, ops 系全般 |
| `spec/fixtures/blueprint_topology.json` | zoom0 ネットワーク + conduit_r1/conduit_r2 ノード | BlueprintNetwork, Layer3ConduitBuilder |
| `spec/fixtures/ns_convert_table.json` | node_name_table / tp_name_table の最小変換テーブル | NameConverter |

### 今回のスコープ外

- Grape API ルート層（`lib/api/conduct/`）— rack-test でテスト可能。`spec/api/ns_convert_spec.rb`（`ns_convert` が dst snapshot にも変換テーブルを保存すること）のみ実装済み、他は後回し
- `MddoRestApiClient` 自体 — WebMock で `HTTPClient` をスタブすれば可能だが、コストが高いため後回し

---

## 実装内容

### 1. Gemfile に `group :test` を追加

`group :development` ブロックの直後に追加する。

```ruby
group :test do
  gem 'rspec', '~> 3.13'
  gem 'rack-test', '~> 2.1'
  gem 'webmock', '~> 3.23'
end
```

- `rspec` — テストフレームワーク本体
- `rack-test` — Grape API エンドポイントテスト用 Rack テストヘルパー
- `webmock` — `HTTPClient` の HTTP 呼び出しをスタブ（主に MddoRestApiClient のテスト時）

追加後、`bundle install` で `Gemfile.lock` を更新する。

### 2. Dockerfile: test gem をイメージから除外

`bundle install` の前に `bundle config` を挿入する。

```dockerfile
# 変更前
&& bundle install \

# 変更後
&& bundle config set --local without 'test' \
&& bundle install \
```

`--local` で `.bundle/config` に書き込み、イメージ内で `test` グループが常に除外される。

### 3. Rakefile に RSpec タスクを追加

既存の rubocop タスクブロックのパターンに倣い追加する。

```ruby
begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  task :spec do
    warn 'RSpec is disabled'
  end
end
```

### 4. `.rspec` ファイルを新規作成

```
--require spec_helper
--format documentation
--color
--order random
```

### 5. `spec/spec_helper.rb` を新規作成

```ruby
# frozen_string_literal: true

require 'bundler/setup'

ENV['MODEL_CONDUCTOR_LOG_LEVEL'] = 'fatal'  # ロガー設定より先に設定すること

require_relative '../lib/model_conductor'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }
end
```

**注意:** `ENV['MODEL_CONDUCTOR_LOG_LEVEL']` は `require_relative '../lib/model_conductor'` より前に設定すること（モジュール本体でログレベルを読み込むため）。

### 6. サポートファイルを新規作成

#### `spec/support/rest_api_helpers.rb`

```ruby
# frozen_string_literal: true

RSpec.shared_context 'with mocked rest_api' do
  let(:mock_rest_api) { instance_double(ModelConductor::MddoRestApiClient) }

  before do
    allow(ModelConductor).to receive(:rest_api).and_return(mock_rest_api)
  end
end
```

`ModelConductor.rest_api` にアクセスするクラスのテスト全般で `include_context 'with mocked rest_api'` として使用する。

#### `spec/support/topology_fixtures.rb`

```ruby
# frozen_string_literal: true

module TopologyFixtures
  FIXTURE_DIR = File.join(__dir__, '..', 'fixtures')

  def load_fixture(filename)
    JSON.parse(File.read(File.join(FIXTURE_DIR, filename)), symbolize_names: false)
  end

  def load_fixture_sym(filename)
    JSON.parse(File.read(File.join(FIXTURE_DIR, filename)), symbolize_names: true)
  end
end

RSpec.configure do |config|
  config.include TopologyFixtures
end
```

### 7. スペックファイルの優先順位

#### Tier 1: HTTP モック不要（先に書く）

| スペックファイル | テスト対象クラス | 要点 |
|---|---|---|
| `spec/nw_subsets/network_subset_spec.rb` | `NetworkSubset` | elements, flag, countup_flag |
| `spec/nw_subsets/network_set_spec.rb` | `NetworkSet` | elements_diff, flag_diff, find_subset_includes |
| `spec/nw_subsets/network_sets_spec.rb` | `NetworkSets` | fixture JSON → Netomox オブジェクト経由で生成 |
| `spec/reach_test/reach_result_converter_spec.rb` | `ReachResultConverter` | summary / full_table の構造 |
| `spec/generate_conduit_topology/blueprint_network_spec.rb` | `BlueprintNetwork` | node_groups の再帰解決・エラーケース |
| `spec/generate_conduit_topology/router_node_attr_merger_spec.rb` | `RouterNodeAttrMerger` | IP→prefix 変換・重複除去 |
| `spec/generate_conduit_topology/layer3_conduit_builder_spec.rb` | `Layer3ConduitBuilder` | build が node_mapping / conduit node を正しく生成するか |
| `spec/generate_conduit_topology/conduit_topology_generator_spec.rb` | `ConduitTopologyGenerator` | generate が conduit topology 配列を返すか |
| `spec/splice_topology/topology_splicer_spec.rb` | `TopologySplicer` | splice! の結果構造 |
| `spec/policy_manipulation/bgp_policy_patcher_spec.rb` | `BgpPolicyPatcher` | patch_nodes の正常系・異常系 |
| `spec/policy_manipulation/firewall_policy_patcher_spec.rb` | `FirewallPolicyPatcher` | patch_nodes の正常系・異常系 |
| `spec/topology_ops/name_converter_spec.rb` | `NameConverter` | convert_node_name / convert_tp_name / 不明キー |

#### Tier 2: Netomox オブジェクトを経由（fixture JSON 必要）

| スペックファイル | テスト対象クラス |
|---|---|
| `spec/topology_ops/topology_ops_commander_spec.rb` | `TopologyOpsCommander` |
| `spec/topology_ops/link_ops_commander_spec.rb` | `LinkOpsCommander` |
| `spec/topology_ops/shut_ops_commander_spec.rb` | `ShutOpsCommander` |

#### Tier 3: `rest_api` モック必要

| スペックファイル | モックポイント | 注意事項 |
|---|---|---|
| `spec/nw_subsets/network_sets_diff_spec.rb` | `mock_rest_api.fetch_topology_data` x2 | |
| `spec/reach_test/reach_pattern_handler_spec.rb` | `fetch_networks`, `fetch_snapshots`, `fetch_all_interface_list` | バリデーション失敗で `exit 1` → `raise_error(SystemExit)` で検証 |

### 8. `.rubocop.yml` に spec/ の BlockLength 除外を追加

```yaml
Metrics/BlockLength:
  Exclude:
    - 'spec/**/*'
```

`rubocop-rspec` は追加しない（Tier 1 では不要、後から追加可能）。

### 9. GitHub Actions ワークフロー更新

`.github/workflows/actions.yaml` を置き換える。
現在はコメントアウトの `lint` ジョブと `build_and_push` のみ。
変更後の構成:

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.4'
          bundler-cache: false
      - name: Install gems (without test)
        env:
          BUNDLE_RUBYGEMS__PKG__GITHUB__COM: "${{ github.repository_owner }}:${{ secrets.GITHUB_TOKEN }}"
        run: |
          bundle config set --local without 'test'
          bundle install
      - run: bundle exec rake rubocop

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.4'
          bundler-cache: false
      - name: Install gems (without development)
        env:
          BUNDLE_RUBYGEMS__PKG__GITHUB__COM: "${{ github.repository_owner }}:${{ secrets.GITHUB_TOKEN }}"
        run: |
          bundle config set --local without 'development'
          bundle install
      - run: bundle exec rspec

  build_and_push:
    needs: [lint, test]   # ← lint + test が通った場合のみビルド
    # ...既存の内容をそのまま利用、actions/checkout を @v4 に更新
```

**ポイント:**
- `lint` ジョブ: `without 'test'` で test gem を除き、`production` + `development` をインストール（rubocop が使用可能）
- `test` ジョブ: `without 'development'` で開発 gem を除き、`production` + `test` をインストール
- `BUNDLE_RUBYGEMS__PKG__GITHUB__COM` は環境変数として設定（env var が Bundler 認証に優先される）
- `build_and_push` は `needs: [lint, test]` でゲート

---

## 実装順序

1. `Gemfile` に `group :test` 追加 → `bundle install` で lock 更新
2. `Dockerfile` に `bundle config set --local without 'test'` 追加
3. `Rakefile` に `:spec` タスク追加
4. `.rspec` 作成
5. `spec/spec_helper.rb` 作成
6. `spec/support/rest_api_helpers.rb` + `spec/support/topology_fixtures.rb` 作成
7. `spec/fixtures/` に 3 つの JSON 作成
8. Tier 1 スペック群を作成・動作確認（`bundle exec rspec spec/nw_subsets/ spec/generate_conduit_topology/blueprint_network_spec.rb`）
9. Tier 2 → Tier 3 スペック群を順に追加
10. `.rubocop.yml` 更新（spec/ の BlockLength 除外）
11. `.github/workflows/actions.yaml` 更新
12. push して CI パイプライン（lint → test → build）を確認

---

## 検証方法

```sh
# ローカルでテスト実行
bundle exec rspec

# lint
bundle exec rake rubocop

# Dockerfile test gem 除外の確認（docker build 後）
docker run --rm model-conductor bundle list | grep rspec  # 何も出力されないこと
```

GitHub Actions では lint + test の両ジョブが green になると build_and_push が自動実行される。

## 現状（2026-10-03 時点）

### 実装済み

| スペックファイル | 対象クラス | Tier |
|---|---|---|
| `spec/nw_subsets/network_subset_spec.rb` | `NetworkSubset` | 1 |
| `spec/nw_subsets/network_set_spec.rb` | `NetworkSet` | 1 |
| `spec/topology_ops/name_converter_spec.rb` | `NameConverter` | 1 |
| `spec/generate_conduit_topology/blueprint_network_spec.rb` | `BlueprintNetwork` | 1 |
| `spec/generate_conduit_topology/router_node_attr_merger_spec.rb` | `RouterNodeAttrMerger` | 1 |
| `spec/generate_conduit_topology/layer3_conduit_builder_spec.rb` | `Layer3ConduitBuilder` | 1 |
| `spec/policy_manipulation/bgp_policy_patcher_spec.rb` | `BgpPolicyPatcher` | 1 |

計 **49 examples, 0 failures**。

### 残課題

#### 未作成スペック

**Tier 1（HTTP 依存なし — すぐに追加可能）**

| スペックファイル | 対象クラス | 備考 |
|---|---|---|
| `spec/reach_test/reach_result_converter_spec.rb` | `ReachResultConverter` | |
| `spec/policy_manipulation/firewall_policy_patcher_spec.rb` | `FirewallPolicyPatcher` | |
| `spec/generate_conduit_topology/conduit_topology_generator_spec.rb` | `ConduitTopologyGenerator` | |
| `spec/splice_topology/topology_splicer_spec.rb` | `TopologySplicer` | bgp_as/bgp_proc/layer3 複合 fixture が必要 |

**Tier 2（Netomox オブジェクト経由）**

| スペックファイル | 対象クラス | 備考 |
|---|---|---|
| `spec/nw_subsets/network_sets_spec.rb` | `NetworkSets` | fixture JSON → `DisconnectedVerifiableNetworks` 経由 |
| `spec/topology_ops/topology_ops_commander_spec.rb` | `TopologyOpsCommander` | |
| `spec/topology_ops/link_ops_commander_spec.rb` | `LinkOpsCommander` | |
| `spec/topology_ops/shut_ops_commander_spec.rb` | `ShutOpsCommander` | |

**Tier 3（`rest_api` モック必要）**

| スペックファイル | 対象クラス | モックポイント |
|---|---|---|
| `spec/nw_subsets/network_sets_diff_spec.rb` | `NetworkSetsDiff` | `fetch_topology_data` x2 |
| `spec/reach_test/reach_pattern_handler_spec.rb` | `ReachPatternHandler` | `fetch_networks` 等 + `exit 1` 対策 |

#### 不足フィクスチャ

- `TopologySplicer` 用: `bgp_as`・`bgp_proc`・`layer3` 層を含む複合 topology JSON
- `TopologyOpsCommander` 系: link/shut 操作を持つ topology JSON（既存の `minimal_layer3_topology.json` で一部対応可）

#### CI 動作確認

push 後に GitHub Actions で `lint` → `test` → `build_and_push` が順に green になることを確認する。

## 成果物一覧

| ファイル | 種別 |
|---|---|
| `docs/testing.md` | この計画書（戦略・構造の説明） |
| `Gemfile` | `group :test` 追加 |
| `Gemfile.lock` | lock 更新 |
| `Dockerfile` | `bundle config set --local without 'test'` 追加 |
| `Rakefile` | `:spec` タスク追加 |
| `.rspec` | 新規作成 |
| `.rubocop.yml` | spec/ の `Metrics/BlockLength` 除外追加 |
| `spec/spec_helper.rb` | 新規作成 |
| `spec/support/rest_api_helpers.rb` | 新規作成 |
| `spec/support/topology_fixtures.rb` | 新規作成 |
| `spec/fixtures/*.json` | フィクスチャ 3 ファイル新規作成 |
| `spec/**/*_spec.rb` | Tier 1 → 2 → 3 の順に追加 |
| `.github/workflows/actions.yaml` | lint + test ジョブ追加、build を gates |
