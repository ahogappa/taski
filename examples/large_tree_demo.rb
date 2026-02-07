#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo: Large tree to test rendering performance
# Run with: ruby examples/large_tree_demo.rb

require_relative "../lib/taski"

# Leaf tasks (Layer 4) - 16 tasks
class Leaf01 < Taski::Task
  exports :value
  def run
    puts "Leaf01: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf01: Done!"
    @value = "leaf01"
  end
end

class Leaf02 < Taski::Task
  exports :value
  def run
    puts "Leaf02: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf02: Done!"
    @value = "leaf02"
  end
end

class Leaf03 < Taski::Task
  exports :value
  def run
    puts "Leaf03: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf03: Done!"
    @value = "leaf03"
  end
end

class Leaf04 < Taski::Task
  exports :value
  def run
    puts "Leaf04: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf04: Done!"
    @value = "leaf04"
  end
end

class Leaf05 < Taski::Task
  exports :value
  def run
    puts "Leaf05: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf05: Done!"
    @value = "leaf05"
  end
end

class Leaf06 < Taski::Task
  exports :value
  def run
    puts "Leaf06: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf06: Done!"
    @value = "leaf06"
  end
end

class Leaf07 < Taski::Task
  exports :value
  def run
    puts "Leaf07: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf07: Done!"
    @value = "leaf07"
  end
end

class Leaf08 < Taski::Task
  exports :value
  def run
    puts "Leaf08: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf08: Done!"
    @value = "leaf08"
  end
end

class Leaf09 < Taski::Task
  exports :value
  def run
    puts "Leaf09: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf09: Done!"
    @value = "leaf09"
  end
end

class Leaf10 < Taski::Task
  exports :value
  def run
    puts "Leaf10: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf10: Done!"
    @value = "leaf10"
  end
end

class Leaf11 < Taski::Task
  exports :value
  def run
    puts "Leaf11: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf11: Done!"
    @value = "leaf11"
  end
end

class Leaf12 < Taski::Task
  exports :value
  def run
    puts "Leaf12: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf12: Done!"
    @value = "leaf12"
  end
end

class Leaf13 < Taski::Task
  exports :value
  def run
    puts "Leaf13: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf13: Done!"
    @value = "leaf13"
  end
end

class Leaf14 < Taski::Task
  exports :value
  def run
    puts "Leaf14: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf14: Done!"
    @value = "leaf14"
  end
end

class Leaf15 < Taski::Task
  exports :value
  def run
    puts "Leaf15: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf15: Done!"
    @value = "leaf15"
  end
end

class Leaf16 < Taski::Task
  exports :value
  def run
    puts "Leaf16: Starting..."
    sleep(rand(0.1..0.3))
    puts "Leaf16: Done!"
    @value = "leaf16"
  end
end

# Middle tasks (Layer 3) - 8 tasks, each depends on 2 leaves
class Middle01 < Taski::Task
  exports :value
  def run
    puts "Middle01: Aggregating leaves..."
    Leaf01.value
    Leaf02.value
    sleep(0.05)
    puts "Middle01: Complete"
    @value = "middle01"
  end
end

class Middle02 < Taski::Task
  exports :value
  def run
    puts "Middle02: Aggregating leaves..."
    Leaf03.value
    Leaf04.value
    sleep(0.05)
    puts "Middle02: Complete"
    @value = "middle02"
  end
end

class Middle03 < Taski::Task
  exports :value
  def run
    puts "Middle03: Aggregating leaves..."
    Leaf05.value
    Leaf06.value
    sleep(0.05)
    puts "Middle03: Complete"
    @value = "middle03"
  end
end

class Middle04 < Taski::Task
  exports :value
  def run
    puts "Middle04: Aggregating leaves..."
    Leaf07.value
    Leaf08.value
    sleep(0.05)
    puts "Middle04: Complete"
    @value = "middle04"
  end
end

class Middle05 < Taski::Task
  exports :value
  def run
    puts "Middle05: Aggregating leaves..."
    Leaf09.value
    Leaf10.value
    sleep(0.05)
    puts "Middle05: Complete"
    @value = "middle05"
  end
end

class Middle06 < Taski::Task
  exports :value
  def run
    puts "Middle06: Aggregating leaves..."
    Leaf11.value
    Leaf12.value
    sleep(0.05)
    puts "Middle06: Complete"
    @value = "middle06"
  end
end

class Middle07 < Taski::Task
  exports :value
  def run
    puts "Middle07: Aggregating leaves..."
    Leaf13.value
    Leaf14.value
    sleep(0.05)
    puts "Middle07: Complete"
    @value = "middle07"
  end
end

class Middle08 < Taski::Task
  exports :value
  def run
    puts "Middle08: Aggregating leaves..."
    Leaf15.value
    Leaf16.value
    sleep(0.05)
    puts "Middle08: Complete"
    @value = "middle08"
  end
end

# Top tasks (Layer 2) - 4 tasks, each depends on 2 middles
class Top01 < Taski::Task
  exports :value
  def run
    Middle01.value
    Middle02.value
    sleep(0.05)
    @value = "top01"
  end
end

class Top02 < Taski::Task
  exports :value
  def run
    Middle03.value
    Middle04.value
    sleep(0.05)
    @value = "top02"
  end
end

class Top03 < Taski::Task
  exports :value
  def run
    Middle05.value
    Middle06.value
    sleep(0.05)
    @value = "top03"
  end
end

class Top04 < Taski::Task
  exports :value
  def run
    Middle07.value
    Middle08.value
    sleep(0.05)
    @value = "top04"
  end
end

# Branch tasks (Layer 1) - 2 tasks, each depends on 2 tops
class Branch01 < Taski::Task
  exports :value
  def run
    Top01.value
    Top02.value
    sleep(0.05)
    @value = "branch01"
  end
end

class Branch02 < Taski::Task
  exports :value
  def run
    Top03.value
    Top04.value
    sleep(0.05)
    @value = "branch02"
  end
end

# Root task (Layer 0)
class LargeTreeRoot < Taski::Task
  exports :result

  def run
    Branch01.value
    Branch02.value
    sleep(0.05)
    @result = "done"
  end
end

puts "Large Tree Demo"
puts "==============="
puts "Tree structure: 1 root -> 2 branch -> 4 top -> 8 middle -> 16 leaf (31 total)"
puts
puts "Static tree:"
puts LargeTreeRoot.tree
puts
puts "Running with progress display..."
puts

LargeTreeRoot.reset!
result = LargeTreeRoot.result

puts
puts "Result: #{result}"
