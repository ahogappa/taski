#!/usr/bin/env ruby
# frozen_string_literal: true

# Taski Re-execution Demo
#
# This example demonstrates cache control and re-execution:
# - Default caching behavior
# - Task.new for fresh instances
# - Task.reset! for clearing all caches
#
# Run: ruby examples/reexecution_demo.rb

require_relative "../lib/taski"

puts "Taski Re-execution Demo"
puts "=" * 40

# Task that generates random values (to demonstrate caching)
class RandomGenerator < Taski::Task
  exports :value, :timestamp

  def run
    @value = rand(1000)
    @timestamp = Time.now.strftime("%H:%M:%S.%L")
    puts "  RandomGenerator.run called: value=#{@value}, time=#{@timestamp}"
  end
end

# Task that depends on RandomGenerator
class Consumer < Taski::Task
  exports :result

  def run
    random_value = RandomGenerator.value
    @result = "Consumed value: #{random_value}"
    puts "  Consumer.run called: #{@result}"
  end
end

puts "\n1. Default Caching Behavior"
puts "-" * 40
puts "First call to RandomGenerator.value:"
value1 = RandomGenerator.value
puts "  => #{value1}"

puts "\nSecond call to RandomGenerator.value (cached, no run):"
value2 = RandomGenerator.value
puts "  => #{value2}"

puts "\nValues are identical: #{value1 == value2}"

puts "\n" + "=" * 40
puts "\n2. Using Task.new for Fresh Instance"
puts "-" * 40
puts "Creating new instance with RandomGenerator.new:"

instance1 = RandomGenerator.new
instance1.run
puts "  instance1.value = #{instance1.value}"

instance2 = RandomGenerator.new
instance2.run
puts "  instance2.value = #{instance2.value}"

puts "\nNote: Each .new creates independent instance"
puts "Class-level cache unchanged: RandomGenerator.value = #{RandomGenerator.value}"

puts "\n" + "=" * 40
puts "\n3. Using reset! to Clear Cache"
puts "-" * 40
puts "Before reset!:"
puts "  RandomGenerator.value = #{RandomGenerator.value}"

puts "\nCalling RandomGenerator.reset!..."
RandomGenerator.reset!

puts "\nAfter reset! (fresh execution):"
new_value = RandomGenerator.value
puts "  RandomGenerator.value = #{new_value}"

puts "\n" + "=" * 40
puts "\n4. Dependency Chain with Re-execution"
puts "-" * 40

# Reset both tasks
RandomGenerator.reset!
Consumer.reset!

puts "First Consumer execution:"
result1 = Consumer.result
puts "  => #{result1}"

puts "\nSecond Consumer execution (cached):"
result2 = Consumer.result
puts "  => #{result2}"

puts "\nReset Consumer and re-execute:"
Consumer.reset!
result3 = Consumer.result
puts "  => #{result3}"
puts "  (Dependencies are re-resolved when task is reset)"

puts "\nReset both tasks:"
RandomGenerator.reset!
Consumer.reset!
result4 = Consumer.result
puts "  => #{result4}"
puts "  (New random value because both were reset)"

puts "\n" + "=" * 40
puts "\n5. Use Cases Summary"
puts "-" * 40
puts <<~SUMMARY
  TaskClass.run / TaskClass.value
    => Normal execution with caching (recommended for dependency graphs)

  TaskClass.new.run
    => Re-execute only this task (dependencies still use cache)
    => Useful for: testing, one-off executions

  TaskClass.reset!
    => Clear this task's cache, next call will re-execute
    => Useful for: environment changes, refreshing data
SUMMARY

puts "\n" + "=" * 40
puts "Re-execution demonstration complete!"
