require 'mongo_mapper'

module MongoMapper
  module Plugins
    module ReferencedTree

      module ClassMethods
        def referenced_tree(options={})
          options.reverse_merge!({
            :scope => nil
          })

          write_inheritable_attribute :referenced_tree_options, options
          class_inheritable_reader    :referenced_tree_options

          key :reference, Array
          key :depth,     Integer

          before_create :assign_reference
          after_destroy :delete_descendants_and_renumber_siblings

          # on create, renumber subsequent nodes
          # on update (if reference changed), renumber all subseqent to latest/prev position
        end

        # renumber a full set of nodes
        # pass the scope into the query to limit it to the nodes you want
        # Eg. Something.renumber_tree(:account_id => 123)
        # TODO - make this work on associations, IE account.nodes.renumber_tree
        def renumber_tree(query={})
          reference     = [0]
          level         = 1
          level_offset  = 0

          where(query).sort(:reference.asc).all.each do |node|

            # it's a level up
            if node.reference.size > (level + level_offset)
              if reference == [0]
                level_offset = 1
              else
                level             += 1
                reference[level-1] = 0
              end

            # back down a level or more
            elsif node.reference.size < (level + level_offset)
              level     = node.depth

              if level_offset > 0

                if level == 1
                  level_offset = 0
                else
                  level -= level_offset
                end
              end

              reference = reference[0, level]
            end

            reference[level-1] += 1

            node.set(:reference => reference)
          end
        end
      end

      module InstanceMethods

        # removes this node and renumbers siblings and descendants
        def destroy
          super
        end

        # removes this node and all descendants, renumbers siblings
        def destroy_with_children
          @destroy_descendants = true
          destroy
        end

        # Provides a formatted version of the reference
        #
        # [1,2,3] => "1.2.3"
        #
        # override this in your model if you want to format the references differently
        def formatted_reference
          reference.join(".")
        end

        def reference=(ref)
          self.depth = ref.size
          super
        end

        # set the reference without calling #save, so no callbacks are triggered
        # good for renumbering on mass without triggering auto-renumbering
        # but may end up with the tree being out of sync if you don't reorder all nodes
        def set_reference(ref)
          self.reference = ref
          set(:reference => ref, :depth => depth)
        end

        # increases the depth of the node if possible
        # can't indent if there's nothing before it on the same level (to become the new parent)
        def indent
        end

        # decreases the depth of the node if possible
        # can't outdent further than 1
        def outdent
        end

        # returns the parent for the node
        # so [1,2,3] would look for a node with reference of [1,2]
        def parent
          return if root?
          query         = query_for_reference(reference[0, depth-1])
          query[:depth] = depth - 1
          scoped_find.first(query)
        end

        def parent=(obj)
          ref = obj.reference

          if child = obj.children.last
            ref << (child.reference.last + 1)
          else
            ref << 1
          end

          self.reference = ref
        end

        def root?
          depth == 1
        end

        def root
          scoped_find.first(:"reference.0" => reference[0], :depth => 1)
        end

        def roots
          scoped_find.all(:depth => 1)
        end

        def ancestors
          return if root?
          scoped_find.all(:depth => {:"$lt" => depth}, :"reference.0" => reference[0])
        end

        def siblings
          query         = query_for_reference(reference[0, depth-1])
          query[:depth] = depth
          query[:id]    = {:"$ne" => self.id}
          scoped_find.all(query)
        end

        def previous_siblings
          query = query_for_reference(reference[0, depth-1])
          query[:"reference.#{depth-1}"] = {:"$lt" => reference.last}
          scoped_find.all(query)
        end

        def next_siblings
          query = query_for_reference(reference[0, depth-1])
          query[:"reference.#{depth-1}"] = {:"$gt" => reference.last}
          scoped_find.all(query)
        end

        def self_and_siblings
          query         = query_for_reference(reference[0, depth-1])
          query[:depth] = depth
          scoped_find.all(query)
        end

        def children
          query         = query_for_reference(reference[0, depth])
          query[:depth] = depth + 1
          scoped_find.all(query)
        end

        def descendants
          query         = query_for_reference(reference[0, depth])
          query[:depth] = {:"$gt" => depth}
          scoped_find.all(query)
        end

        def self_and_descendants
          [self] + descendants
        end

        def is_ancestor_of?(other)
          return false if other.depth <= depth
          other.reference[0, depth] == reference
        end

        def is_or_is_ancestor_of?(other)
          other == self || is_ancestor_of?(other)
        end

        def is_descendant_of?(other)
          return false if other.depth >= depth
          reference[0, other.depth] == other.reference
        end

        def is_or_is_descendant_of?(other)
          other == self || is_descendant_of?(other)
        end

        def is_sibling_of?(other)
          return false if other.depth != depth
          reference[0, depth-1] == other.reference[0, depth-1]
        end

        def is_or_is_sibling_of?(other)
          other == self || is_sibling_of?(other)
        end

        def destroy_descendants
        end

        private

        def query_for_reference(ref)
          query = {}
          ref.each_with_index do |r, i|
            query[:"reference.#{i}"] = r
          end
          query
        end

        def scoped_find
          if referenced_tree_options[:scope]
            self.class.sort(:reference.asc).where(referenced_tree_options[:scope] => self[referenced_tree_options[:scope]])
          else
            self.class.sort(:reference.asc)
          end
        end

        def assign_reference
          return unless reference.blank?

          if root_node = roots.last
            self.reference = [root_node.reference[0] + 1]
          else
            self.reference = [1]
          end
        end

        def delete_descendants_and_renumber_siblings
          if @destroy_descendants
            self.children.each do |child|
              child.destroy_with_children
            end
          end

          scope = {}
          if referenced_tree_options[:scope]
            scope[referenced_tree_options[:scope]] = self[referenced_tree_options[:scope]]
          end
          self.class.renumber_tree(scope)
        end
      end
    end
  end
end