# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# A task class's own state is written on the main Ractor and must then be
# readable from any Ractor: running task code in a Ractor, or offloading part
# of a task to one, reads the export list and the dependency cache from there.
# The Ractor side runs in a child process so that this test process never
# switches into multi-Ractor mode.
class TestTaskClassStateAcrossRactors < Minitest::Test
  FIXTURE = File.expand_path("fixtures/ractor_state_tasks", __dir__)
  LIB = File.expand_path("../lib", __dir__)

  def test_reading_exported_methods_does_not_write_the_class
    klass = Class.new(Taski::Task)
    klass.exported_methods

    refute klass.instance_variable_defined?(:@exported_methods)
  end

  def test_class_state_is_readable_from_a_non_main_ractor
    script = <<~RUBY
      Warning[:experimental] = false
      require #{FIXTURE.dump}
      RactorStateFixtures::Root.cached_dependencies # computed on the main Ractor, as the executor does

      %i[exported_methods cached_dependencies export_read_off_instance].each do |probe|
        r = Ractor.new(probe) { |name| RactorStateFixtures::Probe.public_send(name) }
        puts "\#{probe}: \#{(r.respond_to?(:value) ? r.value : r.take).inspect}"
      end
    RUBY
    out, status = Open3.capture2e(RbConfig.ruby, "-I", LIB, "-e", script)

    assert status.success?, out
    assert_equal <<~OUT, out
      exported_methods: [:value, :extra]
      cached_dependencies: [RactorStateFixtures::Leaf]
      export_read_off_instance: "leaf"
    OUT
  end
end
