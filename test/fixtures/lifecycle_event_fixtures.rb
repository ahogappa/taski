# frozen_string_literal: true

require_relative "../../lib/taski"

# Test fixtures for lifecycle event order testing.
# These are file-based classes (not Class.new) to ensure static analysis
# correctly resolves dependencies through Prism source_location parsing.

class LifecycleLeafTask < Taski::Task
  exports :leaf_value

  def run
    @leaf_value = "leaf"
  end

  def clean
    @leaf_value = nil
  end
end

class LifecycleParentTask < Taski::Task
  exports :parent_value

  def run
    @parent_value = "parent:#{LifecycleLeafTask.leaf_value}"
  end

  def clean
    @parent_value = nil
  end
end
