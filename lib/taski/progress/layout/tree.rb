# frozen_string_literal: true

require_relative "tree/structure"
require_relative "tree/live"
require_relative "tree/event"

module Taski
  module Progress
    module Layout
      # Tree layout module for hierarchical task display.
      # Renders tasks in a tree structure with visual connectors.
      #
      # Contains two implementations:
      # - Tree::Live  — TTY periodic-update with spinner animation
      # - Tree::Event — Non-TTY event-driven incremental output
      #
      # Use Tree.for to automatically select the appropriate implementation.
      #
      # @example Auto-select based on output TTY
      #   layout = Taski::Progress::Layout::Tree.for
      #
      # @example Explicit selection
      #   layout = Taski::Progress::Layout::Tree::Live.new   # TTY
      #   layout = Taski::Progress::Layout::Tree::Event.new  # non-TTY
      module Tree
        # Factory method to create the appropriate tree layout.
        # Returns Tree::Live for TTY outputs, Tree::Event otherwise.
        #
        # @param output [IO] Output stream (default: $stderr)
        # @param theme [Theme::Base, nil] Theme instance
        # @return [Tree::Live, Tree::Event]
        def self.for(output: $stderr, theme: nil)
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
