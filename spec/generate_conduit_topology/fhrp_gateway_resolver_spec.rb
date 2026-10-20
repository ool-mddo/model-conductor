# frozen_string_literal: true

require_relative '../../lib/generate_conduit_topology/fhrp_gateway_resolver'

RSpec.describe ModelConductor::FhrpGatewayResolver do
  let(:layer3) { fhrp_layer3 }
  let(:groups) { collapsed_groups }
  let(:blueprint) { blueprint_of(groups) }
  let(:classified) do
    blueprint.node_groups.map do |group|
      { group: group, type: group.original_node_names.include?('fw1') ? :firewall : :router }
    end
  end
  let(:node_mapping) do
    classified.each_with_object({}) do |cg, map|
      cg[:group].original_node_names.each { |n| map[n] = cg[:type] == :firewall ? n : cg[:group].conduit_name }
    end
  end
  let(:router_groups) { classified.select { |cg| cg[:type] == :router }.map { |cg| cg[:group] } }
  let(:external_tps) { Set.new([%w[cr1 ge-0/0/0.0], %w[cr2 ge-0/0/0.0], %w[cr3 ge-0/0/0.0]]) }

  subject(:resolver) { described_class.new(layer3['node'], node_mapping, router_groups, external_tps) }

  # @return [ModelConductor::FhrpGatewayResolver::EdgeTermPoint, nil] the edge tp of the conduit node
  def edge_tp_of(conduit_name)
    resolver.edge_tps(conduit_name).first
  end

  def set_fhrp(node, key, value)
    fhrp_of(layer3, node, 'ge-0/0/2.0')[key] = value
  end

  describe 'representative of collapsed members (Master/Active)' do
    it 'selects the highest priority member' do
      expect(resolver.edge_tps('c_cr').map { |t| [t.node_name, t.tp_name] }).to eq [%w[cr1 ge-0/0/2.0]]
    end

    it 'selects the highest source-address if priorities are same' do
      %w[cr1 cr2 cr3].each { |n| set_fhrp(n, 'priority', 100) }
      expect(edge_tp_of('c_cr').node_name).to eq 'cr3' # 192.168.100.4
    end

    it 'compares source-address as a number (not as a string)' do
      %w[cr1 cr2 cr3].each { |n| set_fhrp(n, 'priority', 100) }
      set_fhrp('cr1', 'source-address', '192.168.100.9/24')
      set_fhrp('cr2', 'source-address', '192.168.100.10/24')
      set_fhrp('cr3', 'source-address', '192.168.100.8/24')
      expect(edge_tp_of('c_cr').node_name).to eq 'cr2'
    end

    it 'selects priority 255 (vrrp address owner) first' do
      set_fhrp('cr1', 'priority', 0)
      set_fhrp('cr2', 'priority', 100)
      set_fhrp('cr3', 'priority', 255)
      expect(edge_tp_of('c_cr').node_name).to eq 'cr3'
    end

    it 'selects priority 0 (vrrp: releasing master) last' do
      set_fhrp('cr1', 'priority', 0)
      set_fhrp('cr2', 'priority', 0)
      set_fhrp('cr3', 'priority', 100)
      expect(edge_tp_of('c_cr').node_name).to eq 'cr3'
      expect(resolver.edge_tps('c_cr').length).to eq 1
    end

    it 'uses the member order if priority and address are same' do
      %w[cr1 cr2 cr3].each do |n|
        set_fhrp(n, 'priority', 100)
        set_fhrp(n, 'source-address', '192.168.100.2/24')
      end
      expect(edge_tp_of('c_cr').node_name).to eq 'cr1'
    end

    it 'treats a member without valid source-address as the lowest in the address comparison' do
      %w[cr1 cr2 cr3].each { |n| set_fhrp(n, 'priority', 100) }
      set_fhrp('cr3', 'source-address', 'invalid')
      set_fhrp('cr2', 'source-address', '192.168.100.3/24')
      set_fhrp('cr1', 'source-address', '192.168.100.2/24')
      expect(edge_tp_of('c_cr').node_name).to eq 'cr2'
    end

    it 'selects hsrp members in the same way' do
      %w[cr1 cr2 cr3].each do |n|
        set_fhrp(n, 'protocol', 'hsrp')
        set_fhrp(n, 'priority', 110)
      end
      expect(edge_tp_of('c_cr').node_name).to eq 'cr3'
    end
  end

  describe 'redundancy' do
    context 'with members collapsed into one conduit node' do
      it 'replaces ip address with the virtual address (prefix length of source-address) and drops fhrp' do
        expect(edge_tp_of('c_cr')).to have_attributes(ip_addrs: %w[192.168.100.1/24], fhrp: [])
      end
    end

    context 'with members in different conduit nodes' do
      let(:groups) { separate_groups }

      it 'keeps fhrp and the ip address of each edge tp' do
        expected_fhrp = [fhrp_of(layer3, 'cr1', 'ge-0/0/2.0')]
        expect(edge_tp_of('c_cr1')).to have_attributes(ip_addrs: %w[192.168.100.2/24], fhrp: expected_fhrp)
        expect(edge_tp_of('c_cr3')).to have_attributes(ip_addrs: %w[192.168.100.4/24])
      end
    end

    context 'with a member which is not in the blueprint' do
      let(:groups) { { 'c_cr1' => ['cr1'], 'fw1' => ['fw1'] } }

      it 'does not count the member (redundancy is not maintained)' do
        expect(edge_tp_of('c_cr1')).to have_attributes(ip_addrs: %w[192.168.100.1/24], fhrp: [])
      end
    end

    context 'with the group member in the firewall group' do
      let(:groups) { { 'c_cr' => %w[cr1 cr2 cr3], 'fw1' => ['fw1'] } }

      it 'counts the firewall node as a different conduit node (redundancy is maintained)' do
        %w[cr1 cr2 cr3].each do |n|
          fhrp_of(layer3, n, 'ge-0/0/2.0').merge!('virtual-address' => %w[172.16.0.1], 'group-id' => 5)
        end
        expect(edge_tp_of('c_cr')).to have_attributes(ip_addrs: %w[192.168.100.2/24])
        expect(edge_tp_of('c_cr').fhrp.first['group-id']).to eq 5
      end
    end
  end

  describe 'virtual address conversion' do
    it 'converts all virtual addresses' do
      %w[cr1 cr2 cr3].each { |n| set_fhrp(n, 'virtual-address', %w[192.168.100.1 192.168.100.254]) }
      expect(edge_tp_of('c_cr').ip_addrs).to eq %w[192.168.100.1/24 192.168.100.254/24]
    end

    it 'does not convert a virtual address of a different address family (uses the original ip address)' do
      %w[cr1 cr2 cr3].each { |n| set_fhrp(n, 'virtual-address', %w[fc00::1]) }
      expect(edge_tp_of('c_cr').ip_addrs).to eq %w[192.168.100.2/24]
    end

    it 'does not convert if source-address does not have prefix length (uses the original ip address)' do
      %w[cr1 cr2 cr3].each { |n| set_fhrp(n, 'source-address', '192.168.100.2') }
      expect(edge_tp_of('c_cr').ip_addrs).to eq %w[192.168.100.2/24]
    end
  end

  describe 'target term-points' do
    it 'ignores term-points without fhrp and external term-points' do
      tps = resolver.edge_tps('c_cr').map(&:tp_name)
      expect(tps).to eq %w[ge-0/0/2.0]
      expect(resolver.find_edge_tp('c_cr', 'cr1', 'ge-0/0/9.0')).to be_nil
      expect(resolver.find_edge_tp('c_cr', 'cr1', 'ge-0/0/0.0')).to be_nil
    end

    it 'does not make edge tp of firewall nodes' do
      expect(resolver.edge_tps('fw1')).to eq []
    end

    it 'returns an empty array for unknown conduit node' do
      expect(resolver.edge_tps('unknown')).to eq []
    end
  end

  describe '#maintained_fhrp (external tps)' do
    let(:groups) { separate_groups }

    it 'returns fhrp of the redundant group as a copy' do
      fhrp = resolver.maintained_fhrp('cr1', 'ge-0/0/2.0')
      expect(fhrp).to eq [fhrp_of(layer3, 'cr1', 'ge-0/0/2.0')]
      fhrp.first['priority'] = 1
      expect(fhrp_of(layer3, 'cr1', 'ge-0/0/2.0')['priority']).to eq 150
    end

    it 'returns [] if redundancy is not maintained' do
      collapsed = described_class.new(layer3['node'], { 'cr1' => 'c', 'cr2' => 'c', 'cr3' => 'c', 'fw1' => 'fw1' },
                                      router_groups, external_tps)
      expect(collapsed.maintained_fhrp('cr1', 'ge-0/0/2.0')).to eq []
    end

    it 'returns [] for a term-point without fhrp' do
      expect(resolver.maintained_fhrp('cr1', 'ge-0/0/0.0')).to eq []
      expect(resolver.maintained_fhrp('unknown', 'eth0')).to eq []
    end
  end
end
