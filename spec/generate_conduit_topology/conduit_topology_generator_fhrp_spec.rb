# frozen_string_literal: true

require 'netomox'
require_relative '../../lib/generate_conduit_topology/conduit_topology_generator'

RSpec.describe ModelConductor::ConduitTopologyGenerator, 'with fhrp (VRRP/HSRP)' do
  let(:original_topology) { { 'ietf-network:networks' => { 'network' => [fhrp_layer3] } } }
  let(:blueprint_topology) do
    nodes = groups.map do |name, supports|
      { 'node-id' => name, 'supports' => supports.map { |s| { 'network-ref' => 'layer3', 'node-ref' => s } } }
    end
    { 'ietf-network:networks' => { 'network' => [{ 'network-id' => 'bp1', 'node' => nodes }] } }
  end
  let(:result) { described_class.new(original_topology, blueprint_topology).generate }
  let(:networks) { Netomox::Topology::Networks.new(result.first[:topology]) }
  let(:conduit_tp) { networks.find_network('layer3').find_node_by_name(conduit_name).find_tp_by_name(conduit_tp_name) }

  describe 'blueprint flag of the networks container' do
    let(:groups) { separate_groups }
    let(:attr_key) { 'mddo-topology:networks-attributes' }

    it 'records the blueprint snapshot name in the flag (parsed by netomox)' do
      result = described_class.new(original_topology, blueprint_topology, 'original_asis_blueprint1').generate
      expect(result.first[:topology].dig('ietf-network:networks', attr_key, 'flag'))
        .to eq %w[blueprint=original_asis_blueprint1]
      nws = Netomox::Topology::Networks.new(result.first[:topology])
      expect(nws.attribute.flags).to eq %w[blueprint=original_asis_blueprint1]
    end

    it 'does not add the attribute if the blueprint snapshot name is not given' do
      expect(result.first[:topology]['ietf-network:networks']).not_to have_key(attr_key)
    end
  end

  context 'with redundancy maintained' do
    let(:groups) { separate_groups }
    let(:conduit_name) { 'c_cr1' }
    let(:conduit_tp_name) { 'ge-0/0/2.0' } # 1:1 group keeps the original tp name

    it 'is parsed by netomox topology classes and fhrp is kept as MddoFhrp' do
      fhrp = conduit_tp.attribute.fhrp
      expect(fhrp.length).to eq 1
      expect(fhrp.first).to be_a Netomox::Topology::MddoFhrp
      expect(fhrp.first).to have_attributes(protocol: 'vrrp', group_id: 1, priority: 150,
                                            virtual_addresses: %w[192.168.100.1])
    end
  end

  context 'with redundancy not maintained' do
    let(:groups) { collapsed_groups }
    let(:conduit_name) { 'c_cr' }
    let(:conduit_tp_name) { 'eth2' }

    it 'has the virtual address as ip address and no fhrp' do
      expect(conduit_tp.attribute.ip_addrs).to eq %w[192.168.100.1/24]
      expect(conduit_tp.attribute.fhrp).to eq []
    end
  end
end
