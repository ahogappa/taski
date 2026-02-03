# frozen_string_literal: true

module Taski
  module Execution
    module Template
      # Base class for template definitions.
      # Template classes are thin layers that only return Liquid template strings.
      # Rendering (Liquid parsing) is handled by Layout classes.
      #
      # Users can subclass this to create custom templates:
      #
      #   class MyTemplate < Taski::Execution::Template::Base
      #     def task_start
      #       "Starting {{ task_name }}..."
      #     end
      #   end
      #
      #   layout = Taski::Execution::Layout::Plain.new(template: MyTemplate.new)
      class Base
        # === Task lifecycle templates ===

        # Template shown when a task starts running
        # @return [String] Liquid template string
        def task_start
          "[START] {{ task_name }}"
        end

        # Template shown when a task completes successfully
        # Available variables: task_name, duration (optional)
        # @return [String] Liquid template string
        def task_success
          "[DONE] {{ task_name }}{% if duration %} ({{ duration }}){% endif %}"
        end

        # Template shown when a task fails
        # Available variables: task_name, error_message (optional)
        # @return [String] Liquid template string
        def task_fail
          "[FAIL] {{ task_name }}{% if error_message %}: {{ error_message }}{% endif %}"
        end

        # === Clean lifecycle templates ===

        # Template shown when a task's clean phase starts
        # @return [String] Liquid template string
        def clean_start
          "[CLEAN] {{ task_name }}"
        end

        # Template shown when a task's clean phase completes
        # Available variables: task_name, duration (optional)
        # @return [String] Liquid template string
        def clean_success
          "[CLEAN DONE] {{ task_name }}{% if duration %} ({{ duration }}){% endif %}"
        end

        # Template shown when a task's clean phase fails
        # Available variables: task_name, error_message (optional)
        # @return [String] Liquid template string
        def clean_fail
          "[CLEAN FAIL] {{ task_name }}{% if error_message %}: {{ error_message }}{% endif %}"
        end

        # === Group lifecycle templates ===

        # Template shown when a group starts
        # Available variables: task_name, group_name
        # @return [String] Liquid template string
        def group_start
          '[GROUP] {{ task_name }}#{{ group_name }}'
        end

        # Template shown when a group completes successfully
        # Available variables: task_name, group_name, duration (optional)
        # @return [String] Liquid template string
        def group_success
          '[GROUP DONE] {{ task_name }}#{{ group_name }}{% if duration %} ({{ duration }}){% endif %}'
        end

        # Template shown when a group fails
        # Available variables: task_name, group_name, error_message (optional)
        # @return [String] Liquid template string
        def group_fail
          '[GROUP FAIL] {{ task_name }}#{{ group_name }}{% if error_message %}: {{ error_message }}{% endif %}'
        end

        # === Execution lifecycle templates ===

        # Template shown when execution begins
        # Available variables: root_task_name
        # @return [String] Liquid template string
        def execution_start
          "[TASKI] Starting {{ root_task_name }}"
        end

        # Template shown when all tasks complete successfully
        # Available variables: completed, total, duration
        # @return [String] Liquid template string
        def execution_complete
          "[TASKI] Completed: {{ completed }}/{{ total }} tasks ({{ duration }}ms)"
        end

        # Template shown when execution ends with failures
        # Available variables: failed, total, duration
        # @return [String] Liquid template string
        def execution_fail
          "[TASKI] Failed: {{ failed }}/{{ total }} tasks ({{ duration }}ms)"
        end
      end
    end
  end
end
