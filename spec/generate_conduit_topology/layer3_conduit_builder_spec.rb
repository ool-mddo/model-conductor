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
