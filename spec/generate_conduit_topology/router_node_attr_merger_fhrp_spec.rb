# frozen_string_literal: true

RSpec.describe ModelConductor::RouterNodeAttrMerger, 'with fhrp (VRRP/HSRP)' do
  let(:layer3) { fhrp_layer3 }
  let(:conduit_layer3) { build_conduit(layer3, groups)[0] }
  let(:prefixes) { conduit_node(conduit_layer3, conduit_name).dig('mddo-topology:l3-node-attributes', 'prefix') }

  context 'when edge tps are kept in separate conduit nodes' do
    let(:groups) { separate_groups }
    let(:conduit_name) { 'c_cr1' }

    it 'keeps the connected prefix of the edge tp (but not the prefix of the unlinked tp without fhrp)' do
      expect(prefixes.map { |p| p['prefix'] }).to match_array %w[10.0.0.0/30 192.168.100.0/24]
    end
  end

  context 'when members are collapsed' do
    let(:groups) { collapsed_groups }
    let(:conduit_name) { 'c_cr' }

    it 'keeps the connected prefix of the virtual address tp only once' do
      expect(prefixes.map { |p| p['prefix'] }.sort).to eq %w[10.0.0.0/30 192.168.100.0/24]
    end
  end
end
