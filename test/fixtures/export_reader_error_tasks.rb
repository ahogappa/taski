# frozen_string_literal: true

require "taski"

# A user-defined export reader is called by TaskWrapper on behalf of the task
# that asked for the value — inside request_value when the dependency has
# already completed, or inside mark_completed when the requester was parked
# on it. Either way an exception from the reader belongs to the requester.
module ExportReaderErrorFixtures
  class RaisingReader < Taski::Task
    exports :value, :done

    def value
      raise "reader boom"
    end

    def run
      @done = true
    end
  end

  # Pulls RaisingReader while it is still pending, so the requester is parked
  # as a waiter and receives the value from mark_completed.
  class WaitingRequester < Taski::Task
    def run
      RaisingReader.value
    end
  end

  # Reads RaisingReader's non-raising export first, which only returns once
  # RaisingReader has completed, so the raising export is then read inside
  # request_value.
  class LateRequester < Taski::Task
    def run
      RaisingReader.done
      RaisingReader.value
    end
  end

  class RescuingRequester < Taski::Task
    exports :value

    def run
      @value = begin
        RaisingReader.value
      rescue => e
        "rescued: #{e.message}"
      end
    end
  end
end
