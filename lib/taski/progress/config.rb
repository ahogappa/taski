# frozen_string_literal: true

module Taski
  module Progress
    # Configuration for progress display.
    # Holds class references for Layout and Theme, and builds display instances lazily.
    #
    # @example
    #   Taski.progress.layout = Taski::Progress::Layout::Tree
    #   Taski.progress.theme = Taski::Progress::Theme::Detail
    class Config
      attr_reader :layout, :theme, :output

      # @param on_invalidate [Proc, nil] Called when config changes (to clear external caches)
      def initialize(&on_invalidate)
        @layout = nil
        @theme = nil
        @output = nil
        @cached_display = nil
        @on_invalidate = on_invalidate
      end

      def layout=(klass)
        validate_layout!(klass) if klass
        @layout = klass
        invalidate!
      end

      def theme=(klass)
        validate_theme!(klass) if klass
        @theme = klass
        invalidate!
      end

      def output=(io)
        @output = io
        invalidate!
      end

      # Build a Layout instance from the current config.
      # Returns a cached instance if config hasn't changed.
      def build
        @cached_display ||= build_display
      end

      # Reset all settings to defaults.
      def reset
        @layout = nil
        @theme = nil
        @output = nil
        invalidate!
      end

      private

      def invalidate!
        @cached_display = nil
        @on_invalidate&.call
      end

      def build_display
        layout_ref = @layout || Layout::Simple
        args = {}
        args[:theme] = @theme.new if @theme
        args[:output] = @output if @output

        # Every layout exposes the same factory: .build(output:, theme:) returning
        # a Layout::Base instance. The layout itself decides which concrete class
        # to build (Simple/Log return their single class; Tree picks Live/Event).
        layout_ref.build(**args)
      end

      def validate_layout!(klass)
        # A layout is anything that responds to .build. That admits the public
        # layouts (Simple, Log, Tree) and custom ones, while rejecting instances,
        # non-layout classes, and the internal Tree::Live / Tree::Event variants
        # (which have no .build, so they can't be forced as a layout directly).
        unless klass.respond_to?(:build)
          raise ArgumentError, "layout must respond to .build (e.g. Simple, Log, Tree, or a custom layout), got #{klass.inspect}"
        end
      end

      def validate_theme!(klass)
        unless klass.is_a?(Class) && klass <= Theme::Base
          raise ArgumentError, "theme must be a subclass of Taski::Progress::Theme::Base, got #{klass.inspect}"
        end
      end
    end
  end
end
