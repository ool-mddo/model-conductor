# Plan: conduit topology で layer3 TP の `fhrp` 属性を扱う

(状態: 実装済み (ブランチ `v1.18.0-dev`)。netomox v0.14.0 の公開後、Gemfile の制約を `>= 0.14.0` に引き上げ済み)

### 実装結果

- 追加: `lib/generate_conduit_topology/fhrp_gateway_resolver.rb` (`FhrpGatewayResolver`)
  - `edge_tps(conduit_name)` / `find_edge_tp` (Router グループの unlinked + `fhrp` の TP を、冗長維持可否と代表選択で解決)、
    `maintained_fhrp(node, tp)` (外部 TP が引き継ぐ `fhrp`。冗長を維持できる場合のみ)
- 変更: `lib/generate_conduit_topology/layer3_conduit_builder.rb`
  (`build_fhrp_resolver`、`assign_fhrp_edge_tp_mappings` (外部 TP の連番に続けて tp_mapping へ追加)、
  `build_router_conduit_tp` / `build_conduit_tp` (`fhrp` は空のときキーを付けない))
- fixture / helper: `spec/fixtures/layer3_fhrp_topology.json`, `spec/support/fhrp_conduit_helpers.rb`
- spec 追加 (42 examples): `fhrp_gateway_resolver_spec.rb`, `layer3_conduit_builder_fhrp_spec.rb`, `router_node_attr_merger_fhrp_spec.rb`,
  `ospf_conduit_builder_fhrp_spec.rb`, `conduit_topology_generator_fhrp_spec.rb`
- docs 更新: `CLAUDE.md` (土管化ルール、conduit TP 属性は新規構築される旨)、`docs/testing.md`、playground の `docs/architecture.md`
- 確認:
  - `RUBYLIB=/home/hagiwara/ool-mddo/netomox/lib bundle exec rspec` → 102 examples, 0 failures (従来 60 + 42)。rubocop 違反なし。
    `layer3_conduit_builder.rb` を元に戻すと新 spec が 13 件失敗する (spec が変更を検知する)。
  - 実環境 `21_generate_conduit.sh`: blueprint1 は実行前と同一、blueprint2 は旧 builder で作った出力と同一
    (cr を含まないので差分なし。全 6 snapshot で確認)。
  - 実データ (`original_asis`) と in-memory の blueprint で `ConduitTopologyGenerator` を直接実行 (コンテナ内。ファイル追加なし):
    - cr-1 / cr-2 を別 conduit ノード: 各ノードに `eth3` (192.168.100.x/24, vrrp g1 priority 150 / 100) と `eth4` (192.168.200.x/24, g2) が `fhrp` 付きで残る。
    - cr-1 + cr-2 を 1 ノードに畳む: `eth3` = `192.168.100.1/24`、`eth4` = `192.168.200.1/24` (VIP)、`fhrp` なし。
- 実装中の判断: 1 つの TP が冗長を維持できるグループとできないグループの両方を持つ場合は、維持できるグループの `fhrp` と元の IP を残し、
  維持できないグループは落とす (警告ログ)。現行データには該当なし。

playground の `docs/work/plans/fhrp_termination_point_attributes.md` の Phase E に相当する。全体計画・データモデルはそちらを参照。
この文書は model-conductor 側の実装範囲を扱う。

## 目的

`mddo-topology:l3-termination-point-attributes` の `fhrp` (VRRP/HSRP) が、model-conductor の topology 操作
(特に conduit topology 生成。splice 等) で取りこぼされないようにする。
スコープは `emulated_asis[_conduit]` トポロジの生成まで (fhrp から config を生成する処理は次フェーズ)。

## 前提 (リポジトリ状態)

- ブランチ: `v1.17.2-dev` (`581e307`、`origin/v1.17.2-dev` と同期) から **`v1.18.0-dev`** を作成済み。
- 依存: netomox gem は `Gemfile` で `>= 0.13.0`。fhrp 対応は netomox `v0.14.0-dev` (未公開)。
  ローカルでは playground の `docker-compose.override.yaml` が model-conductor コンテナにローカル netomox を bind mount している。
- ローカルの spec 実行 (現状 **60 examples, 0 failures**):
  `RUBYLIB=/home/hagiwara/ool-mddo/netomox/lib bundle exec rspec` (`Gemfile.lock` は git 管理外、`.rspec` あり)
- CI/Gemfile の制約引き上げは、netomox 公開後にまとめて行う方針 (netomox-exp と同じ)。

## 調査結果

### 1. fhrp が落ちる箇所と落ちない箇所

| 箇所 | 挙動 | fhrp |
|---|---|---|
| `Layer3ConduitBuilder#build_fw_conduit_nodes` (Firewall グループ) | 元 TP の `L3_TP_ATTR` を `.dup` して全 TP を保持 | **保持される** (変更不要。spec で固定する) |
| `Layer3ConduitBuilder#build_router_conduit_tp` (Router グループ) | `{ 'ip-address' => ..., 'flag' => [] }` を**新規構築** | **落ちる** (L218) |
| `Layer3ConduitBuilder#build_router_tp_mapping` | 外部セグメントに接続する TP のみ tp_mapping に入れて `eth1, eth2, ...` に rename | 後述の通り **VRRP の TP そのものが対象外** |
| `Layer3ConduitBuilder#build_segment_node` (セグメント TP) | `L3_TP_ATTR => {}` | 対象外 (セグメント TP に fhrp は無い) |
| `RouterNodeAttrMerger` | ノード属性 (prefix / static-route) の集約。TP 属性は扱わない | 影響なし |
| `OspfConduitBuilder` | ospf_area の TP を tp_mapping で引いて変換。fhrp は layer3 のみ | 影響なし (後述の注意あり) |
| `TopologySplicer` / `netomox_patch.rb` (外部 AS の splice) | netomox のオブジェクトを `to_data` 経由で扱い、TP 属性の再構築はしない。`ip_addrs` を読むだけ | 影響なし (netomox 0.14.0 が保持) |
| その他 (`generate_candidate_topologies`, `topology_ops`, `nw_subsets` 等) | `grep` で `L3_TP_ATTR` / `ip-address` / `ip_addrs` を TP 属性として再構築する箇所は conduit builder・merger・splicer のみ | 影響なし (spec / 実環境で確認) |

### 2. 重要な発見: 現行データでは VRRP の TP は conduit の対象外になる

- **現行の blueprint (`original_asis_blueprint1` / `blueprint2`) には cr ノード (VRRP を持つ) が含まれない**。
  blueprint に無いノードは conduit から除外される (`find_external_segments` が除外)。
  → 現状の conduit topology に `fhrp` が無いのは、cr ノード自体が出力に無いため。
- **cr ノードの VRRP の TP は、どのセグメントにも接続していない (unlinked TP)**。
  実データ (`topologies/mddo-fw/original_asis`) の `site-a-cr-1`:
  `ge-0/0/0.0` と `ge-0/0/1.0` は `Seg_*` にリンクがあるが、`fhrp` を持つ `ge-0/0/2.0` (192.168.100.2/24) と
  `ge-0/0/3.0` (192.168.200.2/24) は**リンクが 1 本も無い** (LAN 側でホストが未モデル化の TP は
  netomox-exp が「unlinked な IP 持ち TP」として追加する)。
- Router グループの conduit は「外部セグメント (他グループとの間のセグメント) に接続する TP だけ」を `eth1, eth2, ...` として残す。
  したがって、cr ノードを Router グループとして blueprint に入れても、`fhrp` を持つ TP は**外部セグメントに無いので conduit ノードに残らない**。
  `build_router_conduit_tp` で `fhrp` を引き継ぐだけでは、この TP 自体が無いため不十分。

→ **conduit で fhrp を扱うには、Router グループが fhrp を持つ unlinked TP を残すルールの追加が必要**。これは conduit の抽象化ルール
(土管化ルール) の変更で、下記「決定済み事項」のルール (冗長を維持できるか否かで `fhrp` を残す/VIP に置き換える) に従う。

### 3. 注意点

- `OspfConduitBuilder#parse_seg_tp` は ospf の Seg TP 名 (`{orig_node}_{orig_tp}`) を tp_mapping への逆引きで解決する。
  tp_mapping にエントリが増えると、TP 名に `_` を含む場合の曖昧性の可能性が(理論上)広がる。現行データでは fhrp TP の名前は `ge-0/0/2.0` 形式で問題なし。
- `Layer3ConduitBuilder` は `tp_mapping` の `[node, tp]` を ospf 側でも使う。fhrp TP は ospf_area に現れないので、tp_mapping に足しても ospf 出力は変わらない想定 (spec で確認する)。
- VRRP の組 (cr-1 / cr-2) を 1 つの Router グループに畳むと、同じ conduit ノード上に同じ VIP・同じ group-id の TP が 2 つできる
  (例: eth? = cr-1 の `ge-0/0/2.0` 150、eth? = cr-2 の `ge-0/0/2.0` 100)。これは冗長化の相手が同一ノード内に入る形になるので、
  → 決定済みルールでは、この場合は冗長を維持できないとして 1 TP に集約し、IP を VIP に置き換える。

## 決定済み事項 (2026-10-11)

- **D3:** blueprint (cr を含むもの) の作成は後回しにする。`usecases/` 配下に blueprint は追加しない。
  実環境での確認は、既存 blueprint1/blueprint2 の出力が変わらないこと (回帰) と、blueprint ファイルを作らずに
  in-memory の blueprint で `ConduitTopologyGenerator` を直接実行する確認にとどめる (「動作確認」参照)。
- **D1/D2:** 現在の blueprint は cr を含まないので、VRRP を持つインタフェースは conduit に残らない (現状のまま)。
  blueprint に cr を含めて conduit を作る場合の、セグメントのゲートウェイとなるインタフェースの扱いを次のルールとする
  (目的: **エッジセグメントのエンドポイントのデフォルトゲートウェイ設定が変わらないこと**):
  1. **冗長を維持できる場合:** `fhrp` 設定をそのまま残す。
  2. **冗長を維持できない場合:** `fhrp` 設定は残さず、そのインタフェースの IP アドレスを **fhrp の VIP (virtual-address)** にする
     (エンドポイントから見たゲートウェイ IP が変わらない)。

### ルールの具体化 (D4 の回答を反映)

対象は Router グループのメンバーの、`fhrp` を持つ TP。FHRP のグループは `(protocol, group-id, virtual-address)` で識別する。

- **冗長を維持できる** = そのグループのメンバー TP が、**blueprint に含まれるノード**の範囲で**2 つ以上の異なる conduit ノード**に属する。
  - conduit ノード = Router グループは集約後の conduit ノード、Firewall グループは元ノードそのもの。
  - blueprint に含まれないノード (conduit から除外されるノード) のメンバーは数えない。
    (例: cr-1 だけが blueprint に含まれ cr-2 が無い場合は、冗長を維持できない)
  - 例: cr-1 と cr-2 を別々の Router グループにすれば維持できる。同じ Router グループに畳めば維持できない。
- **1 conduit ノード・1 FHRP グループにつき TP は 1 つだけ**残す。
  同じ conduit ノードに同じグループのメンバー TP が複数ある (畳んだ) 場合は、**Master/Active に選ばれるメンバー (priority 最大、同値なら source-address 最大)** の TP を代表とする
  (選び方は下記「代表 TP の選び方」)。それ以外のメンバー TP は残さない。
- 維持できる場合: 代表 TP を `ethN+1...` (外部 TP の連番に続く) として残し、`ip-address` と `fhrp` (`protocol`, `group-id`,
  `virtual-address`, `priority`, `preempt`, `source-address`, `active`) を元 TP のまま引き継ぐ。`flag` は `[]`。
- 維持できない場合: 代表 TP を同様に残すが、`ip-address` は **VIP を `virtual-address` の各要素 + `source-address` のプレフィックス長**
  (例: `192.168.100.1` + `192.168.100.2/24` → `192.168.100.1/24`) に置き換え、**`fhrp` は付けない**。
  - `source-address` が無い/不正、または VIP と `source-address` のアドレスファミリが違う場合は、その VIP を変換しない (ログ警告)。
- リンク・セグメントは作らない (これらの TP は元から unlinked のため)。

### 代表 TP の選び方 (D4-2。プロトコル仕様の調査結果)

「最も優先度の高いもの」= そのグループで実際に Master (VRRP) / Active (HSRP) に選ばれるメンバーとする。調査結果:

| 項目 | VRRP (RFC 5798) | HSRP (Cisco) |
|---|---|---|
| 選出 | priority が**高い**方が Master (§6.4.3) | priority が**高い**方が Active |
| 同値のとき | **primary IP アドレスが大きい**方が Master (§6.4.3 step 735。primary address はインタフェース自身の実 IP: §1.6) | **インタフェースの IP アドレスが大きい**方が Active |
| 既定値 | 100 | 100 |
| 特殊値 | **255 = 仮想 IP の所有者 (address owner)**。常に Master (§5.2.4, §6.4.1)。**0 = Master の責任放棄** (バックアップが即座に引き継ぐ。§5.2.4, §6.1) | (特別な値の意味はプロトコルとしては無い。0〜255) |
| preempt | preempt 無効だと、起動順で Master/Active が決まりうる (実行時の状態) | preempt を設定しないと、priority が高くても既存の Active を奪わない (実行時の状態) |

→ **両プロトコルとも「priority が大きい方、同値なら source-address (インタフェースの実 IP) が数値として大きい方」で共通**。違いは VRRP の特殊値だけで、
255 は最大値、0 は最小値として扱えば同じ比較で正しく選べる (255 = VIP の所有者が最優先、0 = 責任放棄で最後)。
グループは `(protocol, group-id, virtual-address)` で識別するので、VRRP と HSRP が混ざることはない。

- 比較キー: `[priority (Integer), source-address のアドレス部 (IPAddr として数値比較)]` の降順で最大のメンバー。
  `source-address` が無い/不正なものは IP 比較で最小として扱う。完全に同値の場合は、グループ内メンバー順 (代表ノード → 他メンバー)、TP 名順で先のもの。
- `preempt` / `active` による実行時の状態 (起動順・障害) は静的な設定からは決められないので考慮しない。設定上の Master を代表とする。
- `priority 0` のメンバーしか残らない場合も、そのグループの代表として扱う (VIP を引き継ぐため)。

### D4: 回答

1. 外部 TP が `fhrp` を持つ場合は推奨どおり。VIP への置き換えと 1 グループ 1 TP への集約は **unlinked TP (エッジ)** にだけ適用する。
   外部 TP は IP をそのまま維持し、冗長を維持できる場合は `fhrp` を引き継ぎ、維持できない場合は `fhrp` を落とす。
2. 代表 TP は上記のプロトコル仕様に基づき選ぶ。
3. Firewall グループは現行のまま (全 TP を属性ごと保持)。`fhrp` を引き継ぐだけで、パートナーが blueprint に無くても VIP への置き換えはしない。

(以下は議論時の確認事項。回答済み)

1. **外部 TP (他グループとのセグメントに接続している TP) が `fhrp` を持つ場合**: エッジではなくグループ間リンク上の VRRP。
   - 推奨: 外部 TP は **IP を VIP に置き換えない** (隣接ルータが実 IP でピアリング/OSPF 隣接を張るため)。
     冗長を維持できる場合は `fhrp` を引き継ぎ、維持できない場合は `fhrp` を落として元の IP のままにする。
     VIP への置き換えと「1 グループ 1 TP」への集約は、**unlinked TP (エッジ) にだけ**適用する。
   - 現行データには該当する TP が無い (cr の VRRP TP は全て unlinked) ので、仕様を固定するテストを置くだけで、実データには影響しない。
2. **代表 TP の選び方**: 「priority 最大」でよいか (VIP を持つ側は実運用では active なメンバー。`active` や priority が最大の方)。
3. **Firewall グループ (元ノードをそのまま保持) の `fhrp`**: 現行の「全 TP をそのまま保持」のまま変更しない (Firewall に VRRP がある場合も `fhrp` を引き継ぐだけ。
   パートナーが blueprint に無い場合の VIP 置き換えは行わない)。それでよいか。

## 実装内容

### 1. `Layer3ConduitBuilder` ([layer3_conduit_builder.rb](../../lib/generate_conduit_topology/layer3_conduit_builder.rb))

fhrp の判定が絡むため、tp_mapping の構築 (`build_router_tp_mapping`) と TP 属性の構築 (`build_router_conduit_tp`) の両方に手を入れる。
ロジックが増えるので **新クラスに切り出す**:

- 新規 `lib/generate_conduit_topology/fhrp_gateway_resolver.rb` (`FhrpGatewayResolver`):
  - 入力: 元の layer3 ノード群、`node_mapping` (元ノード → conduit ノード。blueprint に含まれるノードのみ)、Router グループの定義、
    外部 TP の tp_mapping (どの TP が外部か判定するため)。
  - `resolve` → Router グループの unlinked な fhrp TP について、`{ [orig_node, orig_tp] => { redundant: true|false, fhrp: [...], ip_addrs: [...] } }`
    の形で、**残す代表 TP とその conduit 属性** を返す。
    - 1) fhrp TP を `(protocol, group-id, virtual-address)` ごとに集め、メンバーの conduit ノードを数えて冗長可否を判定
    - 2) conduit ノードごとに代表 (priority 最大、同値なら source-address 最大) を選ぶ
    - 3) 可なら `fhrp` 引き継ぎ、不可なら VIP + プレフィックス長に変換
- `Layer3ConduitBuilder`:
  - `build_router_tp_mapping`: 外部 TP の割り当て後に、resolver が返した代表 TP へ続き番号 (`eth` カウンタを共用) を割り当てて tp_mapping に追加。
    非代表メンバーの TP は tp_mapping に入れない。
  - `build_router_conduit_tp`: 外部 TP: 元 TP の `fhrp` を deep copy で引き継ぐ (維持できる場合) / 落とす (維持できない場合)。
    resolver が返した代表 TP: resolver の結果 (`ip_addrs` と `fhrp`) を属性にする。`fhrp` が空なら `fhrp` キーを付けない。
  - ファイル冒頭のルールのコメントを更新。
- `RouterNodeAttrMerger` は変更なし。代表 TP が tp_mapping にあり、その元 TP の IP (実 IP) から connected prefix を作る。
  VIP と実 IP は同じサブネットなので、prefix は一致する (spec で確認)。非代表メンバーの TP の prefix も、代表 TP と同じサブネットなので重複排除で 1 つに集約される。
- `OspfConduitBuilder`, `ConduitTopologyGenerator`, `TopologySplicer`: 変更なし。

### 2. 現行 blueprint (cr を含まない) への影響

fhrp TP を持つノードが blueprint に含まれないため、tp_mapping・conduit ノードともに従来と同一 (差分なし) となるはず。実環境の回帰確認と spec で固定する。

## テスト計画

既存の方針 (`docs/testing.md`: Tier 1、`spec/fixtures` に手書き fixture、機能ごとの専用ファイル) に合わせる。

### fixture

- 新規 `spec/fixtures/layer3_fhrp_topology.json` (手書き。最小構成)
  - Router `cr1`, `cr2` (VRRP ペア: 同じ VIP 192.168.100.1、priority 150 / 100、LAN 側の unlinked TP `ge-0/0/2.0` に `fhrp`。外部セグメントで `fw1` へ接続)。
  - Router `cr3` (別グループ用。冗長ペアの 3 つ目 `cr1`/`cr3` を別グループにするケースに使う)。
  - Firewall `fw1` (flag: firewall。TP の 1 つに `fhrp`)。
  - `fhrp` を持たない unlinked TP (従来どおり除外されることの確認)、外部 TP に `fhrp` を持たせたもの (D4-1 の固定)。
- blueprint は spec 内でハッシュを組み立てる (ケースごとに畳み方を変えるため、blueprint fixture ファイルは作らない)。
- 既存 fixture (`minimal_layer3_topology.json`, `blueprint_topology.json`) は変更しない。

### spec

| ファイル | 内容 |
|---|---|
| `spec/generate_conduit_topology/fhrp_gateway_resolver_spec.rb` | resolver の単体 (代表の選び方を含む): (0) 代表: priority が大きい方、同値なら source-address が数値として大きい方 (例: `192.168.100.10` > `192.168.100.9` を文字列比較で誤らない)、VRRP の 255 (VIP 所有者) が最優先・0 が最後、完全に同値ならメンバー順、source-address が無いものは IP 比較で最小。(1) cr1 と cr2 が別 conduit ノード → 冗長維持 (`fhrp` を引き継ぎ)。(2) 同じ conduit ノードに畳む → 冗長不可 (VIP + プレフィックス長、`fhrp` 無し、代表は priority 最大 = cr1)。(3) cr2 が blueprint に無い → 冗長不可。(4) priority 同値のときの代表 (source-address の大きい方)。(5) 3 メンバーのうち 2 つを畳み 1 つが別ノード → 維持でき、畳んだノードは代表 1 TP。(6) `virtual-address` が複数のとき全て VIP 化。(7) `source-address` が無い/ファミリ不一致の VIP は変換しない。(8) `fhrp` を持たない TP は対象外。 |
| `spec/generate_conduit_topology/layer3_conduit_builder_fhrp_spec.rb` | builder の結果: (1) Firewall グループの `fhrp` が保持される。(2) 冗長維持のケースで各 conduit ノードに代表 TP (`ethN+1`) が `ip-address`(実 IP) と `fhrp` 付きで残る。(3) 冗長不可 (畳んだ) のケースで conduit ノードに VIP の TP が 1 つだけ残り、`fhrp` キーが無い。(4) 非代表メンバーの TP が残らず tp_mapping にも無い。(5) 外部 TP が `fhrp` を持つ場合の扱い (D4-1)。(6) `fhrp` の無い unlinked TP は従来どおり残らない。(7) 追加 TP にセグメントノード・リンクが作られない。(8) 引き継いだ `fhrp` は deep copy。(9) `fhrp` 無しの従来 fixture では出力が従来と同一。 |
| `spec/generate_conduit_topology/router_node_attr_merger_fhrp_spec.rb` | 代表 TP の実 IP から connected prefix が conduit ノードの prefix に残り、非代表 TP と重複しない。 |
| `spec/generate_conduit_topology/ospf_conduit_builder_fhrp_spec.rb` | tp_mapping に fhrp TP が追加されても ospf_area conduit の出力が変わらない。 |
| `spec/generate_conduit_topology/conduit_topology_generator_fhrp_spec.rb` | `ConduitTopologyGenerator#generate` の出力を `Netomox::Topology::Networks` でパースでき、維持ケースで conduit TP に `MddoFhrp` が取れる (netomox 0.14.0 との結合)。 |
| 既存 spec | 変更しない。全て通ること。 |

実行:

```bash
cd /home/hagiwara/ool-mddo/playground/repos/model-conductor
RUBYLIB=/home/hagiwara/ool-mddo/netomox/lib bundle exec rspec
RUBYLIB=/home/hagiwara/ool-mddo/netomox/lib bundle exec rake rubocop
```

## 動作確認 (実環境)

blueprint ファイルは作らない (D3)。

1. **回帰:** `cd demo/candidate_model_ops && source demo_vars && ./21_generate_conduit.sh` (blueprint1) と `-b original_asis_blueprint2`。
   `topologies/mddo-fw/original_asis_conduit*` / `emulated_asis_conduit*` が、実行前と同一であること (cr が含まれないので差分なし)。
2. **cr を含む場合の実データ確認:** スクラッチパッドのスクリプトで、実データ `topologies/mddo-fw/original_asis/topology.json` と
   **in-memory の blueprint** (cr-1/cr-2 を別グループ / 同一グループにしたもの) から `ConduitTopologyGenerator#generate` を直接実行し、
   (a) 別グループ: 各 conduit ノードに `fhrp` 付きの TP (priority 150 / 100) が残る、
   (b) 同一グループ: conduit ノードに VIP (`192.168.100.1/24` / `192.168.200.1/24`) の TP が 1 つずつ残り `fhrp` が無い
   ことを確認する。コンテナ内 (ローカル netomox を bind mount 済み) で実行し、リポジトリ・usecases にはファイルを追加しない。

## ドキュメント修正の調査結果

| ファイル | 要否 | 内容 |
|---|---|---|
| model-conductor `CLAUDE.md` | **要修正** | 「土管化ルール」: Router ノードの記述に、`fhrp` を持つ unlinked TP の扱い (冗長を維持できれば `fhrp` を残す、できなければ 1 TP に集約して IP を VIP にする) と `FhrpGatewayResolver` を追記 (FW ノードは `fhrp` を含め属性をそのまま保持)。「ConduitTopologyGenerator の土管化ロジック」のファイル一覧に `fhrp_gateway_resolver.rb` を追加。「Critical Constraints」に、`build_router_conduit_tp` が TP 属性を新規構築するので新しい TP 属性を追加する際はここも更新する旨を追記。 |
| model-conductor `docs/testing.md` | **要追記** | fixture 一覧 (`layer3_fhrp_topology.json` 等) と spec 一覧に新規ファイルを追記。(なお、`conduit_topology_generator_spec.rb` が一覧にあるが実ファイルは無い。今回追加する `conduit_topology_generator_fhrp_spec.rb` とは別で、この不一致の扱いは別途判断) |
| model-conductor `docs/architecture.md` | 不要 | conduit の説明が無い。TP 属性の記述も無い |
| model-conductor `README.md` | 不要 | conduit / TP の記述なし |
| playground `docs/architecture.md` (L265 付近) | **要修正** | フロー 5 の conduit の説明「外部 TP のみ eth1, eth2, ... に rename」に、`fhrp` を持つ unlinked TP の扱い (冗長を維持できれば `fhrp` を残す、できなければ VIP を IP にして `fhrp` は無し) を追記 |
| playground `demo/candidate_model_ops/README_refocus_topology.md` | 要確認 | conduit の TP ルールの記述が無ければ不要 |
| playground `usecases/refocus_topology/README.md` | 不要 | blueprint のフォーマットのみ (blueprint の追加は後回し) |
| playground `docs/work/plans/fhrp_termination_point_attributes.md` | 要更新 | Phase E の結果と決定 (D1〜D4) を反映 |
| YARD (`doc/`) | 不要 | 自動生成物。新規・変更メソッドに YARD コメントを付ける |

## 実装ステップ (順序)

1. (済) D1〜D4 の回答を受けて本計画を更新。
2. fixture と spec を先に書く (現行コードで fhrp 関連が落ちることを確認)。
3. `FhrpGatewayResolver` を実装 → `fhrp_gateway_resolver_spec.rb` を通す。
4. `Layer3ConduitBuilder` に組み込み → builder / merger / ospf / generator の spec を通す。
5. 全 rspec / rubocop (`RUBYLIB` でローカル netomox)。
6. 実環境確認: blueprint1/blueprint2 の回帰、in-memory blueprint での確認。
7. ドキュメント更新 (CLAUDE.md、testing.md、playground の architecture.md と計画)。
8. コミット (Gemfile の制約引き上げ・CI は netomox 公開時)。
