# frozen_string_literal: true

require_relative '../../lib/generate_conduit_topology/ospf_conduit_builder'

RSpec.describe ModelConductor::OspfConduitBuilder, 'with fhrp edge tps in tp_mapping' do
  let(:tp_key) { 'ietf-network-topology:termination-point' }
  let(:original_ospf) do
    {
      'network-id' => 'ospf_area0',
      'node' => [
        { 'node-id' => 'cr1', tp_key => [{ 'tp-id' => 'ge-0/0/0.0' }] },
        { 'node-id' => 'fw1', tp_key => [{ 'tp-id' => 'ge-0/0/1.0' }] },
        { 'node-id' => 'Seg_10.0.0.0/30',
          tp_key => [{ 'tp-id' => 'cr1_ge-0/0/0.0' }, { 'tp-id' => 'fw1_ge-0/0/1.0' }] }
      ],
      'ietf-network-topology:link' => []
    }
  end
  let(:node_mapping) { { 'cr1' => 'c_cr1', 'fw1' => 'fw1' } }
  let(:tp_mapping) { { %w[cr1 ge-0/0/0.0] => %w[c_cr1 eth1], %w[fw1 ge-0/0/1.0] => %w[fw1 ge-0/0/1.0] } }
  # edge tp with fhrp (not in ospf area network)
  let(:tp_mapping_with_edge) { tp_mapping.merge(%w[cr1 ge-0/0/2.0] => %w[c_cr1 eth2]) }

  it 'generates the same ospf conduit as without the edge tp mapping' do
    without = described_class.new(original_ospf, node_mapping, tp_mapping).build
    with = described_class.new(original_ospf, node_mapping, tp_mapping_with_edge).build
    expect(with).to eq without
  end
end
