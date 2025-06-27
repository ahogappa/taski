# frozen_string_literal: true

module Taski
  # Terminal control operations with ANSI escape sequences
  class TerminalController
    # ANSI escape sequences
    MOVE_UP = "\033[A"
    CLEAR_LINE = "\033[K"
    MOVE_UP_AND_CLEAR = "#{MOVE_UP}#{CLEAR_LINE}"

    def initialize(output)
      @output = output
    end

    def clear_lines(count)
      return if count == 0

      count.times { @output.print MOVE_UP_AND_CLEAR }
    end

    def puts(text)
      @output.puts text
    end

    def print(text)
      @output.print text
    end

    def flush
      @output.flush
    end
  end

  # Spinner animation with dots-style characters
  class SpinnerAnimation
    SPINNER_CHARS = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"].freeze
    FRAME_DELAY = 0.1

    def initialize
      @frame = 0
      @running = false
      @thread = nil
    end

    def start(terminal, task_name, &display_callback)
      return if @running

      @running = true
      @frame = 0

      @thread = Thread.new do
        while @running
          current_char = SPINNER_CHARS[@frame % SPINNER_CHARS.length]
          display_callback&.call(current_char, task_name)

          @frame += 1
          sleep FRAME_DELAY
        end
      rescue
        # Silently handle thread errors
      end
    end

    def stop
      @running = false
      @thread&.join(0.2)
      @thread = nil
    end

    def running?
      @running
    end
  end

  # Captures stdout and maintains last N lines like tail -f
  class OutputCapture
    MAX_LINES = 10
    DISPLAY_LINES = 5

    def initialize(main_output)
      @main_output = main_output
      @buffer = []
      @capturing = false
      @original_stdout = nil
      @pipe_reader = nil
      @pipe_writer = nil
      @capture_thread = nil
    end

    def start
      return if @capturing

      @buffer.clear
      setup_stdout_redirection
      @capturing = true

      start_capture_thread
    end

    def stop
      return unless @capturing

      @capturing = false

      # Restore stdout
      restore_stdout

      # Clean up pipes and thread
      cleanup_capture_thread
      cleanup_pipes
    end

    def last_lines
      @buffer.last(DISPLAY_LINES)
    end

    def capturing?
      @capturing
    end

    private

    def setup_stdout_redirection
      @original_stdout = $stdout
      @pipe_reader, @pipe_writer = IO.pipe
      $stdout = @pipe_writer
    end

    def restore_stdout
      return unless @original_stdout

      $stdout = @original_stdout
      @original_stdout = nil
    end

    def start_capture_thread
      @capture_thread = Thread.new do
        while (line = @pipe_reader.gets)
          line = line.chomp
          next if line.empty?
          next if skip_line?(line)

          add_line_to_buffer(line)
        end
      rescue IOError
        # Pipe closed, normal termination
      end
    end

    def skip_line?(line)
      # Skip logger lines (they appear separately)
      line.match?(/^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\]/)
    end

    def add_line_to_buffer(line)
      @buffer << line
      @buffer.shift while @buffer.length > MAX_LINES
    end

    def cleanup_capture_thread
      @capture_thread&.join(0.1)
      @capture_thread = nil
    end

    def cleanup_pipes
      [@pipe_writer, @pipe_reader].each do |pipe|
        pipe&.close
      rescue IOError
        # Already closed, ignore
      end
      @pipe_writer = @pipe_reader = nil
    end
  end

  # Represents task execution status
  class TaskStatus
    attr_reader :name, :duration, :error

    def initialize(name:, duration: nil, error: nil)
      @name = name
      @duration = duration
      @error = error
    end

    def success?
      @error.nil?
    end

    def failure?
      !success?
    end

    def duration_ms
      return nil unless @duration
      (@duration * 1000).round(1)
    end

    def icon
      success? ? "✅" : "❌"
    end

    def format_duration
      return "" unless duration_ms
      "(#{duration_ms}ms)"
    end
  end

  # Main progress display controller
  class ProgressDisplay
    # ANSI colors
    COLORS = {
      reset: "\033[0m",
      bold: "\033[1m",
      dim: "\033[2m",
      cyan: "\033[36m",
      green: "\033[32m",
      red: "\033[31m"
    }.freeze

    def initialize(output: $stdout, force_enable: nil)
      @output = output
      @terminal = TerminalController.new(output)
      @spinner = SpinnerAnimation.new
      @output_capture = OutputCapture.new(output)

      # Enable if TTY or force enabled or environment variable set
      @enabled = force_enable.nil? ? (output.tty? || ENV["TASKI_FORCE_PROGRESS"] == "1") : force_enable

      @completed_tasks = []
      @current_display_lines = 0
    end

    def start_task(task_name, dependencies: [])
      puts "DEBUG: start_task called for #{task_name}, enabled: #{@enabled}" if ENV["TASKI_DEBUG"]
      return unless @enabled

      clear_current_display
      @output_capture.start

      start_spinner_display(task_name)
    end

    def complete_task(task_name, duration:)
      return unless @enabled

      status = TaskStatus.new(name: task_name, duration: duration)
      finish_task(status)
    end

    def fail_task(task_name, error:, duration:)
      return unless @enabled

      status = TaskStatus.new(name: task_name, duration: duration, error: error)
      finish_task(status)
    end

    def clear
      return unless @enabled

      @spinner.stop
      @output_capture.stop
      clear_current_display

      # Display final summary of all completed tasks
      if @completed_tasks.any?
        @completed_tasks.each do |status|
          @terminal.puts format_completed_task(status)
        end
        @terminal.flush
      end

      @completed_tasks.clear
      @current_display_lines = 0
    end

    def enabled?
      @enabled
    end

    private

    def start_spinner_display(task_name)
      @spinner.start(@terminal, task_name) do |spinner_char, name|
        display_current_state(spinner_char, name)
      end
    end

    def display_current_state(spinner_char, task_name)
      clear_current_display

      lines_count = 0

      # Only display current task with spinner (no past completed tasks during execution)
      @terminal.puts format_current_task(spinner_char, task_name)
      lines_count += 1

      # Display output lines
      @output_capture.last_lines.each do |line|
        @terminal.puts format_output_line(line)
        lines_count += 1
      end

      @current_display_lines = lines_count
      @terminal.flush
    end

    def finish_task(status)
      @spinner.stop
      @output_capture.stop
      clear_current_display

      @completed_tasks << status
      display_final_state
    end

    def display_final_state
      # Only display the newly completed task (last one)
      if @completed_tasks.any?
        latest_task = @completed_tasks.last
        @terminal.puts format_completed_task(latest_task)
      end
      @terminal.flush
      @current_display_lines = 1  # Only one line for the latest task
    end

    def format_completed_task(status)
      color = status.success? ? COLORS[:green] : COLORS[:red]
      "#{color}#{COLORS[:bold]}#{status.icon} #{status.name}#{COLORS[:reset]} #{COLORS[:dim]}#{status.format_duration}#{COLORS[:reset]}"
    end

    def format_current_task(spinner_char, task_name)
      "#{COLORS[:cyan]}#{spinner_char}#{COLORS[:reset]} #{COLORS[:bold]}#{task_name}#{COLORS[:reset]}"
    end

    def format_output_line(line)
      "  #{COLORS[:dim]}#{line}#{COLORS[:reset]}"
    end

    def clear_current_display
      @terminal.clear_lines(@current_display_lines)
      @current_display_lines = 0
    end
  end
end
