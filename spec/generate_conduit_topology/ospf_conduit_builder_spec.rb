# frozen_string_literal: true

require_relative '../../lib/generate_conduit_topology/ospf_conduit_builder'

RSpec.describe ModelConductor::OspfConduitBuilder do
  let(:tp_key) { 'ietf-network-topology:termination-point' }
  let(:original_ospf) do
    {
      'network-id' => 'ospf_area0',
      'node' => [
        { 'node-id' => 'router1', tp_key => [{ 'tp-id' => 'eth0' }] },
        { 'node-id' => 'router3', tp_key => [{ 'tp-id' => 'eth0' }] },
        { 'node-id' => 'Seg_10.0.0.0/30',
          tp_key => [{ 'tp-id' => 'router1_eth0' }, { 'tp-id' => 'router3_eth0' }] }
      ],
      'ietf-network-topology:link' => []
    }
  end
  # router3 is not defined in the blueprint
  let(:node_mapping) { { 'router1' => 'conduit_r1' } }
  let(:tp_mapping) { { %w[router1 eth0] => %w[conduit_r1 eth1] } }

  subject(:result) { described_class.new(original_ospf, node_mapping, tp_mapping).build }

  it 'omits nodes not found in node_mapping without raising' do
    expect { result }.not_to raise_error
    expect(result['node'].map { |n| n['node-id'] }).to eq(['conduit_r1'])
  end

  it 'omits segments left with fewer than two conduit endpoints' do
    expect(result['node'].map { |n| n['node-id'] }).not_to include('Seg_10.0.0.0/30')
  end
end
