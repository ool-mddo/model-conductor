# frozen_string_literal: true

require_relative '../../lib/generate_conduit_topology/router_node_attr_merger'

RSpec.describe ModelConductor::RouterNodeAttrMerger do
  let(:orig_nodes) do
    load_fixture('minimal_layer3_topology.json').dig('ietf-network:networks', 'network', 0, 'node')
  end

  subject(:merger) { described_class.new(orig_nodes) }

  let(:tp_mapping) { { %w[router1 eth0] => %w[conduit_r1 eth1] } }

  describe '#merge' do
    it 'returns a hash with node-type, prefix, static-route and flag keys' do
      result = merger.merge(['router1'], tp_mapping, 'conduit_r1')
      expect(result).to include('node-type' => 'node', 'flag' => [])
      expect(result).to have_key('prefix')
      expect(result).to have_key('static-route')
    end

    it 'includes the surviving prefix for external TPs' do
      result = merger.merge(['router1'], tp_mapping, 'conduit_r1')
      # router1's eth0 has ip 10.0.0.1/30, so prefix should be 10.0.0.0/30
      prefix_values = result['prefix'].map { |p| p['prefix'] }
      expect(prefix_values).to include('10.0.0.0/30')
    end

    it 'produces empty prefix when no external TP mapping exists' do
      result = merger.merge(['router1'], {}, 'conduit_r1')
      expect(result['prefix']).to be_empty
    end

    it 'deduplicates prefixes from multiple nodes mapped to same conduit' do
      tp_mapping_both = {
        %w[router1 eth0] => %w[conduit_r1 eth1],
        %w[router2 eth0] => %w[conduit_r1 eth2]
      }
      result = merger.merge(%w[router1 router2], tp_mapping_both, 'conduit_r1')
      prefixes = result['prefix'].map { |p| p['prefix'] }
      expect(prefixes).to eq(prefixes.uniq)
    end
  end
end
