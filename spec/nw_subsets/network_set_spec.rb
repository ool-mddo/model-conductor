# frozen_string_literal: true

require_relative '../../lib/nw_subsets/network_subsets'
require_relative '../../lib/nw_subsets/network_set'

RSpec.describe ModelConductor::NetworkSet do
  subject(:network_set) { described_class.new('layer3') }

  let(:subset1) do
    ss = ModelConductor::NetworkSubset.new('layer3__router1', 'layer3__router1__eth0')
    ss.countup_flag(:loop)
    ss
  end
  let(:subset2) { ModelConductor::NetworkSubset.new('layer3__router2') }

  before do
    network_set.subsets << subset1
    network_set.subsets << subset2
  end

  describe '#network_name' do
    it { expect(network_set.network_name).to eq('layer3') }
  end

  describe '#find_subset_includes' do
    it 'returns the subset that contains the given element path' do
      result = network_set.find_subset_includes('layer3__router1__eth0')
      expect(result).to be(subset1)
    end

    it 'returns nil when no subset contains the element' do
      expect(network_set.find_subset_includes('layer3__unknown')).to be_nil
    end
  end

  describe '#to_array' do
    it 'returns an array of subset data hashes' do
      arr = network_set.to_array
      expect(arr.length).to eq(2)
      expect(arr.first).to include(:elements, :flag)
    end
  end

  describe '#reject_empty_set!' do
    it 'removes subsets with no elements' do
      empty_ss = ModelConductor::NetworkSubset.new
      network_set.subsets << empty_ss
      network_set.reject_empty_set!
      expect(network_set.subsets).not_to include(empty_ss)
    end

    it 'returns self' do
      expect(network_set.reject_empty_set!).to be(network_set)
    end
  end

  describe '#elements_diff' do
    let(:other_set) { described_class.new('layer3') }

    before { other_set.subsets << ModelConductor::NetworkSubset.new('layer3__router2') }

    it 'returns elements present in self but not in other' do
      diff = network_set.elements_diff(other_set)
      expect(diff).to include('layer3__router1', 'layer3__router1__eth0')
      expect(diff).not_to include('layer3__router2')
    end
  end

  describe '#flag_diff' do
    let(:other_set) { described_class.new('layer3') }

    before { other_set.subsets << ModelConductor::NetworkSubset.new('layer3__router2') }

    it 'returns positive number when self has more flags than other' do
      expect(network_set.flag_diff(other_set)).to be > 0
    end

    it 'returns zero when both sets have no flags' do
      both_empty = described_class.new('layer3')
      other_empty = described_class.new('layer3')
      both_empty.subsets << ModelConductor::NetworkSubset.new('a')
      other_empty.subsets << ModelConductor::NetworkSubset.new('a')
      expect(both_empty.flag_diff(other_empty)).to eq(0)
    end
  end
end
