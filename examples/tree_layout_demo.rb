#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo: Layout::Tree with Template::Default
# This demonstrates the Template/Layout separation where:
# - Template defines "what one line looks like" (task_start, task_success, etc.)
# - Layout defines "how lines are arranged" (tree structure, prefixes)

require_relative "../lib/taski"
require_relative "../lib/taski/progress/layout/tree"
require_relative "../lib/taski/progress/template/default"

# Create tasks with nested dependencies
class DbTask < Taski::Task
  def run
  end
end

class CacheTask < Taski::Task
  def run
  end
end

class ApiTask < Taski::Task
  def run
    DbTask.value
    CacheTask.value
  end
end

class WebTask < Taski::Task
  def run
    ApiTask.value
  end
end

puts "=== Layout::Tree + Template::Default Demo ==="
puts
puts "Task structure:"
puts "  WebTask (root)"
puts "  └── ApiTask"
puts "      ├── DbTask"
puts "      └── CacheTask"
puts

output = StringIO.new
layout = Taski::Progress::Layout::Tree.new(output: output)

layout.set_root_task(WebTask)
layout.start

# Simulate execution (dependencies run first)
layout.update_task(DbTask, state: :running)
layout.update_task(CacheTask, state: :running)
layout.update_task(CacheTask, state: :completed, duration: 30)
layout.update_task(DbTask, state: :completed, duration: 80)

layout.update_task(ApiTask, state: :running)
layout.update_task(ApiTask, state: :completed, duration: 50)

layout.update_task(WebTask, state: :running)
layout.update_task(WebTask, state: :completed, duration: 20)

layout.stop

puts "Output:"
puts output.string
