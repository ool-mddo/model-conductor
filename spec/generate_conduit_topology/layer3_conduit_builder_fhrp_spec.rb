# frozen_string_literal: true

RSpec.describe ModelConductor::Layer3ConduitBuilder, 'with fhrp (VRRP/HSRP)' do
  let(:layer3) { fhrp_layer3 }
  let(:result) { build_conduit(layer3, groups) }
  let(:conduit_layer3) { result[0] }
  let(:tp_mapping) { result[2] }
  let(:groups) { separate_groups }

  context 'when redundancy is maintained (cr1, cr2, cr3 are in different conduit nodes)' do
    it 'keeps the edge tp with fhrp and ip address in each conduit node (after external tps)' do
      expect(conduit_tp_names(conduit_layer3, 'c_cr1')).to eq %w[eth1 eth2]
      tp = find_tp(conduit_layer3, 'c_cr1', 'eth2')
      expect(tp[l3_attr]['ip-address']).to eq %w[192.168.100.2/24]
      expect(tp[l3_attr]['fhrp']).to eq [
        {
          'protocol' => 'vrrp', 'group-id' => 1, 'virtual-address' => %w[192.168.100.1], 'priority' => 150,
          'preempt' => true, 'source-address' => '192.168.100.2/24', 'active' => true
        }
      ]
    end

    it 'keeps the priority of each member' do
      expect(fhrp_of(conduit_layer3, 'c_cr2', 'eth2')['priority']).to eq 100
      expect(fhrp_of(conduit_layer3, 'c_cr3', 'eth2')['priority']).to eq 100
    end

    it 'adds the edge tp to tp_mapping' do
      expect(tp_mapping[%w[cr1 ge-0/0/2.0]]).to eq %w[c_cr1 eth2]
      expect(tp_mapping[%w[cr2 ge-0/0/2.0]]).to eq %w[c_cr2 eth2]
    end

    it 'does not keep the edge tp without fhrp (as before)' do
      expect(tp_mapping).not_to have_key(%w[cr1 ge-0/0/9.0])
      expect(conduit_node(conduit_layer3, 'c_cr1')[tp_key].map { |tp| tp[l3_attr]['ip-address'] }.flatten)
        .not_to include('10.9.9.1/24')
    end

    it 'does not add segment nodes or links for the edge tps' do
      expect(conduit_layer3['node'].map { |n| n['node-id'] }).to match_array %w[c_cr1 c_cr2 c_cr3 fw1
                                                                                Seg_10.0.0.0/30 Seg_10.0.1.0/30
                                                                                Seg_10.0.2.0/30]
      link_tps = conduit_layer3['ietf-network-topology:link'].flat_map do |l|
        [l['source']['source-tp'], l['destination']['dest-tp']]
      end
      expect(link_tps).not_to include('eth2', 'c_cr1_eth2')
    end

    it 'does not add fhrp key to tps without fhrp' do
      expect(find_tp(conduit_layer3, 'c_cr1', 'eth1')[l3_attr]).not_to have_key('fhrp')
    end

    it 'copies fhrp (changing the conduit does not affect the original topology)' do
      fhrp_of(conduit_layer3, 'c_cr1', 'eth2')['priority'] = 1
      expect(fhrp_of(layer3, 'cr1', 'ge-0/0/2.0')['priority']).to eq 150
    end
  end

  context 'when redundancy is not maintained (cr1, cr2, cr3 are collapsed into one conduit node)' do
    let(:groups) { collapsed_groups }

    it 'keeps one edge tp that has the virtual address as ip address and no fhrp' do
      expect(conduit_tp_names(conduit_layer3, 'c_cr')).to eq %w[eth1 eth2]
      tp = find_tp(conduit_layer3, 'c_cr', 'eth2')
      expect(tp[l3_attr]['ip-address']).to eq %w[192.168.100.1/24]
      expect(tp[l3_attr]).not_to have_key('fhrp')
    end

    it 'selects the member which becomes Master (the highest priority: cr1) as the representative' do
      expect(tp_mapping[%w[cr1 ge-0/0/2.0]]).to eq %w[c_cr eth2]
      expect(tp_mapping).not_to have_key(%w[cr2 ge-0/0/2.0])
      expect(tp_mapping).not_to have_key(%w[cr3 ge-0/0/2.0])
    end
  end

  context 'when the partner is not in the blueprint' do
    let(:groups) { { 'c_cr1' => ['cr1'], 'fw1' => ['fw1'] } }

    it 'uses the virtual address as ip address (redundancy is not maintained)' do
      tp = find_tp(conduit_layer3, 'c_cr1', 'eth2')
      expect(tp[l3_attr]['ip-address']).to eq %w[192.168.100.1/24]
      expect(tp[l3_attr]).not_to have_key('fhrp')
    end
  end

  context 'when a group has three members and two of them are collapsed' do
    let(:groups) { { 'c_cr12' => %w[cr1 cr2], 'c_cr3' => ['cr3'], 'fw1' => ['fw1'] } }

    it 'maintains redundancy with one tp (the representative) in the collapsed node' do
      edge_tps = conduit_node(conduit_layer3, 'c_cr12')[tp_key].select { |tp| tp[l3_attr].key?('fhrp') }
      expect(edge_tps.length).to eq 1
      expect(edge_tps.first[l3_attr]['ip-address']).to eq %w[192.168.100.2/24]
      expect(edge_tps.first[l3_attr]['fhrp'].first['priority']).to eq 150
      expect(fhrp_of(conduit_layer3, 'c_cr3', 'eth2')).not_to be_nil
    end
  end

  context 'when a router has an external tp with fhrp' do
    before do
      # the same group on the external tps of cr1 and cr2 (and fw1 for the redundant case)
      [['cr1', 'ge-0/0/0.0', '10.0.0.1/30', 90], ['cr2', 'ge-0/0/0.0', '10.0.1.1/30', 80]].each do |node, tp, src, prio|
        find_tp(layer3, node, tp)[l3_attr]['fhrp'] = [
          { 'protocol' => 'hsrp', 'group-id' => 7, 'virtual-address' => %w[10.0.9.9], 'priority' => prio,
            'preempt' => false, 'source-address' => src, 'active' => true }
        ]
      end
    end

    context 'with the group members in different conduit nodes' do
      it 'keeps fhrp (and the own ip address)' do
        tp = find_tp(conduit_layer3, 'c_cr1', 'eth1')
        expect(tp[l3_attr]['ip-address']).to eq %w[10.0.0.1/30]
        expect(tp[l3_attr]['fhrp'].first).to include('protocol' => 'hsrp', 'group-id' => 7, 'priority' => 90)
      end
    end

    context 'with the group members collapsed into one conduit node' do
      let(:groups) { { 'c_cr12' => %w[cr1 cr2], 'c_cr3' => ['cr3'], 'fw1' => ['fw1'] } }

      it 'drops fhrp but does not replace the ip address with the virtual address' do
        tp = find_tp(conduit_layer3, 'c_cr12', 'eth1')
        expect(tp[l3_attr]['ip-address']).to eq %w[10.0.0.1/30]
        expect(tp[l3_attr]).not_to have_key('fhrp')
      end
    end
  end

  context 'with firewall group' do
    it 'keeps all tps and attributes including fhrp as before' do
      expect(conduit_tp_names(conduit_layer3, 'fw1')).to eq %w[ge-0/0/1.0 ge-0/0/2.0 ge-0/0/3.0 ge-0/0/4.0]
      expect(fhrp_of(conduit_layer3, 'fw1', 'ge-0/0/4.0')).to eq fhrp_of(layer3, 'fw1', 'ge-0/0/4.0')
    end

    it 'does not replace the ip address with the virtual address even if the partner is not in the blueprint' do
      tp = find_tp(conduit_layer3, 'fw1', 'ge-0/0/4.0')
      expect(tp[l3_attr]['ip-address']).to eq %w[172.16.0.2/24]
    end
  end

  context 'without fhrp in the original topology' do
    it 'generates the same conduit as before (no fhrp key)' do
      stripped = fhrp_layer3
      stripped['node'].each do |node|
        (node[tp_key] || []).each { |tp| tp[l3_attr]&.delete('fhrp') }
      end
      conduit, _node_mapping, mapping = build_conduit(stripped, separate_groups)
      expect(conduit['node'].flat_map { |n| (n[tp_key] || []).map { |tp| tp[l3_attr] } }.compact)
        .to all(satisfy { |attr| !attr.key?('fhrp') })
      expect(mapping.keys).not_to include(%w[cr1 ge-0/0/2.0])
    end
  end
end
