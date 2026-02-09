# frozen_string_literal: true

require "taski"

module MessageFixtures
  class MessageOutputTask < Taski::Task
    exports :result

    def run
      Taski.message("Created: /path/to/output.txt")
      Taski.message("Summary: 42 items processed")
      @result = "done"
    end
  end
end
