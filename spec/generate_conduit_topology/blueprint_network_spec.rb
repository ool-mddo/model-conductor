# frozen_string_literal: true

require_relative '../../lib/generate_conduit_topology/blueprint_network'

RSpec.describe ModelConductor::BlueprintNetwork do
  let(:bp_data) do
    load_fixture('blueprint_topology.json').dig('ietf-network:networks', 'network').first
  end
  let(:all_bp_networks) do
    load_fixture('blueprint_topology.json').dig('ietf-network:networks', 'network')
  end

  subject(:bp_nw) { described_class.new(bp_data, all_bp_networks) }

  describe '#name' do
    it { expect(bp_nw.name).to eq('zoom0') }
  end

  describe '#node_groups' do
    it 'returns NodeGroup structs for each blueprint node' do
      groups = bp_nw.node_groups
      expect(groups.length).to eq(2)
      expect(groups.map(&:conduit_name)).to contain_exactly('conduit_r1', 'conduit_r2')
    end

    it 'resolves supports to original layer3 node names' do
      groups = bp_nw.node_groups
      r1_group = groups.find { |g| g.conduit_name == 'conduit_r1' }
      expect(r1_group.original_node_names).to contain_exactly('router1')
    end

    it 'caches the result' do
      groups1 = bp_nw.node_groups
      groups2 = bp_nw.node_groups
      expect(groups1).to be(groups2)
    end
  end

  context 'when supports reference a missing blueprint network' do
    let(:bp_data_bad) do
      { 'network-id' => 'zoom1',
        'node' => [{ 'node-id' => 'bad_node',
                     'supports' => [{ 'network-ref' => 'nonexistent', 'node-ref' => 'x' }] }] }
    end

    subject(:bad_bp_nw) { described_class.new(bp_data_bad, [bp_data_bad]) }

    it 'raises RuntimeError with the missing network name' do
      expect { bad_bp_nw.node_groups }.to raise_error(RuntimeError, /nonexistent/)
    end
  end

  context 'with transitive resolution (zoom1 -> zoom0 -> layer3)' do
    let(:zoom1_data) do
      { 'network-id' => 'zoom1',
        'node' => [{ 'node-id' => 'super_r1',
                     'supports' => [{ 'network-ref' => 'zoom0', 'node-ref' => 'conduit_r1' }] }] }
    end
    let(:all_networks_transitive) { [bp_data, zoom1_data] }

    subject(:zoom1_nw) { described_class.new(zoom1_data, all_networks_transitive) }

    it 'resolves transitively to layer3 node names' do
      groups = zoom1_nw.node_groups
      expect(groups.first.original_node_names).to contain_exactly('router1')
    end
  end
end
