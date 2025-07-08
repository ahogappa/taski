# frozen_string_literal: true

module Taski
  # Interface for tree display functionality
  # Provides common logic for displaying dependency trees
  module TreeDisplay
    # Color utilities for tree display
    # Provides ANSI color codes for enhanced tree visualization
    module TreeColors
      # ANSI color codes
      COLORS = {
        red: "\e[31m",
        green: "\e[32m",
        yellow: "\e[33m",
        blue: "\e[34m",
        magenta: "\e[35m",
        cyan: "\e[36m",
        gray: "\e[90m",
        reset: "\e[0m",
        bold: "\e[1m"
      }.freeze

      class << self
        # Check if colors should be enabled
        # @return [Boolean] true if colors should be used
        def enabled?
          return @enabled unless @enabled.nil?
          @enabled = tty? && !no_color?
        end

        # Enable or disable colors
        # @param value [Boolean] whether to enable colors
        attr_writer :enabled

        # Colorize text for Section names (blue)
        # @param text [String] text to colorize
        # @return [String] colorized text
        def section(text)
          colorize(text, :blue, bold: true)
        end

        # Colorize text for Task names (green)
        # @param text [String] text to colorize
        # @return [String] colorized text
        def task(text)
          colorize(text, :green)
        end

        # Colorize text for implementation candidates (yellow)
        # @param text [String] text to colorize
        # @return [String] colorized text
        def implementations(text)
          colorize(text, :yellow)
        end

        # Colorize tree connectors (gray)
        # @param text [String] text to colorize
        # @return [String] colorized text
        def connector(text)
          colorize(text, :gray)
        end

        private

        # Apply color to text
        # @param text [String] text to colorize
        # @param color [Symbol] color name
        # @param bold [Boolean] whether to make text bold
        # @return [String] colorized text
        def colorize(text, color, bold: false)
          return text unless enabled?

          result = ""
          result += COLORS[:bold] if bold
          result += COLORS[color]
          result += text
          result += COLORS[:reset]
          result
        end

        # Check if output is a TTY
        # @return [Boolean] true if stdout is a TTY
        def tty?
          $stdout.tty?
        end

        # Check if NO_COLOR environment variable is set
        # @return [Boolean] true if colors should be disabled
        def no_color?
          ENV.key?("NO_COLOR")
        end
      end
    end

    private

    # Render dependencies as tree structure
    # @param dependencies [Array] Array of dependency objects
    # @param prefix [String] Current indentation prefix
    # @param visited [Set] Set of visited classes
    # @param color [Boolean] Whether to use color output
    # @return [String] Formatted dependency tree string
    def render_dependencies_tree(dependencies, prefix, visited, color)
      result = ""

      dependencies = dependencies.uniq { |dep| extract_class(dep) }
      dependencies.each_with_index do |dep, index|
        dep_class = extract_class(dep)
        is_last = index == dependencies.length - 1

        connector_text = is_last ? "└── " : "├── "
        connector = color ? TreeColors.connector(connector_text) : connector_text
        child_prefix_text = is_last ? "    " : "│   "
        child_prefix = prefix + (color ? TreeColors.connector(child_prefix_text) : child_prefix_text)

        dep_tree = dep_class.tree(child_prefix, visited, color: color)

        dep_lines = dep_tree.lines
        if dep_lines.any?
          # Replace the first line prefix with connector
          first_line = dep_lines[0]
          fixed_first_line = first_line.sub(/^#{Regexp.escape(child_prefix)}/, prefix + connector)
          result += fixed_first_line
          # Add the rest of the lines as-is
          result += dep_lines[1..].join if dep_lines.length > 1
        else
          dep_name = color ? TreeColors.task(dep_class.name) : dep_class.name
          result += "#{prefix}#{connector}#{dep_name}\n"
        end
      end

      result
    end

    # Check for circular dependencies and handle visited set
    # @param visited [Set] Set of visited classes
    # @param current_class [Class] Current class being processed
    # @param prefix [String] Current indentation prefix
    # @return [Array] Returns [should_return_early, result_string, new_visited_set]
    def handle_circular_dependency_check(visited, current_class, prefix)
      if visited.include?(current_class)
        return [true, "#{prefix}#{current_class.name} (circular)\n", visited]
      end

      new_visited = visited.dup
      new_visited << current_class
      [false, nil, new_visited]
    end
  end
end
