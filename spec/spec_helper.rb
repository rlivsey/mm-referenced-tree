$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'rubygems'
gem 'rspec'

require 'mm-referenced-tree'
require 'spec'

MongoMapper.database = 'mm-referenced-tree-spec'

class Node
  include MongoMapper::Document

  plugin MongoMapper::Plugins::ReferencedTree
  referenced_tree :scope => :account_id

  key :name, String
  key :account_id, ObjectId
end

class Account
  include MongoMapper::Document

  key :name, String
  many :nodes
end

Spec::Runner.configure do |config|
  config.before(:each) do
    MongoMapper.database.collections.each do |collection|
      unless collection.name.match(/^system\./)
        collection.remove
      end
    end
  end
end
