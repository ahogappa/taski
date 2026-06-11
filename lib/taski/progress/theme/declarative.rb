# frozen_string_literal: true

require "yaml"
require_relative "../info"
require_relative "base"
require_relative "default"
require_relative "plain"
require_relative "detail"
require_relative "compact"

module Taski
  module Progress
    module Theme
      # Raised when a data theme fails to load or validate. Distinct from the
      # ArgumentError Config raises for invalid theme CLASSES: load errors are
      # I/O + schema problems in a theme FILE (or hash).
      class LoadError < StandardError; end

      # Load a data theme from a YAML file. Returns an anonymous subclass of
      # the theme named by `extends` (IS-A Theme::Base, zero-arg .new) with the
      # validated, frozen definition baked in — so it satisfies Config's
      # existing theme contract unchanged.
      #
      # All validation happens here, fail-fast: unknown keys, type errors,
      # stray %, unknown placeholders all raise Theme::LoadError naming the
      # offending key. A theme that loads cannot fail at render time.
      #
      # @param path [String, Pathname] Path to the YAML theme file
      # @return [Class] Anonymous theme class
      # @raise [Theme::LoadError]
      def self.load(path)
        hash = begin
          YAML.safe_load_file(path)
        rescue Psych::Exception => e
          # Covers SyntaxError, AliasesNotEnabled (anchors/aliases/merge keys),
          # DisallowedClass (unquoted dates/timestamps), BadAlias — all of
          # which safe_load_file raises on ordinary malformed input.
          raise LoadError, "#{path}: invalid YAML: #{e.message}"
        rescue SystemCallError => e
          raise LoadError, "#{path}: #{e.message}"
        end
        Declarative.from_hash(hash, source: path.to_s)
      end

      # Programmatic variant of {Theme.load} for an already-parsed Hash.
      #
      # @param hash [Hash] Theme definition (string or symbol keys)
      # @return [Class] Anonymous theme class
      # @raise [Theme::LoadError]
      def self.from_hash(hash)
        Declarative.from_hash(hash)
      end

      # Data themes: progress display customization from an inert YAML file —
      # no code, safe to share and use without reading. Templates are
      # %{placeholder} format strings; the placeholder names ARE the
      # Theme::Base helper names (%{duration_part}, %{icon}, %{spinner}, ...),
      # so the Ruby-theme vocabulary and the data-theme vocabulary are one.
      #
      # {Declarative.from_hash} builds an anonymous class that REALLY inherits
      # from the `extends` theme with {Declarative::Behavior} layered on top.
      # Declared templates render from their format strings; everything
      # undeclared falls through to the extends theme's own methods — executed
      # on the same instance, so declared colors, icons, spinner frames,
      # formats, fragments and truncation knobs apply to fallback-rendered
      # lines too, exactly like a Ruby subclass would behave.
      #
      # Logic-free by design: the only-when-present guards live in the engine
      # (the same *_part methods Ruby themes use); only the wrapper strings,
      # icons, colors, spinner frames, formats and truncation knobs are data.
      # A theme that needs real control flow is a Ruby theme.
      #
      # @example
      #   Taski.progress.theme = "my-theme.yml"
      #   # or explicitly:
      #   Taski.progress.theme = Taski::Progress::Theme.load("my-theme.yml")
      module Declarative
        TEMPLATE_KEYS = %i[task_pending task_start task_success task_fail task_skip
          clean_start clean_success clean_fail group_start group_success group_fail
          execution_start execution_running execution_complete execution_fail].freeze
        EXECUTION_TEMPLATES = %i[execution_start execution_running execution_complete execution_fail].freeze
        EXTENDS = {"base" => Base, "default" => Default, "plain" => Plain,
                   "detail" => Detail, "compact" => Compact}.freeze

        # Validated, immutable result of loading a data theme.
        Definition = ::Data.define(:name, :templates, :icons, :colors, :spinner_frames,
          :spinner_interval, :render_interval, :formats, :truncation, :fragments, :extends_class)

        # Build an anonymous theme class with the validated definition baked
        # in at class level. The class inherits from the extends theme, so
        # `klass <= Theme::Base` holds and Config's zero-arg `.new` works.
        #
        # @raise [Theme::LoadError]
        def self.from_hash(hash, source: "(hash)")
          defn = Loader.new(hash, source: source).definition
          klass = Class.new(defn.extends_class) do
            include Behavior

            @definition = defn
            class << self
              attr_reader :definition
            end
          end
          Loader.validation_render!(klass, source)
          klass
        end

        # The data-theme layer: declared values win, everything else falls
        # through (`super`) to the extends theme — on the same instance.
        module Behavior
          def initialize
            @definition = self.class.definition or
              raise LoadError, "data themes must be built via Theme.load / Theme.from_hash"
            super
          end

          # 15 generated template methods: declared format string if present,
          # else the extends theme's own rendering (which sees the declared
          # colors/icons/etc. through the overrides below).
          TEMPLATE_KEYS.each do |key|
            define_method(key) do |task: nil, execution: nil|
              tpl = @definition.templates[key]
              next super(task: task, execution: execution) unless tpl
              format(tpl, **placeholders(key, task, execution))
            end
          end

          # === Config values: declared wins, else the extends theme ===
          # fetch-with-block keeps explicitly-declared "" values (Plain-style).

          def spinner_frames = @definition.spinner_frames || super

          def spinner_interval = @definition.spinner_interval || super

          def render_interval = @definition.render_interval || super

          def icon_success = @definition.icons.fetch(:success) { super }

          def icon_failure = @definition.icons.fetch(:failure) { super }

          def icon_pending = @definition.icons.fetch(:pending) { super }

          def icon_skip = @definition.icons.fetch(:skip) { super }

          def color_green = @definition.colors.fetch(:green) { super }

          def color_red = @definition.colors.fetch(:red) { super }

          def color_yellow = @definition.colors.fetch(:yellow) { super }

          def color_dim = @definition.colors.fetch(:dim) { super }

          def color_reset = @definition.colors.fetch(:reset) { super }

          def truncate_list_limit = @definition.truncation.fetch(:list_limit) { super }

          def truncate_list_separator = @definition.truncation.fetch(:list_separator) { super }

          def truncate_list_suffix = @definition.truncation.fetch(:list_suffix) { super }

          def truncate_text_max = @definition.truncation.fetch(:text_max) { super }

          def truncate_text_suffix = @definition.truncation.fetch(:text_suffix) { super }

          def format_count(count)
            tpl = @definition.formats[:count]
            return super unless tpl
            format(tpl, count: count)
          end

          # The >=1000ms branch stays engine logic; only the leaf strings are data.
          def format_duration(ms)
            return "" if ms.nil?
            s_tpl, ms_tpl = @definition.formats.values_at(:duration_s, :duration_ms)
            return super unless s_tpl || ms_tpl
            if ms >= 1000
              format(s_tpl || "%{s}s", s: (ms / 1000.0).round(1))
            else
              format(ms_tpl || "%{ms}ms", ms: ms)
            end
          end

          # === Fragment wrappers: the string is data, the presence guard is
          # engine-fixed. Undeclared fragments use the extends implementation,
          # which routes through the declared formats/knobs via self. ===

          def duration_part(duration)
            tpl = @definition.fragments[:duration_part]
            return super unless tpl
            return "" if duration.nil?
            format(tpl, duration: format_duration(duration), **color_placeholders)
          end

          def error_part(error_message)
            tpl = @definition.fragments[:error_part]
            return super unless tpl
            return "" if error_message.nil? || error_message.to_s.empty?
            format(tpl, error_message: error_message, **color_placeholders)
          end

          def stdout_part(stdout)
            tpl = @definition.fragments[:stdout_part]
            return super unless tpl
            return "" if stdout.nil? || stdout.to_s.empty?
            format(tpl, stdout: truncate_text(stdout, truncate_text_max), **color_placeholders)
          end

          def task_names_part(task_names)
            tpl = @definition.fragments[:task_names_part]
            return super unless tpl
            return "" if task_names.nil? || task_names.empty?
            format(tpl, task_names: joined_task_names(task_names), **color_placeholders)
          end

          private

          def color_placeholders
            {green: color_green, red: color_red, yellow: color_yellow, dim: color_dim, reset: color_reset}
          end

          def joined_task_names(names) = truncate_list(names.map { |n| short_name(n) }, truncate_list_limit)

          # The uniform payload: every template is formatted against the full
          # key set (absent data renders ""/"0"); Kernel#format ignores extra
          # keys, so one sample payload validates everything at load time.
          # Runs inside render_theme's rescue at render time — any surprise
          # isolates.
          def placeholders(key, task, execution)
            icon_state = EXECUTION_TEMPLATES.include?(key) ? execution&.state : task&.state
            {
              name: short_name(task&.name),
              full_name: task&.name.to_s,
              state: task&.state.to_s,
              duration: task&.duration ? format_duration(task.duration) : "",
              duration_part: duration_part(task&.duration),
              error_message: task&.error_message.to_s,
              error_part: error_part(task&.error_message),
              group_name: task&.group_name.to_s,
              stdout: task&.stdout ? truncate_text(task.stdout, truncate_text_max) : "",
              stdout_part: stdout_part(task&.stdout),
              root_task_name: short_name(execution&.root_task_name),
              done_count: format_count(execution&.done_count || 0),
              total_count: format_count(execution&.total_count || 0),
              failed_count: format_count(execution&.failed_count || 0),
              completed_count: format_count(execution&.completed_count || 0),
              skipped_count: format_count(execution&.skipped_count || 0),
              pending_count: format_count(execution&.pending_count || 0),
              total_duration: format_duration(execution&.total_duration || 0),
              task_names: (execution&.task_names && !execution.task_names.empty?) ? joined_task_names(execution.task_names) : "",
              task_names_part: task_names_part(execution&.task_names),
              spinner: spinner_frame(execution&.spinner_index),
              icon: icon_for(icon_state),
              **color_placeholders
            }
          end
        end

        # Validates a raw theme hash into a frozen Definition. Closed key sets
        # everywhere: anything unknown fails at load with the allowed keys in
        # the message, never silently at render.
        class Loader
          TOP_KEYS = %w[name schema extends templates icons colors spinner render_interval formats truncation fragments].freeze
          ICON_KEYS = %w[success failure pending skip].freeze
          COLOR_KEYS = %w[green red yellow dim reset].freeze
          SPINNER_KEYS = %w[frames interval].freeze
          FORMAT_KEYS = %w[count duration_ms duration_s].freeze
          TRUNCATION_KEYS = %w[list_limit list_separator list_suffix text_max text_suffix].freeze
          FRAGMENT_KEYS = %w[duration_part error_part stdout_part task_names_part].freeze
          INTEGER_TRUNCATION_KEYS = %w[list_limit text_max].freeze

          # Render/spinner intervals are seconds on background-thread sleeps:
          # non-finite or huge values would kill or wedge those threads, tiny
          # values busy-loop the CPU. Bounded here so a loaded theme can't.
          INTERVAL_RANGE = (0.01..60)

          # Fully-populated sample inputs for the validation render: with the
          # uniform payload, one render per declared template is exhaustive.
          SAMPLE_TASK = TaskInfo.new(name: "Sample::SampleTask", state: :completed,
            duration: 1234, error_message: "sample error", group_name: "sample",
            stdout: "sample output line")
          SAMPLE_EXECUTION = ExecutionInfo.new(state: :completed, pending_count: 1,
            done_count: 2, completed_count: 2, failed_count: 1, skipped_count: 1,
            total_count: 5, total_duration: 1234, root_task_name: "Sample::Root",
            task_names: ["Sample::SampleTask"], spinner_index: 0)

          def initialize(hash, source:)
            @source = source
            raise err("top level must be a mapping (got #{hash.class})") unless hash.is_a?(Hash)
            @hash = stringify_keys(hash)
            # Schema first: a future-schema file should fail with "unsupported
            # schema version", not with whatever unknown key it contains.
            schema_version!
            check_keys(@hash, TOP_KEYS, "top level")
          end

          def definition
            Definition.new(
              name: string_value("name"),
              templates: validated_templates,
              icons: section_of_strings("icons", ICON_KEYS),
              colors: section_of_strings("colors", COLOR_KEYS),
              spinner_frames: spinner_value("frames"),
              spinner_interval: spinner_value("interval"),
              render_interval: bounded_interval("render_interval", @hash["render_interval"]),
              formats: validated_format_strings("formats", FORMAT_KEYS),
              truncation: validated_truncation,
              fragments: validated_format_strings("fragments", FRAGMENT_KEYS),
              extends_class: extends_class
            ).freeze
          end

          # Render every declared template and fragment once against the fully
          # populated sample payload — catches unknown placeholders (KeyError)
          # and malformed format strings the percent check cannot see.
          def self.validation_render!(klass, source)
            theme = klass.new
            defn = klass.definition
            defn.templates.each_key do |key|
              theme.public_send(key, task: SAMPLE_TASK, execution: SAMPLE_EXECUTION)
            rescue KeyError => e
              raise LoadError, "#{source}: unknown placeholder in templates.#{key}: #{e.message}"
            rescue => e
              raise LoadError, "#{source}: malformed format string in templates.#{key}: #{e.message}"
            end
            {duration_part: -> { theme.duration_part(1234) },
             error_part: -> { theme.error_part("sample error") },
             stdout_part: -> { theme.stdout_part("sample output line") },
             task_names_part: -> { theme.task_names_part(["Sample::SampleTask"]) }}.each do |key, render|
              next unless defn.fragments.key?(key)
              begin
                render.call
              rescue KeyError => e
                raise LoadError, "#{source}: unknown placeholder in fragments.#{key}: #{e.message}"
              rescue => e
                raise LoadError, "#{source}: malformed format string in fragments.#{key}: #{e.message}"
              end
            end
            [123, 1500].each { |ms| theme.format_duration(ms) }
            theme.format_count(1)
          rescue KeyError => e
            raise LoadError, "#{source}: unknown placeholder in formats: #{e.message}"
          end

          private

          def err(message) = LoadError.new("#{@source}: #{message}")

          # Accept symbol keys everywhere a YAML file would have strings, so
          # from_hash works naturally from Ruby. One level of nesting is all
          # the schema has.
          def stringify_keys(hash)
            hash.to_h do |key, value|
              [key.to_s, value.is_a?(Hash) ? value.transform_keys(&:to_s) : value]
            end
          end

          def check_keys(hash, allowed, where)
            unknown = hash.keys - allowed
            return if unknown.empty?
            raise err("unknown key #{unknown.first.inspect} in #{where} (allowed: #{allowed.join(", ")})")
          end

          def schema_version!
            version = @hash.fetch("schema", 1)
            raise err("schema must be an Integer (got #{version.inspect})") unless version.is_a?(Integer)
            raise err("unsupported schema version #{version} (this taski supports 1)") unless version == 1
          end

          def section(name, allowed)
            value = @hash[name]
            return {} if value.nil?
            raise err("#{name} must be a mapping (got #{value.class})") unless value.is_a?(Hash)
            check_keys(value, allowed, name)
            value
          end

          def string_value(key)
            value = @hash[key]
            return nil if value.nil?
            raise err("#{key} must be a String (got #{value.class})") unless value.is_a?(String)
            value.dup.freeze
          end

          def extends_class
            value = @hash.fetch("extends", "default")
            EXTENDS.fetch(value) do
              raise err("unknown extends #{value.inspect} (allowed: #{EXTENDS.keys.join(", ")})")
            end
          end

          def validated_templates
            section("templates", TEMPLATE_KEYS.map(&:to_s)).each_with_object({}) do |(key, value), out|
              out[key.to_sym] = format_string!("templates.#{key}", value)
            end.freeze
          end

          def section_of_strings(name, allowed)
            section(name, allowed).each_with_object({}) do |(key, value), out|
              raise err("#{name}.#{key} must be a String (got #{value.class})") unless value.is_a?(String)
              out[key.to_sym] = value.dup.freeze
            end.freeze
          end

          def validated_format_strings(name, allowed)
            section(name, allowed).each_with_object({}) do |(key, value), out|
              out[key.to_sym] = format_string!("#{name}.#{key}", value)
            end.freeze
          end

          def spinner_value(key)
            spinner = section("spinner", SPINNER_KEYS)
            value = spinner[key]
            return nil if value.nil?
            case key
            when "frames"
              unless value.is_a?(Array) && value.all?(String)
                raise err("spinner.frames must be an Array of String")
              end
              value.map { |frame| frame.dup.freeze }.freeze
            when "interval"
              bounded_interval("spinner.interval", value)
            end
          end

          def bounded_interval(label, value)
            return nil if value.nil?
            unless value.is_a?(Numeric) && value.finite? && INTERVAL_RANGE.cover?(value)
              raise err("#{label} must be a number of seconds between #{INTERVAL_RANGE.min} and #{INTERVAL_RANGE.max} (got #{value.inspect})")
            end
            value
          end

          def validated_truncation
            section("truncation", TRUNCATION_KEYS).each_with_object({}) do |(key, value), out|
              if INTEGER_TRUNCATION_KEYS.include?(key)
                unless value.is_a?(Integer) && value.positive?
                  raise err("truncation.#{key} must be a positive Integer (got #{value.inspect})")
                end
                out[key.to_sym] = value
              else
                raise err("truncation.#{key} must be a String (got #{value.class})") unless value.is_a?(String)
                out[key.to_sym] = value.dup.freeze
              end
            end.freeze
          end

          # The vocabulary is %{...} plus %% only. Stripping those must leave
          # no % behind — this rejects %s/%d (which Kernel#format would
          # silently interpolate from the payload hash), lone %, unclosed %{,
          # and the %<name>s form.
          def format_string!(label, value)
            raise err("#{label} must be a String (got #{value.class})") unless value.is_a?(String)
            if value.gsub(/%%|%\{[^}]*\}/, "").include?("%")
              raise err("#{label} contains a stray % — the placeholder syntax is %{name}; escape a literal % as %%")
            end
            value.dup.freeze
          end
        end
      end
    end
  end
end
