# frozen_string_literal: true

require_relative '../../lib/generate_conduit_topology/tp_description_resolver'

RSpec.describe ModelConductor::TpDescriptionResolver do
  let(:tp_key) { 'ietf-network-topology:termination-point' }
  let(:attr_key) { 'mddo-topology:l3-termination-point-attributes' }

  def node(id, tp_ids, type: 'node', description: nil)
    tps = tp_ids.map do |tp_id|
      attr = description ? { 'description' => description, 'ip-address' => ['10.0.0.1/30'] } : {}
      { 'tp-id' => tp_id, 'mddo-topology:l3-termination-point-attributes' => attr }
    end
    { 'node-id' => id, 'ietf-network-topology:termination-point' => tps,
      'mddo-topology:l3-node-attributes' => { 'node-type' => type } }
  end

  def link(src_node, src_tp, dst_node, dst_tp)
    { 'source' => { 'source-node' => src_node, 'source-tp' => src_tp },
      'destination' => { 'dest-node' => dst_node, 'dest-tp' => dst_tp } }
  end

  def bidirectional(node_a, tp_a, node_b, tp_b)
    [link(node_a, tp_a, node_b, tp_b), link(node_b, tp_b, node_a, tp_a)]
  end

  def description(nodes, node_id, tp_id)
    n = nodes.find { |x| x['node-id'] == node_id }
    n[tp_key].find { |t| t['tp-id'] == tp_id }.dig(attr_key, 'description')
  end

  let(:nodes) do
    [
      node('r1', %w[eth1]),
      node('fw1', %w[ge-0/0/1.0 ge-0/0/2.0], description: 'to_old_ge-0/0/3'),
      node('Seg_a', %w[r1_eth1 fw1_ge-0/0/1.0], type: 'segment'),
      node('r2', %w[eth1 eth2]),
      node('r3', %w[eth1]),
      node('r4', %w[eth1]),
      node('Seg_m', %w[r2_eth2 r3_eth1 r4_eth1], type: 'segment')
    ]
  end
  let(:links) do
    bidirectional('Seg_a', 'r1_eth1', 'r1', 'eth1') +
      bidirectional('Seg_a', 'fw1_ge-0/0/1.0', 'fw1', 'ge-0/0/1.0') +
      bidirectional('Seg_m', 'r2_eth2', 'r2', 'eth2') +
      bidirectional('Seg_m', 'r3_eth1', 'r3', 'eth1') +
      bidirectional('Seg_m', 'r4_eth1', 'r4', 'eth1')
  end

  before do
    allow(ModelConductor.logger).to receive(:warn)
    described_class.new(nodes, links).apply!
  end

  it 'sets facing node/tp across a point-to-point segment (router and firewall)' do
    expect(description(nodes, 'r1', 'eth1')).to eq('to_fw1_ge-0/0/1.0')
    expect(description(nodes, 'fw1', 'ge-0/0/1.0')).to eq('to_r1_eth1')
  end

  it 'sets the linked node/tp to segment term-points' do
    expect(description(nodes, 'Seg_a', 'r1_eth1')).to eq('to_r1_eth1')
    expect(description(nodes, 'Seg_a', 'fw1_ge-0/0/1.0')).to eq('to_fw1_ge-0/0/1.0')
  end

  it 'removes the description of a term-point without link but keeps the other attributes' do
    expect(description(nodes, 'fw1', 'ge-0/0/2.0')).to be_nil
    fw_tp = nodes[1][tp_key].last[attr_key]
    expect(fw_tp).to eq('ip-address' => ['10.0.0.1/30'])
  end

  it 'does not set description for a multi-access segment (and warns)' do
    expect(description(nodes, 'r2', 'eth2')).to be_nil
    expect(description(nodes, 'r3', 'eth1')).to be_nil
    expect(ModelConductor.logger).to have_received(:warn).at_least(:once)
  end

  it 'still sets segment term-point description for a multi-access segment' do
    expect(description(nodes, 'Seg_m', 'r3_eth1')).to eq('to_r3_eth1')
  end

  it 'does not leave nil description key' do
    expect(nodes[3][tp_key].last[attr_key]).not_to have_key('description')
  end

  context 'with a firewall cluster pair' do
    def fw_node(id, pair)
      n = node(id, %w[ge-0/0/1.0 ge-7/0/1.0 ge-0/0/2.0], description: 'to_old_x')
      n['mddo-topology:l3-node-attributes']['firewall'] = { 'node' => id, 'pair' => pair }
      n
    end

    let(:pair) { { 'primary' => { 'name' => 'fw1' }, 'secondary' => { 'name' => 'fw2' } } }
    let(:nodes) do
      [
        node('r1', %w[eth1]), node('r2', %w[eth1]),
        fw_node('fw1', pair), fw_node('fw2', pair),
        node('Seg_a', %w[r1_eth1 fw1_ge-0/0/1.0], type: 'segment'),
        node('Seg_b', %w[r2_eth1 fw2_ge-7/0/1.0], type: 'segment')
      ]
    end
    # fw1: ge-0/0/1.0 is linked, fw2: ge-7/0/1.0 is linked (the other side is a partner's port without link)
    let(:links) do
      bidirectional('Seg_a', 'r1_eth1', 'r1', 'eth1') +
        bidirectional('Seg_a', 'fw1_ge-0/0/1.0', 'fw1', 'ge-0/0/1.0') +
        bidirectional('Seg_b', 'r2_eth1', 'r2', 'eth1') +
        bidirectional('Seg_b', 'fw2_ge-7/0/1.0', 'fw2', 'ge-7/0/1.0')
    end

    it 'copies the description determined by the link to the partner node' do
      expect(description(nodes, 'fw1', 'ge-0/0/1.0')).to eq('to_r1_eth1')
      expect(description(nodes, 'fw2', 'ge-0/0/1.0')).to eq('to_r1_eth1')
      expect(description(nodes, 'fw2', 'ge-7/0/1.0')).to eq('to_r2_eth1')
      expect(description(nodes, 'fw1', 'ge-7/0/1.0')).to eq('to_r2_eth1')
    end

    it 'keeps the term-points that no node determines empty' do
      expect(description(nodes, 'fw1', 'ge-0/0/2.0')).to be_nil
      expect(description(nodes, 'fw2', 'ge-0/0/2.0')).to be_nil
    end

    it 'has the same descriptions in the pair' do
      by_node = %w[fw1 fw2].map do |id|
        nodes.find { |n| n['node-id'] == id }[tp_key].to_h { |t| [t['tp-id'], t.dig(attr_key, 'description')] }
      end
      expect(by_node[0]).to eq(by_node[1])
    end
  end
end
