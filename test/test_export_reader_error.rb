# frozen_string_literal: true

require "test_helper"
require "timeout"
require_relative "fixtures/export_reader_error_tasks"

class TestExportReaderError < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
  end

  def test_reader_error_for_a_parked_requester_fails_the_requester
    error = Timeout.timeout(10) do
      assert_raises(Taski::AggregateError) { ExportReaderErrorFixtures::WaitingRequester.run }
    end

    assert_equal [ExportReaderErrorFixtures::WaitingRequester], error.errors.map(&:task_class)
    assert_equal "reader boom", error.errors.first.error.message
  end

  def test_reader_error_after_completion_fails_the_requester
    error = Timeout.timeout(10) do
      assert_raises(Taski::AggregateError) { ExportReaderErrorFixtures::LateRequester.run }
    end

    assert_equal [ExportReaderErrorFixtures::LateRequester], error.errors.map(&:task_class)
    assert_equal "reader boom", error.errors.first.error.message
  end

  def test_requester_can_rescue_the_reader_error
    value = Timeout.timeout(10) { ExportReaderErrorFixtures::RescuingRequester.value }

    assert_equal "rescued: reader boom", value
  end
end
