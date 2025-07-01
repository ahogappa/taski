# frozen_string_literal: true

module Taski
  module Progress
    # Color constants for progress display
    module DisplayColors
      COLORS = {
        reset: "\033[0m",
        bold: "\033[1m",
        dim: "\033[2m",
        cyan: "\033[36m",
        green: "\033[32m",
        red: "\033[31m"
      }.freeze
    end
  end
end
