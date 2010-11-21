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

  describe ".renumber_tree" do

    # bugger up the tree by setting the references to non-sensical ones
    # then when calling Node.renumber_tree it should put it back to its original state
    # (as long as the general structure & ordering is the same)
    #
    # 1                  1
    # 1.3                1.1
    # 1.3.1              1.1.1
    # 1.3.4      =>      1.1.2
    # 1.3.4.6            1.1.2.1
    # 1.3.6              1.1.3

    before(:each) do
      @n_1.set(:reference       => [1])
      @n_1_1.set(:reference     => [1,3])
      @n_1_1_1.set(:reference   => [1,3,1])
      @n_1_1_2.set(:reference   => [1,3,4])
      @n_1_1_2_1.set(:reference => [1,3,4,6])
      @n_1_1_3.set(:reference   => [1,3,6])
    end

    it "should fix the tree's structure by renumbering based on the depths" do
      Node.renumber_tree(:account_id => @account.id)

      @n_1.reload.reference.should        == [1]
      @n_1_1.reload.reference.should      == [1,1]
      @n_1_1_1.reload.reference.should    == [1,1,1]
      @n_1_1_2.reload.reference.should    == [1,1,2]
      @n_1_1_2_1.reload.reference.should  == [1,1,2,1]
      @n_1_1_3.reload.reference.should    == [1,1,3]
    end

    it "should leave nodes alone which don't need moving" do
      Node.renumber_tree(:account_id => @account.id)

      @n_2.reload.reference.should        == [2]
      @n_2_1.reload.reference.should      == [2,1]
      @n_2_1_1.reload.reference.should    == [2,1,1]
      @n_2_1_2.reload.reference.should    == [2,1,2]
      @n_2_1_2_1.reload.reference.should  == [2,1,2,1]
      @n_2_1_3.reload.reference.should    == [2,1,3]
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

    describe "when inserted into the tree" do

      # 1                  1
      # -----------------> 1.1 (new)
      # 1.1                1.2
      # 1.1.1              1.2.1
      # 1.1.2              1.2.2
      # 1.1.2.1            1.2.1.1
      # 1.1.3              1.2.2

      it "should move the subsequent nodes down to fit" do
        node = @account.nodes.create(:reference => [1,1])

        @n_1.reload.reference.should        == [1]
        node.reload.reference.should        == [1,1]
        @n_1_1.reload.reference.should      == [1,2]
        @n_1_1_1.reload.reference.should    == [1,2,1]
        @n_1_1_2.reload.reference.should    == [1,2,2]
        @n_1_1_2_1.reload.reference.should  == [1,2,2,1]
        @n_1_1_3.reload.reference.should    == [1,2,3]
      end
    end
  end

  describe "#destroy" do

    # 1                  1
    # 1.1                1.1
    # 1.1.1              1.1.1
    # 1.1.2      =>      xxxxx
    # 1.1.2.1            1.1.1.1
    # 1.1.3              1.1.2

    it "should renumber siblings and descendants" do
      @n_1_1_2.destroy

      @n_1.reload.reference.should        == [1]
      @n_1_1.reload.reference.should      == [1,1]
      @n_1_1_1.reload.reference.should    == [1,1,1]
      lambda{ @n_1_1_2.reload }.should raise_error(MongoMapper::DocumentNotFound)
      @n_1_1_2_1.reload.reference.should  == [1,1,1,1]
      @n_1_1_3.reload.reference.should    == [1,1,2]
    end

    # 1                  xxxxx
    # 1.1                1
    # 1.1.1              1.1
    # 1.1.2      =>      1.2
    # 1.1.2.1            1.2.1
    # 1.1.3              1.3

    it "should outdent a level if the first root is deleted" do
      @n_1.destroy

      lambda{ @n_1.reload }.should raise_error(MongoMapper::DocumentNotFound)
      @n_1_1.reload.reference.should      == [1]
      @n_1_1_1.reload.reference.should    == [1,1]
      @n_1_1_2.reload.reference.should    == [1,2]
      @n_1_1_2_1.reload.reference.should  == [1,2,1]
      @n_1_1_3.reload.reference.should    == [1,3]
    end


    # 1                  1
    # 1.1                1.1
    # 1.1.1              1.1.1
    # 1.1.2              1.1.2
    # 1.1.2.1            1.1.2.1
    # 1.1.3              1.1.3
    # 2                  xxxx
    # 2.1                1.2
    # 2.1.1              1.2.1
    # 2.1.2      =>      1.2.2
    # 2.1.2.1            1.2.2.1
    # 2.1.3              1.2.3

    it "should join trees if a subsequent root is deleted" do
      @n_2.destroy

      lambda{ @n_2.reload }.should raise_error(MongoMapper::DocumentNotFound)
      @n_2_1.reload.reference.should      == [1,2]
      @n_2_1_1.reload.reference.should    == [1,2,1]
      @n_2_1_2.reload.reference.should    == [1,2,2]
      @n_2_1_2_1.reload.reference.should  == [1,2,2,1]
      @n_2_1_3.reload.reference.should    == [1,2,3]
    end

  end

  describe "#destroy_with_children" do

    # 1                  1
    # 1.1                1.1
    # 1.1.1              1.1.1
    # 1.1.2      =>      xxxxx
    # 1.1.2.1            xxxxx
    # 1.1.3              1.1.2

    it "should remove descendants and renumber siblings" do
      @n_1_1_2.destroy_with_children

      @n_1.reload.reference.should        == [1]
      @n_1_1.reload.reference.should      == [1,1]
      @n_1_1_1.reload.reference.should    == [1,1,1]
      lambda{ @n_1_1_2.reload   }.should raise_error(MongoMapper::DocumentNotFound)
      lambda{ @n_1_1_2_1.reload }.should raise_error(MongoMapper::DocumentNotFound)
      @n_1_1_3.reload.reference.should    == [1,1,2]
    end
  end

  describe "#depth" do
    it "should default to 1" do
      Node.new.depth.should == 1
    end
  end

  describe "#reference" do
    it "should default to [1]" do
      Node.new.reference.should == [1]
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

    it "should not renumber siblings or descendants" do
      @n_1.set_reference([1,2,3])
      @n_1_1.reference.should == [1,1]
    end
  end

  describe "#formatted_reference" do
    it "should join the reference numbers with dots" do
      @n_1_1_2_1.formatted_reference.should == "1.1.2.1"
    end
  end

  describe "indent" do
  end

  describe "outdent" do
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

  describe "#previous_siblings" do
    it "should return all nodes on the same level before the node" do
      @n_2_1_2.previous_siblings.should == [@n_2_1_1]
    end
  end

  describe "#next_siblings" do
    it "should return all nodes on the same level after the node" do
      @n_2_1_2.next_siblings.should == [@n_2_1_3]
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