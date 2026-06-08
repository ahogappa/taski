# frozen_string_literal: true

require_relative "tree/structure"
require_relative "tree/live"
require_relative "tree/event"

module Taski
  module Progress
    module Layout
      # Tree layout for hierarchical task display.
      # Renders tasks in a tree structure with visual connectors.
      #
      # Tree has two implementations and picks the right one itself, so it
      # presents the same layout factory interface as Simple/Log — `.build` —
      # returning a Layout::Base instance:
      # - Tree::Live  — TTY periodic-update with spinner animation
      # - Tree::Event — Non-TTY event-driven incremental output
      #
      # Tree::Live / Tree::Event are internal; pick the layout via the Tree kind
      # and let it decide:
      #
      # @example
      #   Taski.progress.layout = Taski::Progress::Layout::Tree
      module Tree
        # Build the appropriate tree layout from the given options. Tree decides
        # which concrete class to use: Tree::Live for a TTY output, Tree::Event
        # otherwise. Matches the layout factory interface (.build) so the progress
        # Config can treat every layout uniformly.
        #
        # @param output [IO] Output stream (default: $stderr)
        # @param theme [Theme::Base, nil] Theme instance
        # @return [Tree::Live, Tree::Event]
        def self.build(output: $stderr, theme: nil)
          if output.respond_to?(:tty?) && output.tty?
            Live.new(output: output, theme: theme)
          else
            Event.new(output: output, theme: theme)
          end
        end
      end
    end
  end
end
