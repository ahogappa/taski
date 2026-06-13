# frozen_string_literal: true

require_relative "base"

module Taski
  module Progress
    module Theme
      # Default theme inheriting from Theme::Base.
      #
      # Note: Theme::Base provides ANSI color helper methods (color_red,
      # color_green, etc.) which return escape codes by default. Theme methods
      # that use them (via colorize/icon_for) emit escape codes in their output.
      #
      # For guaranteed plain text output without any terminal escape codes,
      # use Theme::Plain instead, which overrides all color methods to
      # return empty strings.
      #
      # @see Taski::Progress::Theme::Base Base class with color helpers
      # @see Taski::Progress::Theme::Plain Plain output without escape codes
      class Default < Base
        # Inherits all methods from Base.
      end
    end
  end
end
