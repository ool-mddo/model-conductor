# frozen_string_literal: true

require_relative '../../lib/nw_subsets/network_subsets'

RSpec.describe ModelConductor::NetworkSubset do
  subject(:subset) { described_class.new('layer3__router1', 'layer3__router1__eth0') }

  describe '#elements' do
    it 'contains the paths passed to the constructor' do
      expect(subset.elements).to contain_exactly('layer3__router1', 'layer3__router1__eth0')
    end
  end

  describe '#to_data' do
    it 'has :elements and :flag keys' do
      expect(subset.to_data).to include(:elements, :flag)
    end

    it 'flag is empty by default' do
      expect(subset.to_data[:flag]).to eq({})
    end
  end

  describe '#countup_flag' do
    it 'increments the flag counter each call' do
      subset.countup_flag(:loop)
      expect(subset.flag[:loop]).to eq(1)
      subset.countup_flag(:loop)
      expect(subset.flag[:loop]).to eq(2)
    end

    it 'initializes a new flag key to 1' do
      subset.countup_flag(:new_key)
      expect(subset.flag[:new_key]).to eq(1)
    end
  end

  describe '#uniq!' do
    subject(:dup_subset) { described_class.new('layer3__r1', 'layer3__r1') }

    it 'removes duplicate elements in place' do
      dup_subset.uniq!
      expect(dup_subset.elements.length).to eq(1)
    end

    it 'returns self' do
      expect(dup_subset.uniq!).to be(dup_subset)
    end
  end

  describe '#find_all_multiple_prefix_seg_nodes' do
    it 'finds segment nodes with multiple-prefix suffix (+)' do
      subset_with_mp = described_class.new('layer3__Seg_10.0.0.0/24+')
      expect(subset_with_mp.find_all_multiple_prefix_seg_nodes).to contain_exactly('layer3__Seg_10.0.0.0/24+')
    end

    it 'returns empty for normal elements' do
      expect(subset.find_all_multiple_prefix_seg_nodes).to be_empty
    end
  end

  describe '#find_all_duplicated_prefix_seg_nodes' do
    it 'finds segment nodes with duplicated-prefix suffix (#N)' do
      subset_with_dup = described_class.new('layer3__Seg_10.0.0.0/24#2')
      expect(subset_with_dup.find_all_duplicated_prefix_seg_nodes).to contain_exactly('layer3__Seg_10.0.0.0/24#2')
    end

    it 'returns empty for normal elements' do
      expect(subset.find_all_duplicated_prefix_seg_nodes).to be_empty
    end
  end
end
