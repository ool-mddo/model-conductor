# frozen_string_literal: true

RSpec.describe ModelConductor::Layer3ConduitBuilder, 'with an endpoint on the fhrp segment' do
  let(:seg_name) { 'Seg_192.168.100.0/24' }
  let(:layer3) do
    nw = fhrp_layer3
    host_tp = { 'tp-id' => 'eth0', l3_attr => { 'ip-address' => %w[192.168.100.10/24] } }
    nw['node'] << { 'node-id' => 'host1', tp_key => [host_tp] }
    nw['node'] << { 'node-id' => seg_name, tp_key => (%w[cr1 cr2 cr3].map { |n| { 'tp-id' => "#{n}_ge-0/0/2.0" } } +
                                                    [{ 'tp-id' => 'host1_eth0' }]) }
    nw['ietf-network-topology:link'] += segment_links
    nw
  end
  let(:segment_links) do
    [%w[cr1 ge-0/0/2.0], %w[cr2 ge-0/0/2.0], %w[cr3 ge-0/0/2.0], %w[host1 eth0]].flat_map do |node, tp|
      [make_link(seg_name, "#{node}_#{tp}", node, tp), make_link(node, tp, seg_name, "#{node}_#{tp}")]
    end
  end
  let(:result) { build_conduit(layer3, groups) }
  let(:conduit_layer3) { result[0] }
  let(:tp_mapping) { result[2] }

  def make_link(src_node, src_tp, dst_node, dst_tp)
    { 'link-id' => "#{src_node},#{src_tp},#{dst_node},#{dst_tp}",
      'source' => { 'source-node' => src_node, 'source-tp' => src_tp },
      'destination' => { 'dest-node' => dst_node, 'dest-tp' => dst_tp } }
  end

  def segment_tp_ids
    conduit_node(conduit_layer3, seg_name)[tp_key].map { |tp| tp['tp-id'] }
  end

  context 'when the redundant gateways are collapsed into one conduit node (redundancy is not maintained)' do
    let(:groups) { { 'c_cr' => %w[cr1 cr2 cr3], 'fw1' => ['fw1'], 'host1' => ['host1'] } }

    it 'keeps one tp for the gateways with the virtual address and no fhrp' do
      tp = find_tp(conduit_layer3, 'c_cr', 'eth2')
      expect(tp[l3_attr]['ip-address']).to eq %w[192.168.100.1/24]
      expect(tp[l3_attr]).not_to have_key('fhrp')
      expect(conduit_tp_names(conduit_layer3, 'c_cr')).to eq %w[eth1 eth2]
    end

    it 'maps only the representative (the highest priority: cr1) and removes the others from the segment' do
      expect(tp_mapping[%w[cr1 ge-0/0/2.0]]).to eq %w[c_cr eth2]
      expect(tp_mapping).not_to have_key(%w[cr2 ge-0/0/2.0])
      expect(tp_mapping).not_to have_key(%w[cr3 ge-0/0/2.0])
      expect(segment_tp_ids).to eq %w[c_cr_eth2 host1_eth0]
    end

    it 'keeps the original tp name of the group of a single original node (endpoint)' do
      expect(conduit_tp_names(conduit_layer3, 'host1')).to eq %w[eth0]
      expect(tp_mapping[%w[host1 eth0]]).to eq %w[host1 eth0]
    end

    it 'describes the tps by the facing node (the segment has two endpoints)' do
      expect(find_tp(conduit_layer3, 'c_cr', 'eth2')[l3_attr]['description']).to eq 'to_host1_eth0'
      expect(find_tp(conduit_layer3, 'host1', 'eth0')[l3_attr]['description']).to eq 'to_c_cr_eth2'
    end
  end

  context 'when a part of the gateways is collapsed and the others are separate (redundancy is maintained)' do
    let(:groups) { { 'c_cr12' => %w[cr1 cr2], 'c_cr3' => ['cr3'], 'fw1' => ['fw1'], 'host1' => ['host1'] } }

    it 'keeps one tp with fhrp (the representative) in the collapsed node' do
      tp = find_tp(conduit_layer3, 'c_cr12', 'eth2')
      expect(tp[l3_attr]['ip-address']).to eq %w[192.168.100.2/24]
      expect(tp[l3_attr]['fhrp'].first).to include('group-id' => 1, 'priority' => 150)
    end

    it 'keeps the tp of the other conduit node as it is' do
      expect(tp_mapping[%w[cr3 ge-0/0/2.0]]).to eq %w[c_cr3 ge-0/0/2.0]
      expect(fhrp_of(conduit_layer3, 'c_cr3', 'ge-0/0/2.0')['priority']).to eq 100
    end
  end
end
