# frozen_string_literal: true

require_relative "test_helper"

class TestSection < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  def test_section_basic_functionality
    assert Object.const_defined?("Taski::Section")

    section_class = Class.new(Taski::Section)
    refute_nil section_class
    assert_respond_to section_class, :interface

    section_class.interface(:connection_string, :timeout)
    assert_respond_to section_class, :connection_string
    assert_respond_to section_class, :timeout
  end

  def test_section_returns_implementation_values
    section_class = Class.new(Taski::Section) do
      interface :database_url

      def self.impl
        self::TestImplementation
      end
    end

    test_implementation = Class.new(Taski::Task) do
      exports :database_url

      def build
        @database_url = "postgresql://localhost:5432/test"
      end
    end

    section_class.const_set(:TestImplementation, test_implementation)
    assert_equal "postgresql://localhost:5432/test", section_class.database_url
  end

  def test_section_with_nested_task_classes
    database_section = Class.new(Taski::Section) do
      interface :database_url, :timeout

      def self.impl
        self::Production
      end
    end

    production_task = Class.new(Taski::Task) do
      exports :database_url, :timeout

      def build
        @database_url = "postgresql://prod:5432/app"
        @timeout = 30
      end
    end

    database_section.const_set(:Production, production_task)
    assert_equal "postgresql://prod:5432/app", database_section.database_url
    assert_equal 30, database_section.timeout
  end

  def test_section_auto_exports
    section_class = Class.new(Taski::Section) do
      interface :connection_string, :pool_size

      def self.impl
        self::SimpleTask
      end
    end

    simple_task = Class.new(Taski::Task) do
      def build
        @connection_string = "sqlite::memory:"
        @pool_size = 1
      end
    end

    section_class.const_set(:SimpleTask, simple_task)
    section_class.apply_auto_exports

    assert_equal "sqlite::memory:", section_class.connection_string
    assert_equal 1, section_class.pool_size
  end

  def test_impl_without_self
    section_class = Class.new(Taski::Section) do
      interface :value

      def impl
        self.class::TestImplementation
      end
    end

    test_implementation = Class.new(Taski::Task) do
      exports :value

      def build
        @value = "no-self-impl"
      end
    end

    section_class.const_set(:TestImplementation, test_implementation)
    assert_equal "no-self-impl", section_class.value
  end

  def test_section_error_handling
    # Empty interface
    error = assert_raises(ArgumentError) do
      Class.new(Taski::Section) { interface }
    end
    assert_includes error.message, "interface requires at least one method name"

    # impl returns nil
    nil_section = Class.new(Taski::Section) do
      interface :value
      def impl
        nil
      end
    end
    error = assert_raises(Taski::SectionImplementationError) { nil_section.value }
    assert_includes error.message, "impl returned nil"

    # impl returns wrong type
    wrong_type_section = Class.new(Taski::Section) do
      interface :value
      def impl
        "not a class"
      end
    end
    error = assert_raises(Taski::SectionImplementationError) { wrong_type_section.value }
    assert_includes error.message, "must return a Task class"

    # impl not defined
    undefined_section = Class.new(Taski::Section) { interface :value }
    error = assert_raises(NotImplementedError) { undefined_section.value }
    assert_includes error.message, "impl"
  end

  def test_section_utility_methods
    # interface_exports
    empty_section = Class.new(Taski::Section)
    assert_equal [], empty_section.interface_exports

    section_with_interface = Class.new(Taski::Section) do
      interface :host, :port, :database
    end
    assert_equal [:host, :port, :database], section_with_interface.interface_exports

    # Instance management methods
    section_class = Class.new(Taski::Section) do
      interface :value
      def impl
        self.class::TestImplementation
      end
    end

    test_task = Class.new(Taski::Task) do
      exports :value
      def build
        @value = "test"
      end
    end

    section_class.const_set(:TestImplementation, test_task)

    assert_equal section_class, section_class.reset!
    assert_equal section_class, section_class.build
    assert_equal section_class, section_class.ensure_instance_built
  end

  def test_section_tree_displays_possible_implementations
    # RED段階：Section.treeが可能な実装クラスを表示する機能のテスト
    # 期待される動作：Section.treeで可能な実装クラスが表示される

    # PostgreSQL/MySQL implementation section
    database_section = Class.new(Taski::Section) do
      interface :database_url

      def self.impl
        if ENV["DATABASE"] == "postgres"
          self::PostgresImplementation
        else
          self::MysqlImplementation
        end
      end
    end

    postgres_impl = Class.new(Taski::Task) do
      exports :database_url
      def build
        @database_url = "postgresql://localhost/test"
      end
    end

    mysql_impl = Class.new(Taski::Task) do
      exports :database_url
      def build
        @database_url = "mysql://localhost/test"
      end
    end

    database_section.const_set(:PostgresImplementation, postgres_impl)
    database_section.const_set(:MysqlImplementation, mysql_impl)

    # EXPECTED: Section.tree should show possible implementations
    tree_output = database_section.tree(color: false)

    # Should show section name and possible implementations
    # Note: anonymous class name is nil, so we check for the class itself or a fallback
    section_name = database_section.name || database_section.to_s
    assert_includes tree_output, section_name, "Tree should show section name"
    assert_includes tree_output, "[One of:", "Tree should indicate multiple possible implementations"
    assert_includes tree_output, "PostgresImplementation", "Tree should list PostgresImplementation as possibility"
    assert_includes tree_output, "MysqlImplementation", "Tree should list MysqlImplementation as possibility"
  end

  def test_section_tree_shows_different_implementations_for_different_sections
    # 三角測量：異なるSectionで異なる実装リストが表示されることを確認

    # Cache section (different implementations)
    cache_section = Class.new(Taski::Section) do
      interface :cache_client

      def self.impl
        if ENV["CACHE"] == "redis"
          self::RedisCache
        else
          self::MemoryCache
        end
      end
    end

    redis_cache = Class.new(Taski::Task) do
      exports :cache_client
      def build
        @cache_client = "redis client"
      end
    end

    memory_cache = Class.new(Taski::Task) do
      exports :cache_client
      def build
        @cache_client = "memory cache"
      end
    end

    cache_section.const_set(:RedisCache, redis_cache)
    cache_section.const_set(:MemoryCache, memory_cache)

    # Get tree output
    cache_tree = cache_section.tree(color: false)

    # Should show different implementations than database section
    cache_name = cache_section.name || cache_section.to_s
    assert_includes cache_tree, cache_name, "Cache tree should show cache section name"
    assert_includes cache_tree, "[One of:", "Cache tree should indicate multiple implementations"
    assert_includes cache_tree, "RedisCache", "Cache tree should list RedisCache as possibility"
    assert_includes cache_tree, "MemoryCache", "Cache tree should list MemoryCache as possibility"

    # Should NOT show database implementations
    refute_includes cache_tree, "PostgresImplementation", "Cache tree should not show database implementations"
    refute_includes cache_tree, "MysqlImplementation", "Cache tree should not show database implementations"
  end

  def test_section_tree_with_no_implementations
    # エッジケース：実装クラスが存在しない場合
    empty_section = Class.new(Taski::Section) do
      interface :value

      def self.impl
        # impl method exists but no nested classes
        nil
      end
    end

    tree_output = empty_section.tree(color: false)
    section_name = empty_section.name || empty_section.to_s

    # Should show section name but no implementation list
    assert_includes tree_output, section_name, "Tree should show section name even with no implementations"
    refute_includes tree_output, "[One of:", "Tree should not show implementation list when none exist"
  end

  def test_section_tree_with_colors
    # カラー表示のテスト
    database_section = Class.new(Taski::Section) do
      interface :database_url

      def self.impl
        PostgresImplementation
      end
    end

    postgres_impl = Class.new(Taski::Task) do
      exports :database_url
      def build
        @database_url = "postgresql://localhost/test"
      end
    end

    database_section.const_set(:PostgresImplementation, postgres_impl)

    # Force enable colors for testing (since test environment might not be TTY)
    original_enabled = Taski::TreeColors.enabled?
    Taski::TreeColors.enabled = true

    begin
      # Color enabled
      colored_output = database_section.tree(color: true)
      assert_includes colored_output, "\e[1m\e[34m", "Should include blue color for section name"
      assert_includes colored_output, "\e[33m", "Should include yellow color for implementations"
      assert_includes colored_output, "\e[90m", "Should include gray color for connectors"

      # Color disabled
      plain_output = database_section.tree(color: false)
      refute_includes plain_output, "\e[", "Should not include any ANSI codes when color disabled"
    ensure
      # Restore original state
      Taski::TreeColors.enabled = original_enabled
    end
  end
end
