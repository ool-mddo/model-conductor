# frozen_string_literal: true

require_relative '../../lib/generate_conduit_topology/blueprint_network'
require_relative '../../lib/generate_conduit_topology/layer3_conduit_builder'

RSpec.describe ModelConductor::Layer3ConduitBuilder do
  let(:original_layer3) do
    load_fixture('minimal_layer3_topology.json').dig('ietf-network:networks', 'network', 0)
  end
  let(:bp_networks) do
    load_fixture('blueprint_topology.json').dig('ietf-network:networks', 'network')
  end
  let(:blueprint_nw) { ModelConductor::BlueprintNetwork.new(bp_networks.first, bp_networks) }

  subject(:builder) { described_class.new(original_layer3, blueprint_nw) }

  describe '#build' do
    let(:result) { builder.build }
    let(:conduit_layer3) { result[0] }
    let(:node_mapping) { result[1] }
    let(:tp_mapping) { result[2] }

    it 'returns an array of three elements [conduit_layer3, node_mapping, tp_mapping]' do
      expect(result.length).to eq(3)
    end

    it 'conduit_layer3 has network-id "layer3"' do
      expect(conduit_layer3['network-id']).to eq('layer3')
    end

    it 'maps original node names to conduit node names' do
      expect(node_mapping['router1']).to eq('conduit_r1')
      expect(node_mapping['router2']).to eq('conduit_r2')
    end

    it 'includes conduit nodes for each blueprint group' do
      node_ids = (conduit_layer3['node'] || []).map { |n| n['node-id'] }
      expect(node_ids).to include('conduit_r1', 'conduit_r2')
    end

    it 'generates a segment node for the cross-group segment' do
      node_ids = (conduit_layer3['node'] || []).map { |n| n['node-id'] }
      expect(node_ids).to include('Seg_10.0.0.0/30')
    end

    it 'generates links connecting conduit nodes to the segment' do
      links = conduit_layer3['ietf-network-topology:link'] || []
      expect(links).not_to be_empty
    end

    it 'tp_mapping contains entries for external TPs' do
      expect(tp_mapping).not_to be_empty
      expect(tp_mapping.values.map(&:first)).to include('conduit_r1', 'conduit_r2')
    end
  end

  describe '#build term-point description' do
    let(:conduit_layer3) { builder.build[0] }
    let(:links) { conduit_layer3['ietf-network-topology:link'] }
    let(:tp_key) { 'ietf-network-topology:termination-point' }
    let(:attr_key) { 'mddo-topology:l3-termination-point-attributes' }

    def expected_description(node_id, tp_id)
      seg_link = links.find { |l| l['source'].values == [node_id, tp_id] }
      return nil if seg_link.nil?

      facing_via_segment(seg_link['destination']['dest-node'], node_id)
    end

    def facing_via_segment(segment_name, self_node_id)
      peer = links.find do |l|
        l['source']['source-node'] == segment_name && l['destination']['dest-node'] != self_node_id
      end
      "to_#{peer['destination'].values.join('_')}"
    end

    # every description must match the facing node/tp (across the segment) in the conduit topology
    it 'is consistent with the links for all term-points of non-segment nodes' do
      nodes = conduit_layer3['node'].reject { |n| n['node-id'].start_with?('Seg_') }
      nodes.each do |n|
        n[tp_key].each do |tp|
          expect(tp.dig(attr_key, 'description')).to eq(expected_description(n['node-id'], tp['tp-id']))
        end
      end
    end

    it 'sets segment term-point description' do
      seg = conduit_layer3['node'].find { |n| n['node-id'] == 'Seg_10.0.0.0/30' }
      descs = seg[tp_key].map { |tp| tp.dig(attr_key, 'description') }
      expect(descs).to contain_exactly('to_conduit_r1_eth0', 'to_conduit_r2_eth0')
    end
  end

  describe '#build term-point description with a firewall cluster pair' do
    let(:tp_key) { 'ietf-network-topology:termination-point' }
    let(:attr_key) { 'mddo-topology:l3-termination-point-attributes' }
    let(:node_attr_key) { 'mddo-topology:l3-node-attributes' }
    let(:pair) { { 'primary' => { 'name' => 'fw1' }, 'secondary' => { 'name' => 'fw2' } } }

    def tp(tp_id, description: nil)
      attrs = { 'ip-address' => ['10.0.0.1/30'], 'flag' => [] }
      attrs['description'] = description if description
      { 'tp-id' => tp_id, attr_key => attrs }
    end

    def fw_node(node_id)
      { 'node-id' => node_id, 'flag' => ['firewall'],
        node_attr_key => { 'node-type' => 'node', 'firewall' => { 'node' => node_id, 'pair' => pair } },
        tp_key => [tp('ge-0/0/1.0', description: 'to_old_a'), tp('ge-7/0/1.0', description: 'to_old_b'),
                   tp('ge-0/0/2.0', description: 'to_removed_c')] }
    end

    def router_node(node_id, tp_ids)
      { 'node-id' => node_id, node_attr_key => { 'node-type' => 'node' }, tp_key => tp_ids.map { |id| tp(id) } }
    end

    def segment_node(seg_id, tp_ids)
      { 'node-id' => seg_id, node_attr_key => { 'node-type' => 'segment' }, tp_key => tp_ids.map { |id| tp(id) } }
    end

    def links_between(seg, node, node_tp)
      [['source', seg, "#{node}_#{node_tp}", node, node_tp], ['dest', node, node_tp, seg, "#{node}_#{node_tp}"]]
        .map do |_, sn, st, dn, dt|
        { 'link-id' => "#{sn},#{st},#{dn},#{dt}", 'source' => { 'source-node' => sn, 'source-tp' => st },
          'destination' => { 'dest-node' => dn, 'dest-tp' => dt } }
      end
    end

    # r1 -- (Seg_a) -- fw1[ge-0/0/1.0], r1 -- (Seg_b) -- fw2[ge-7/0/1.0]; the other term-points of fw1/fw2 have no link
    let(:fw_nodes) do
      [router_node('r1', %w[eth0 eth1]), fw_node('fw1'), fw_node('fw2'),
       segment_node('Seg_a', %w[r1_eth0 fw1_ge-0/0/1.0]), segment_node('Seg_b', %w[r1_eth1 fw2_ge-7/0/1.0])]
    end
    let(:fw_links) do
      [%w[Seg_a r1 eth0], %w[Seg_a fw1 ge-0/0/1.0], %w[Seg_b r1 eth1], %w[Seg_b fw2 ge-7/0/1.0]]
        .flat_map { |seg, node, node_tp| links_between(seg, node, node_tp) }
    end
    let(:fw_layer3) { { 'network-id' => 'layer3', 'node' => fw_nodes, 'ietf-network-topology:link' => fw_links } }
    let(:fw_blueprint) do
      groups = %w[r1 fw1 fw2].map do |n|
        { 'node-id' => "c_#{n}", 'supports' => [{ 'network-ref' => 'layer3', 'node-ref' => n }] }
      end
      [{ 'network-id' => 'zoom0', 'node' => groups }]
    end
    let(:conduit_layer3) do
      blueprint = ModelConductor::BlueprintNetwork.new(fw_blueprint.first, fw_blueprint)
      described_class.new(fw_layer3, blueprint).build[0]
    end

    def description_of(node_id, tp_id)
      node = conduit_layer3['node'].find { |n| n['node-id'] == node_id }
      node[tp_key].find { |t| t['tp-id'] == tp_id }.dig(attr_key, 'description')
    end

    it 'points the router and firewall term-points at the facing node (not the segment)' do
      expect(description_of('c_r1', 'eth0')).to eq('to_fw1_ge-0/0/1.0')
      expect(description_of('fw1', 'ge-0/0/1.0')).to eq('to_c_r1_eth0')
    end

    it 'makes the descriptions of the cluster pair the same (including term-points without link)' do
      expect(description_of('fw2', 'ge-0/0/1.0')).to eq(description_of('fw1', 'ge-0/0/1.0'))
      expect(description_of('fw1', 'ge-7/0/1.0')).to eq(description_of('fw2', 'ge-7/0/1.0'))
      expect(description_of('fw1', 'ge-7/0/1.0')).to eq('to_c_r1_eth1')
    end

    it 'removes stale descriptions of term-points that lost their facing node' do
      expect(description_of('fw1', 'ge-0/0/2.0')).to be_nil
      expect(description_of('fw2', 'ge-0/0/2.0')).to be_nil
    end
  end

  describe '#build with nodes not defined in the blueprint' do
    # router3 is not in the blueprint: add it to a 3-party segment (Seg_10.0.0.0/30) and a 2-party segment
    let(:layer3_with_extra) do
      nw = Marshal.load(Marshal.dump(original_layer3))
      tp_key = 'ietf-network-topology:termination-point'
      link_key = 'ietf-network-topology:link'
      nw['node'] << { 'node-id' => 'router3', tp_key => [{ 'tp-id' => 'eth0' }, { 'tp-id' => 'eth1' }] }
      nw['node'].find { |n| n['node-id'] == 'Seg_10.0.0.0/30' }[tp_key] << { 'tp-id' => 'router3_eth0' }
      nw['node'] << { 'node-id' => 'Seg_10.9.9.0/30',
                      tp_key => [{ 'tp-id' => 'router1_eth1' }, { 'tp-id' => 'router3_eth1' }] }
      nw[link_key] += [
        ['Seg_10.0.0.0/30', 'router3_eth0', 'router3', 'eth0'],
        ['Seg_10.9.9.0/30', 'router1_eth1', 'router1', 'eth1'],
        ['Seg_10.9.9.0/30', 'router3_eth1', 'router3', 'eth1']
      ].map do |sn, stp, dn, dtp|
        { 'link-id' => "#{sn},#{stp},#{dn},#{dtp}",
          'source' => { 'source-node' => sn, 'source-tp' => stp },
          'destination' => { 'dest-node' => dn, 'dest-tp' => dtp } }
      end
      nw
    end
    let(:result) { described_class.new(layer3_with_extra, blueprint_nw).build }
    let(:node_ids) { result[0]['node'].map { |n| n['node-id'] } }

    it 'does not raise' do
      expect { result }.not_to raise_error
    end

    it 'omits nodes not defined in the blueprint' do
      expect(node_ids).not_to include('router3')
      expect(result[1]).not_to have_key('router3')
    end

    it 'keeps a segment shared by blueprint nodes without the undefined endpoint' do
      seg = result[0]['node'].find { |n| n['node-id'] == 'Seg_10.0.0.0/30' }
      expect(seg['ietf-network-topology:termination-point'].size).to eq(2)
    end

    it 'omits a segment that has only one blueprint node endpoint' do
      expect(node_ids).not_to include('Seg_10.9.9.0/30')
    end
  end
end
