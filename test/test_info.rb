# frozen_string_literal: true

require "test_helper"
require "taski/progress/info"

# TaskInfo / ExecutionInfo are the immutable render data passed to theme
# methods (successors of the Liquid TaskDrop/ExecutionDrop). Pins the
# deliberate differences from the drops: keyword defaults for partial
# construction, frozen instances, and unknown-member access raising (drops
# returned nil for any key — typos were invisible).
class TestInfo < Minitest::Test
  def test_task_info_all_members_default_to_nil
    info = Taski::Progress::TaskInfo.new
    assert_nil info.name
    assert_nil info.state
    assert_nil info.duration
    assert_nil info.error_message
    assert_nil info.group_name
    assert_nil info.stdout
  end

  def test_task_info_partial_construction
    info = Taski::Progress::TaskInfo.new(stdout: "line")
    assert_equal "line", info.stdout
    assert_nil info.name
  end

  def test_task_info_is_frozen
    assert_predicate Taski::Progress::TaskInfo.new(name: "T"), :frozen?
  end

  def test_task_info_unknown_member_raises
    info = Taski::Progress::TaskInfo.new
    assert_raises(NoMethodError) { info.nmae }
  end

  def test_task_info_unknown_keyword_raises
    assert_raises(ArgumentError) { Taski::Progress::TaskInfo.new(nmae: "typo") }
  end

  def test_execution_info_counts_default_to_zero
    info = Taski::Progress::ExecutionInfo.new
    assert_equal 0, info.pending_count
    assert_equal 0, info.done_count
    assert_equal 0, info.completed_count
    assert_equal 0, info.failed_count
    assert_equal 0, info.skipped_count
    assert_equal 0, info.total_count
    assert_equal 0, info.total_duration
    assert_equal 0, info.spinner_index
  end

  def test_execution_info_nilable_members_default_to_nil
    info = Taski::Progress::ExecutionInfo.new
    assert_nil info.state
    assert_nil info.root_task_name
    assert_nil info.task_names
  end

  def test_execution_info_partial_construction
    info = Taski::Progress::ExecutionInfo.new(done_count: 3, total_count: 5)
    assert_equal 3, info.done_count
    assert_equal 5, info.total_count
    assert_equal 0, info.failed_count
  end

  def test_execution_info_carries_spinner_index
    info = Taski::Progress::ExecutionInfo.new(spinner_index: 3)
    assert_equal 3, info.spinner_index
  end

  def test_execution_info_is_frozen
    assert_predicate Taski::Progress::ExecutionInfo.new, :frozen?
  end

  def test_execution_info_unknown_member_raises
    info = Taski::Progress::ExecutionInfo.new
    assert_raises(NoMethodError) { info.done_cuont }
  end
end
