require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'pp'

describe "MongoMapper::Plugins::ReferencedTree" do

  # can be written in fewer lines, but keeping it obvious as to what it's building
  before(:each) do
    @account   = Account.create(:name => "something")

    @n_1       = @account.nodes.create!(:reference => [1])
    @n_1_1     = @account.nodes.create!(:reference => [1,1])
    @n_1_1_1   = @account.nodes.create!(:reference => [1,1,1])
    @n_1_1_2   = @account.nodes.create!(:reference => [1,1,2])
    @n_1_1_2_1 = @account.nodes.create!(:reference => [1,1,2,1])
    @n_1_1_3   = @account.nodes.create!(:reference => [1,1,3])

    @n_2       = @account.nodes.create!(:reference => [2])
    @n_2_1     = @account.nodes.create!(:reference => [2,1])
    @n_2_1_1   = @account.nodes.create!(:reference => [2,1,1])
    @n_2_1_2   = @account.nodes.create!(:reference => [2,1,2])
    @n_2_1_2_1 = @account.nodes.create!(:reference => [2,1,2,1])
    @n_2_1_3   = @account.nodes.create!(:reference => [2,1,3])
  end

  describe "scoping" do
    it "should scope queries to the provided scope" do
      other_account = Account.create(:name => "other")
      o_1   = other_account.nodes.create!(:reference => [1])
      o_1_1 = other_account.nodes.create!(:reference => [1,1])

      o_1.siblings.should == []
      @n_1.siblings.should_not include(o_1)
    end
  end

  describe "on create" do
    describe "with no reference set" do
      it "should set the reference to [1] if it is the only item in the tree" do
        other_account = Account.create(:name => "other")
        node = other_account.nodes.create
        node.reference.should == [1]
      end

      it "should move the item to the end of the tree as a new root" do
        node = @account.nodes.create
        node.reference.should == [3]
      end
    end
  end

  describe "#reference=" do
    it "should set the depth to the size of the reference array" do
      @n_1_1_2_1.depth.should == 4
    end
  end

  describe "#set_reference" do
    it "should not call #save" do
      @n_1.should_not_receive(:save)
      @n_1.set_reference([1,2,3])
    end

    it "should update the reference to the one provided" do
      @n_1.set_reference([1,2,3])
      @n_1.reload
      @n_1.reference.should == [1,2,3]
    end

    it "should update the depth for the reference" do
      @n_1.set_reference([1,2,3])
      @n_1.reload
      @n_1.depth.should == 3
    end
  end

  describe "#formatted_reference" do
    it "should join the reference numbers with dots" do
      @n_1_1_2_1.formatted_reference.should == "1.1.2.1"
    end
  end

  describe "#parent" do
    it "should return nil if node is root" do
      @n_1.parent.should be_nil
    end

    it "should return the nodes parent" do
      @n_1_1_2.parent.should == @n_1_1
    end
  end

  describe "#parent=" do
    # ahem, better way of describing this needed!
    it "should set the reference as the parent's and insert 1 for the last level if the parent doesn't have children" do
      node = Node.new
      node.parent = @n_1_1_1
      node.reference.should == [1,1,1,1]
    end

    it "should set the reference as the parent's last child plus one" do
      node = Node.new
      node.parent = @n_1_1_2
      node.reference.should == [1,1,2,2]
    end
  end

  describe "#root?" do
    it "should be true if the node is at the root of the tree" do
      @n_1.root?.should be_true
    end

    it "should be false if the node is in a sub-level" do
      @n_1_1.root?.should be_false
    end
  end

  describe "#root" do
    it "should fetch the root node for this tree" do
      @n_2_1.root.should == @n_2
    end
  end

  describe "#roots" do
    it "should fetch all the root nodes" do
      @n_2_1.roots.should == [@n_1, @n_2]
    end
  end

  describe "#ancestors" do
    it "should fetch all the ancestors of the node" do
      @n_1_1_2.ancestors.should == [@n_1, @n_1_1]
    end
  end

  describe "#siblings" do
    it "should return all nodes on the same level of the tree except itself" do
      @n_2_1_2.siblings.should == [@n_2_1_1, @n_2_1_3]
    end
  end

  describe "#self_and_siblings" do
    it "should return all nodes on the same level of the tree including itself" do
      @n_2_1_2.self_and_siblings.should == [@n_2_1_1, @n_2_1_2, @n_2_1_3]
    end
  end

  describe "#children" do
    it "should return all the children of the node" do
      @n_1_1.children.should == [@n_1_1_1, @n_1_1_2, @n_1_1_3]
    end
  end

  describe "#descendants" do
    it "should return all nodes further up the tree" do
      @n_1_1.descendants.should == [@n_1_1_1, @n_1_1_2, @n_1_1_2_1, @n_1_1_3]
    end
  end

  describe "#self_and_descendants" do
    it "should return all nodes further up the tree including itself" do
      @n_1_1.self_and_descendants.should == [@n_1_1, @n_1_1_1, @n_1_1_2, @n_1_1_2_1, @n_1_1_3]
    end
  end

  describe "#is_ancestor_of?" do
    it "should return true if it's an ancestor of the other node" do
      @n_1_1_2.is_ancestor_of?(@n_1_1_2_1).should be_true
    end

    it "should return false if it's not an ancestor of the other node" do
      @n_1_1_2.is_ancestor_of?(@n_1_1).should be_false
    end

    it "should return false if it's a sibling of the other node" do
      @n_1_1_2.is_ancestor_of?(@n_1_1_3).should be_false
    end
  end

  describe "#is_or_is_ancestor_of?" do
    it "should return true if it is the same item" do
      @n_1_1_2.is_or_is_ancestor_of?(@n_1_1_2).should be_true
    end

    it "should return true if it's an ancestor of the other node" do
      @n_1_1_2.is_or_is_ancestor_of?(@n_1_1_2_1).should be_true
    end

    it "should return false if it's not an ancestor of the other node" do
      @n_1_1_2.is_or_is_ancestor_of?(@n_1_1).should be_false
    end

    it "should return false if it's a sibling of the other node" do
      @n_1_1_2.is_or_is_ancestor_of?(@n_1_1_3).should be_false
    end
  end

  describe "#is_descendant_of?" do
    it "should return true if it's a descendant of the other node" do
      @n_1_1_2_1.is_descendant_of?(@n_1_1_2).should be_true
    end

    it "should return false if it's not a descendant of the other node" do
      @n_1_1.is_descendant_of?(@n_1_1_2).should be_false
    end

    it "should return false if it's a sibling of the other node" do
      @n_1_1_3.is_descendant_of?(@n_1_1_2).should be_false
    end
  end

  describe "#is_or_is_descendant_of?" do
    it "should return true if it is the same item" do
      @n_1_1_2.is_or_is_descendant_of?(@n_1_1_2).should be_true
    end

    it "should return true if it's a descendant of the other node" do
      @n_1_1_2_1.is_or_is_descendant_of?(@n_1_1_2).should be_true
    end

    it "should return false if it's not a descendant of the other node" do
      @n_1_1.is_or_is_descendant_of?(@n_1_1_2).should be_false
    end

    it "should return false if it's a sibling of the other node" do
      @n_1_1_3.is_or_is_descendant_of?(@n_1_1_2).should be_false
    end
  end

  describe "#is_sibling_of?" do
    it "should return false if it's a descendant of the other node" do
      @n_1_1_2_1.is_sibling_of?(@n_1_1_2).should be_false
    end

    it "should return false if it's an ancestor of the other node" do
      @n_1_1.is_sibling_of?(@n_1_1_2).should be_false
    end

    it "should return true if it's a sibling of the other node" do
      @n_1_1_3.is_sibling_of?(@n_1_1_2).should be_true
    end
  end

  describe "#is_or_is_sibling_of?" do
    it "should return true if it is the same item" do
      @n_1_1_2.is_or_is_sibling_of?(@n_1_1_2).should be_true
    end

    it "should return false if it's a descendant of the other node" do
      @n_1_1_2_1.is_or_is_sibling_of?(@n_1_1_2).should be_false
    end

    it "should return false if it's an ancestor of the other node" do
      @n_1_1.is_or_is_sibling_of?(@n_1_1_2).should be_false
    end

    it "should return true if it's a sibling of the other node" do
      @n_1_1_3.is_or_is_sibling_of?(@n_1_1_2).should be_true
    end
  end

end