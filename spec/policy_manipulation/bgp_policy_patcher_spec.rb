# frozen_string_literal: true

require_relative '../../lib/policy_manipulation/bgp_policy_patcher'

RSpec.describe ModelConductor::BgpPolicyPatcher do
  let(:topology_data) do
    {
      'ietf-network:networks' => {
        'network' => [
          {
            'network-id' => 'bgp_proc',
            'node' => [
              {
                'node-id' => 'router1',
                'mddo-topology:bgp-proc-node-attributes' => {
                  'router-id' => '1.1.1.1',
                  'confederation' => nil,
                  'policy' => []
                },
                'ietf-network-topology:termination-point' => [
                  {
                    'tp-id' => '10.0.0.1',
                    'mddo-topology:bgp-proc-termination-point-attributes' => {
                      'local-as' => 65_000,
                      'remote-as' => 65_001,
                      'import-policy' => [],
                      'export-policy' => []
                    }
                  }
                ]
              }
            ]
          }
        ]
      }
    }
  end

  subject(:patcher) { described_class.new(topology_data) }

  describe '#patch_nodes with valid layer and node' do
    let(:node_patches) do
      [
        {
          'node-id' => 'router1',
          'mddo-topology:bgp-proc-node-attributes' => {
            'policy' => [{ 'name' => 'test-policy' }]
          }
        }
      ]
    end

    it 'returns the topology data (not an error hash)' do
      result = patcher.patch_nodes('bgp_proc', node_patches)
      expect(result).to have_key('ietf-network:networks')
    end

    it 'patches the target node attribute' do
      patcher.patch_nodes('bgp_proc', node_patches)
      patched_node = topology_data.dig('ietf-network:networks', 'network', 0, 'node', 0)
      expect(patched_node.dig('mddo-topology:bgp-proc-node-attributes', 'policy')).to eq([{ 'name' => 'test-policy' }])
    end
  end

  describe '#patch_nodes with TP patch' do
    let(:tp_patches) do
      [
        {
          'node-id' => 'router1',
          'ietf-network-topology:termination-point' => [
            {
              'tp-id' => '10.0.0.1',
              'mddo-topology:bgp-proc-termination-point-attributes' => {
                'import-policy' => ['IMPORT-TEST']
              }
            }
          ]
        }
      ]
    end

    it 'patches the TP attribute' do
      patcher.patch_nodes('bgp_proc', tp_patches)
      tp = topology_data.dig('ietf-network:networks', 'network', 0, 'node', 0,
                             'ietf-network-topology:termination-point', 0)
      expect(tp.dig('mddo-topology:bgp-proc-termination-point-attributes', 'import-policy')).to eq(['IMPORT-TEST'])
    end
  end

  describe '#patch_nodes with nonexistent layer' do
    it 'returns an error hash with :error key' do
      result = patcher.patch_nodes('nonexistent_layer', [])
      expect(result).to have_key(:error)
      expect(result[:error]).to eq(500)
    end
  end

  describe '#patch_nodes with nonexistent node' do
    let(:node_patches) { [{ 'node-id' => 'unknown_router' }] }

    it 'returns an error hash' do
      result = patcher.patch_nodes('bgp_proc', node_patches)
      expect(result).to have_key(:error)
    end
  end
end
