# frozen_string_literal: true

module Taski
  # Signal handling utilities for task interruption
  class SignalHandler
    # Default signals to handle
    DEFAULT_SIGNALS = %w[INT TERM USR1].freeze

    def initialize(signals: DEFAULT_SIGNALS)
      @signals = signals
      @signal_received = false
      @signal_name = nil
      @signal_handlers = {}
    end

    def self.setup_signal_traps(signals: DEFAULT_SIGNALS)
      # Class method for setting up signal traps
      new(signals: signals).setup_signal_traps
    end

    def setup_signal_traps
      # Skip signal trapping during tests to avoid test interference
      return if ENV["MINITEST_TEST"] || defined?(Minitest)

      @signals.each do |signal|
        setup_signal_trap(signal)
      end
    end

    def convert_signal_to_exception(signal_name)
      strategy = SignalExceptionStrategy.for_signal(signal_name)
      strategy.create_exception(signal_name)
    end

    def signal_received?
      @signal_received
    end

    attr_reader :signal_name

    private

    def setup_signal_trap(signal)
      Signal.trap(signal) do
        @signal_received = true
        @signal_name = signal
      end
    rescue ArgumentError => e
      # Handle unsupported signals gracefully
      warn "Warning: Unable to trap signal #{signal}: #{e.message}"
    end
  end

  # Strategy pattern for different signal exception types
  module SignalExceptionStrategy
    class BaseStrategy
      def self.create_exception(signal_name)
        raise NotImplementedError, "Subclass must implement create_exception"
      end
    end

    class InterruptStrategy < BaseStrategy
      def self.create_exception(signal_name)
        TaskInterruptedException.new("interrupted by SIG#{signal_name}")
      end
    end

    class TerminateStrategy < BaseStrategy
      def self.create_exception(signal_name)
        TaskInterruptedException.new("terminated by SIG#{signal_name}")
      end
    end

    class UserSignalStrategy < BaseStrategy
      def self.create_exception(signal_name)
        TaskInterruptedException.new("user signal received: SIG#{signal_name}")
      end
    end

    STRATEGIES = {
      "INT" => InterruptStrategy,
      "TERM" => TerminateStrategy,
      "USR1" => UserSignalStrategy,
      "USR2" => UserSignalStrategy
    }.freeze

    def self.for_signal(signal_name)
      STRATEGIES[signal_name] || InterruptStrategy
    end
  end
end
