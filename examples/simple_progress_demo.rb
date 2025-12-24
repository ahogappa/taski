#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/taski"

# Demo of simple one-line progress display mode
# Run with: TASKI_PROGRESS_MODE=simple ruby examples/simple_progress_demo.rb
# Or set via API: Taski.progress_mode = :simple

# Set simple progress mode via API
Taski.progress_mode = :simple

class DownloadLayer1 < Taski::Task
  exports :layer1_data

  def run
    puts "Downloading base image..."
    sleep(0.8)
    puts "Base image complete"
    @layer1_data = "Layer 1 data (base image)"
  end
end

class DownloadLayer2 < Taski::Task
  exports :layer2_data

  def run
    puts "Downloading dependencies..."
    sleep(1.2)
    puts "Dependencies complete"
    @layer2_data = "Layer 2 data (dependencies)"
  end
end

class DownloadLayer3 < Taski::Task
  exports :layer3_data

  def run
    puts "Downloading application..."
    sleep(0.3)
    puts "Application complete"
    @layer3_data = "Layer 3 data (application)"
  end
end

class ExtractLayers < Taski::Task
  exports :extracted_data

  def run
    layer1 = DownloadLayer1.layer1_data
    layer2 = DownloadLayer2.layer2_data
    layer3 = DownloadLayer3.layer3_data

    puts "Extracting layers..."
    sleep(0.3)
    @extracted_data = "Extracted: #{layer1}, #{layer2}, #{layer3}"
  end
end

class VerifyImage < Taski::Task
  exports :verification_result

  def run
    data = ExtractLayers.extracted_data

    puts "Verifying image..."
    sleep(0.2)
    @verification_result = "Verified: #{data}"
  end
end

puts "=== Simple Progress Display Demo ==="
puts "Progress mode: #{Taski.progress_mode}"
puts ""

# Execute the final task (all dependencies will be resolved automatically)
result = VerifyImage.verification_result

puts "\n\nFinal result:"
puts result
