# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "taski/execution/progress_features"

module Taski
  module Execution
    class TestProgressFeatures < Minitest::Test
      # ========================================
      # SpinnerAnimation Tests
      # ========================================
      class SpinnerHost
        include ProgressFeatures::SpinnerAnimation

        attr_reader :render_count

        def initialize
          @render_count = 0
        end

        def render_callback
          @render_count += 1
        end
      end

      def test_spinner_animation_default_frames
        SpinnerHost.new
        assert_equal %w[- \\ | /], ProgressFeatures::SpinnerAnimation::DEFAULT_FRAMES
      end

      def test_spinner_animation_current_frame_cycles
        host = SpinnerHost.new
        frames = %w[A B C]

        host.start_spinner(frames: frames, interval: 0.05) { host.render_callback }

        # Wait for a few cycles
        sleep 0.15
        host.stop_spinner

        # Should have called render at least once
        assert host.render_count > 0
      end

      def test_spinner_animation_stop_stops_thread
        host = SpinnerHost.new
        host.start_spinner(frames: %w[A B], interval: 0.01) { host.render_callback }

        sleep 0.03
        host.stop_spinner

        count_after_stop = host.render_count
        sleep 0.05

        # Count should not increase after stop
        assert_equal count_after_stop, host.render_count
      end

      def test_spinner_animation_current_frame_returns_frame
        host = SpinnerHost.new
        frames = %w[X Y Z]

        host.start_spinner(frames: frames, interval: 0.1) {}
        frame = host.current_frame
        host.stop_spinner

        assert_includes frames, frame
      end

      # ========================================
      # TerminalControl Tests
      # ========================================
      class TerminalHost
        include ProgressFeatures::TerminalControl

        attr_reader :output

        def initialize(output = StringIO.new)
          @output = output
        end
      end

      def test_terminal_control_hide_cursor
        output = StringIO.new
        host = TerminalHost.new(output)
        host.hide_cursor
        assert_equal "\e[?25l", output.string
      end

      def test_terminal_control_show_cursor
        output = StringIO.new
        host = TerminalHost.new(output)
        host.show_cursor
        assert_equal "\e[?25h", output.string
      end

      def test_terminal_control_clear_line
        output = StringIO.new
        host = TerminalHost.new(output)
        host.clear_line
        assert_equal "\r\e[K", output.string
      end

      def test_terminal_control_move_cursor_up
        output = StringIO.new
        host = TerminalHost.new(output)
        host.move_cursor_up(3)
        assert_equal "\e[3A", output.string
      end

      def test_terminal_control_use_alternate_buffer
        output = StringIO.new
        host = TerminalHost.new(output)
        host.use_alternate_buffer
        assert_equal "\e[?1049h", output.string
      end

      def test_terminal_control_restore_buffer
        output = StringIO.new
        host = TerminalHost.new(output)
        host.restore_buffer
        assert_equal "\e[?1049l", output.string
      end

      def test_terminal_control_tty_returns_false_for_stringio
        output = StringIO.new
        host = TerminalHost.new(output)
        refute host.tty?
      end

      def test_terminal_control_terminal_width_default
        output = StringIO.new
        host = TerminalHost.new(output)
        assert_equal 80, host.terminal_width
      end

      def test_terminal_control_terminal_height_default
        output = StringIO.new
        host = TerminalHost.new(output)
        assert_equal 24, host.terminal_height
      end

      # ========================================
      # AnsiColors Tests
      # ========================================
      class ColorHost
        include ProgressFeatures::AnsiColors
      end

      def test_ansi_colors_colorize_single_style
        host = ColorHost.new
        result = host.colorize("test", :red)
        assert_equal "\e[31mtest\e[0m", result
      end

      def test_ansi_colors_colorize_multiple_styles
        host = ColorHost.new
        result = host.colorize("test", :bold, :green)
        assert_equal "\e[1;32mtest\e[0m", result
      end

      def test_ansi_colors_colorize_no_styles
        host = ColorHost.new
        result = host.colorize("test")
        assert_equal "test", result
      end

      def test_ansi_colors_status_color
        host = ColorHost.new
        assert_equal :green, host.status_color(:completed)
        assert_equal :red, host.status_color(:failed)
        assert_equal :yellow, host.status_color(:running)
        assert_equal :gray, host.status_color(:pending)
      end

      # ========================================
      # Formatting Tests
      # ========================================
      class FormattingHost
        include ProgressFeatures::Formatting
      end

      def test_formatting_short_name
        host = FormattingHost.new
        mock_class = Class.new
        Object.const_set(:MyModule, Module.new) unless defined?(MyModule)
        MyModule.const_set(:MyTask, mock_class) unless defined?(MyModule::MyTask)

        assert_equal "MyTask", host.short_name(MyModule::MyTask)
      end

      def test_formatting_short_name_handles_nil
        host = FormattingHost.new
        assert_equal "Unknown", host.short_name(nil)
      end

      def test_formatting_format_duration_milliseconds
        host = FormattingHost.new
        assert_equal "123.5ms", host.format_duration(123.456)
      end

      def test_formatting_format_duration_seconds
        host = FormattingHost.new
        assert_equal "1.5s", host.format_duration(1500)
      end

      def test_formatting_truncate
        host = FormattingHost.new
        assert_equal "Hello...", host.truncate("Hello World!", 8)
        assert_equal "Short", host.truncate("Short", 10)
      end

      # ========================================
      # TreeRendering Tests
      # ========================================
      class TreeHost
        include ProgressFeatures::TreeRendering
      end

      def test_tree_rendering_tree_prefix_last
        host = TreeHost.new
        assert_equal "\e[90m\u2514\u2500\u2500 \e[0m", host.tree_prefix(1, true)
      end

      def test_tree_rendering_tree_prefix_not_last
        host = TreeHost.new
        assert_equal "\e[90m\u251c\u2500\u2500 \e[0m", host.tree_prefix(1, false)
      end

      def test_tree_rendering_tree_prefix_root
        host = TreeHost.new
        assert_equal "", host.tree_prefix(0, true)
      end

      def test_tree_rendering_tree_indent
        host = TreeHost.new
        # When parent was last, use spaces
        assert_equal "\e[90m    \e[0m", host.tree_indent(1, [true])
        # When parent was not last, use vertical bar
        assert_equal "\e[90m\u2502   \e[0m", host.tree_indent(1, [false])
      end

      def test_tree_rendering_each_tree_node
        host = TreeHost.new
        tree = {
          task_class: "Root",
          children: [
            {task_class: "Child1", children: []},
            {task_class: "Child2", children: [
              {task_class: "GrandChild", children: []}
            ]}
          ]
        }

        visited = []
        host.each_tree_node(tree) do |node, depth, is_last|
          visited << {name: node[:task_class], depth: depth, is_last: is_last}
        end

        assert_equal 4, visited.size
        assert_equal({name: "Root", depth: 0, is_last: true}, visited[0])
        assert_equal({name: "Child1", depth: 1, is_last: false}, visited[1])
        assert_equal({name: "Child2", depth: 1, is_last: true}, visited[2])
        assert_equal({name: "GrandChild", depth: 2, is_last: true}, visited[3])
      end

      # ========================================
      # ProgressTracking Tests
      # ========================================
      class TrackingHost
        include ProgressFeatures::ProgressTracking

        def initialize
          init_progress_tracking
        end
      end

      def test_progress_tracking_register_task
        host = TrackingHost.new
        mock_task = Class.new
        Object.const_set(:MockTask, mock_task) unless defined?(MockTask)

        host.register_task(MockTask)
        assert_equal :pending, host.task_state(MockTask)
      end

      def test_progress_tracking_update_task_state
        host = TrackingHost.new
        mock_task = Class.new
        Object.const_set(:MockTask2, mock_task) unless defined?(MockTask2)

        host.register_task(MockTask2)
        host.update_task_state(MockTask2, :running, nil, nil)
        assert_equal :running, host.task_state(MockTask2)

        host.update_task_state(MockTask2, :completed, 100.5, nil)
        assert_equal :completed, host.task_state(MockTask2)
      end

      def test_progress_tracking_completed_count
        host = TrackingHost.new
        task1 = Class.new
        task2 = Class.new
        Object.const_set(:CountTask1, task1) unless defined?(CountTask1)
        Object.const_set(:CountTask2, task2) unless defined?(CountTask2)

        host.register_task(CountTask1)
        host.register_task(CountTask2)

        assert_equal 0, host.completed_count

        host.update_task_state(CountTask1, :completed, 100, nil)
        assert_equal 1, host.completed_count

        host.update_task_state(CountTask2, :completed, 100, nil)
        assert_equal 2, host.completed_count
      end

      def test_progress_tracking_total_count
        host = TrackingHost.new
        task1 = Class.new
        task2 = Class.new
        Object.const_set(:TotalTask1, task1) unless defined?(TotalTask1)
        Object.const_set(:TotalTask2, task2) unless defined?(TotalTask2)

        host.register_task(TotalTask1)
        host.register_task(TotalTask2)

        assert_equal 2, host.total_count
      end

      def test_progress_tracking_running_tasks
        host = TrackingHost.new
        task1 = Class.new
        task2 = Class.new
        Object.const_set(:RunningTask1, task1) unless defined?(RunningTask1)
        Object.const_set(:RunningTask2, task2) unless defined?(RunningTask2)

        host.register_task(RunningTask1)
        host.register_task(RunningTask2)

        host.update_task_state(RunningTask1, :running, nil, nil)
        assert_equal [RunningTask1], host.running_tasks
      end

      def test_progress_tracking_progress_summary
        host = TrackingHost.new
        task1 = Class.new
        task2 = Class.new
        task3 = Class.new
        Object.const_set(:SummaryTask1, task1) unless defined?(SummaryTask1)
        Object.const_set(:SummaryTask2, task2) unless defined?(SummaryTask2)
        Object.const_set(:SummaryTask3, task3) unless defined?(SummaryTask3)

        host.register_task(SummaryTask1)
        host.register_task(SummaryTask2)
        host.register_task(SummaryTask3)

        host.update_task_state(SummaryTask1, :completed, 100, nil)
        host.update_task_state(SummaryTask2, :running, nil, nil)
        host.update_task_state(SummaryTask3, :failed, nil, StandardError.new("oops"))

        summary = host.progress_summary
        assert_equal 1, summary[:completed]
        assert_equal 3, summary[:total]
        assert_equal [SummaryTask2], summary[:running]
        assert_equal [SummaryTask3], summary[:failed]
      end
    end
  end
end
