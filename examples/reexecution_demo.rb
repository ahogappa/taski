#!/usr/bin/env ruby
# frozen_string_literal: true

# Taski Scope-Based Execution Demo
#
# This example demonstrates the execution model:
# - Task.run / Task.value: Fresh execution every time
# - Dependencies within same execution scope share results
#
# Run: ruby examples/reexecution_demo.rb

require_relative "../lib/taski"

puts "Taski Scope-Based Execution Demo"
puts "=" * 50

# Task that generates random values (to demonstrate execution behavior)
class RandomGenerator < Taski::Task
  exports :value, :timestamp

  def run
    @value = rand(1000)
    @timestamp = Time.now.strftime("%H:%M:%S.%L")
    puts "  RandomGenerator.run called: value=#{@value}, time=#{@timestamp}"
    @value
  end
end

# Task that depends on RandomGenerator
class Consumer < Taski::Task
  exports :result

  def run
    random_value = RandomGenerator.value
    @result = "Consumed: #{random_value}"
    puts "  Consumer.run called with RandomGenerator.value=#{random_value}"
    @result
  end
end

# Task that accesses RandomGenerator twice
class DoubleConsumer < Taski::Task
  exports :first_value, :second_value

  def run
    @first_value = RandomGenerator.value
    puts "  DoubleConsumer: first access = #{@first_value}"
    @second_value = RandomGenerator.value
    puts "  DoubleConsumer: second access = #{@second_value}"
  end
end

puts "\n1. Class Method Calls: Fresh Execution Every Time"
puts "-" * 50
puts "Each Task.value call creates a NEW execution:"
puts "\nFirst call:"
value1 = RandomGenerator.value
puts "  => #{value1}"

puts "\nSecond call (NEW execution, different value):"
value2 = RandomGenerator.value
puts "  => #{value2}"

puts "\nValues are different: #{value1 != value2}"

puts "\n" + "=" * 50
puts "\n2. Scope-Based Caching for Dependencies"
puts "-" * 50
puts "Within ONE execution, dependencies are cached:"

puts "\nDoubleConsumer accesses RandomGenerator.value twice:"
DoubleConsumer.run

puts "\nNote: Both accesses return the SAME value!"
puts "(Because they're in the same execution scope)"

puts "\n" + "=" * 50
puts "\n3. Dependency Chain with Fresh Execution"
puts "-" * 50

puts "Each Consumer.run creates fresh RandomGenerator:"
puts "\nFirst Consumer.run:"
Consumer.run

puts "\nSecond Consumer.run (different RandomGenerator value):"
Consumer.run

puts "\n" + "=" * 50
puts "\n4. Use Cases Summary"
puts "-" * 50
puts <<~SUMMARY
  TaskClass.run / TaskClass.value
    => Fresh execution every time
    => Dependencies within same execution are cached
    => Use for: Independent executions, scripts

  TaskClass.reset!
    => Clears task state
    => Next execution starts fresh
    => Use for: Re-running tasks in tests
SUMMARY

puts "\n" + "=" * 50
puts "Scope-Based Execution demonstration complete!"
