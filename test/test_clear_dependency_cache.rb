# frozen_string_literal: true

require "test_helper"
require_relative "fixtures/start_dep_tasks"

# Taski::Task.clear_dependency_cache is the public hook for "this task's code
# changed, re-analyze it". It must fully invalidate the per-class analysis:
# the dependency cache, the memoized circular-dependency check, and the
# StartDepAnalyzer (prestart) cache.
class TestClearDependencyCache < Minitest::Test
  def setup
    Taski::Task.reset! if defined?(Taski::Task)
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
  end

  def teardown
    # Drop any per-class memo state these tests deliberately populated/invalidated.
    StartDepFixtures::SlowDepA.clear_dependency_cache
    StartDepFixtures::ParallelStartDepRoot.clear_dependency_cache
    Taski::StaticAnalysis::StartDepAnalyzer.clear_cache!
  end

  # After clear_dependency_cache, a dependency change that introduces a cycle
  # must be caught on the next validation — the memoized "already checked" flag
  # must not short-circuit it.
  def test_clear_dependency_cache_forces_circular_recheck
    klass = StartDepFixtures::SlowDepA
    klass.send(:validate_no_circular_dependencies!) # passes; result is memoized

    with_cyclic_components do
      # Without clearing, the memoized pass short-circuits — no re-check.
      klass.send(:validate_no_circular_dependencies!) # must NOT raise

      klass.clear_dependency_cache

      # After clearing, validation re-runs and sees the (now cyclic) graph.
      assert_raises(Taski::CircularDependencyError) do
        klass.send(:validate_no_circular_dependencies!)
      end
    end
  end

  # clear_dependency_cache must also drop this class's StartDepAnalyzer entry so
  # prestart analysis is recomputed after a code change.
  def test_clear_dependency_cache_clears_start_dep_analysis
    klass = StartDepFixtures::ParallelStartDepRoot
    Taski::StaticAnalysis::StartDepAnalyzer.analyze(klass)
    assert start_dep_cached?(klass), "precondition: prestart analysis is cached"

    klass.clear_dependency_cache

    refute start_dep_cached?(klass), "clear_dependency_cache should drop the start-dep cache entry"
  end

  # An unrelated class's prestart cache must survive a per-class clear.
  def test_clear_dependency_cache_does_not_clear_other_classes
    Taski::StaticAnalysis::StartDepAnalyzer.analyze(StartDepFixtures::SlowDepA)
    Taski::StaticAnalysis::StartDepAnalyzer.analyze(StartDepFixtures::ParallelStartDepRoot)

    StartDepFixtures::SlowDepA.clear_dependency_cache

    assert start_dep_cached?(StartDepFixtures::ParallelStartDepRoot),
      "clearing one class must not evict another class's prestart cache"
  end

  private

  def start_dep_cached?(klass)
    Taski::StaticAnalysis::StartDepAnalyzer.instance_variable_get(:@cache).key?(klass)
  end

  # Force DependencyGraph#cyclic_components to report a cycle for the duration of
  # the block, so we can observe whether validation actually re-runs.
  def with_cyclic_components
    graph = Taski::StaticAnalysis::DependencyGraph
    original = graph.instance_method(:cyclic_components)
    graph.define_method(:cyclic_components) { [[Object]] }
    yield
  ensure
    graph.define_method(:cyclic_components, original)
  end
end
