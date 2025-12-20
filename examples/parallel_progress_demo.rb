#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/taski"

# Demo tasks that simulate parallel execution with progress display
# Run with: ruby examples/parallel_progress_demo.rb

class DownloadLayer1 < Taski::Task
  exports :layer1_data

  def run
    sleep(2.3) # Simulate download
    @layer1_data = "Layer 1 data (base image)"
  end
end

class DownloadLayer2 < Taski::Task
  exports :layer2_data

  def run
    sleep(5.5) # Simulate slower download
    @layer2_data = "Layer 2 data (dependencies)"
  end
end

class DownloadLayer3 < Taski::Task
  exports :layer3_data

  def run
    sleep(0.2) # Simulate fast download
    @layer3_data = "Layer 3 data (application)"
  end
end

class ExtractLayers < Taski::Task
  exports :extracted_data

  def run
    # This task depends on all download tasks (via static analysis)
    layer1 = DownloadLayer1.layer1_data
    layer2 = DownloadLayer2.layer2_data
    layer3 = DownloadLayer3.layer3_data

    sleep(0.3) # Simulate extraction
    @extracted_data = "Extracted: #{layer1}, #{layer2}, #{layer3}"
  end
end

class VerifyImage < Taski::Task
  exports :verification_result

  def run
    # Depends on ExtractLayers
    data = ExtractLayers.extracted_data

    sleep(0.2) # Simulate verification
    @verification_result = "Verified: #{data}"
  end
end

# Start progress display
Taski.progress_display&.start

# Execute the final task (all dependencies will be resolved automatically)
result = VerifyImage.verification_result

# Stop progress display
Taski.progress_display&.stop

puts "\n\nFinal result:"
puts result
