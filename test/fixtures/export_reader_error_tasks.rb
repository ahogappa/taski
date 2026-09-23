# frozen_string_literal: true

require "taski"

# A user-defined export reader is called by TaskWrapper on behalf of the task
# that asked for the value — inside request_value when the dependency has
# already completed, or inside mark_completed when the requester was parked
# on it. Either way an exception from the reader belongs to the requester.
module ExportReaderErrorFixtures
  class RaisingReader < Taski::Task
    exports :value

    def value
      raise "reader boom"
    end

    def run
    end
  end

  # Pulls RaisingReader while it is still pending, so the requester is parked
  # as a waiter and receives the value from mark_completed.
  class WaitingRequester < Taski::Task
    def run
      RaisingReader.value
    end
  end

  # Prestarts RaisingReader and reads it only after it completed, so the
  # value is read inside request_value.
  class LateRequester < Taski::Task
    def run
      value = RaisingReader.value
      sleep 0.3
      value.to_s
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
