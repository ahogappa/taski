# frozen_string_literal: true

require_relative "test_helper"

class TestTaskProxy < Minitest::Test
  include TaskiTestHelper

  def setup
    setup_taski_test
  end

  def test_proxy_resolves_via_method_missing
    proxy = nil
    fiber = Fiber.new do
      proxy = Taski::TaskProxy.new(String, :value)
      proxy.upcase
    end

    # First resume: proxy is created and method_missing triggers __resolve__ which yields
    result = fiber.resume
    assert_equal [:need_dep, String, :value], result

    # Resume with resolved value
    result = fiber.resume("hello")
    assert_equal "HELLO", result
  end

  def test_proxy_resolves_on_bang
    proxy = nil
    fiber = Fiber.new do
      proxy = Taski::TaskProxy.new(String, :value)
      !proxy
    end

    result = fiber.resume
    assert_equal [:need_dep, String, :value], result

    result = fiber.resume(nil)
    assert_equal true, result
  end

  def test_proxy_resolves_on_equal
    proxy = nil
    fiber = Fiber.new do
      proxy = Taski::TaskProxy.new(String, :value)
      proxy == 42
    end

    result = fiber.resume
    assert_equal [:need_dep, String, :value], result

    result = fiber.resume(42)
    assert_equal true, result
  end

  def test_proxy_resolves_on_not_equal
    proxy = nil
    fiber = Fiber.new do
      proxy = Taski::TaskProxy.new(String, :value)
      proxy != 42
    end

    result = fiber.resume
    assert_equal [:need_dep, String, :value], result

    result = fiber.resume(42)
    assert_equal false, result
  end

  def test_proxy_caches_resolution
    fiber = Fiber.new do
      proxy = Taski::TaskProxy.new(String, :value)
      # First access triggers yield
      first = proxy.to_s
      # Second access should use cached value (no yield)
      second = proxy.to_i
      [first, second]
    end

    result = fiber.resume
    assert_equal [:need_dep, String, :value], result

    # Resume with "123" - proxy resolves and caches
    # Both to_s and to_i should work without another yield
    result = fiber.resume("123")
    assert_equal ["123", 123], result
  end

  def test_proxy_resolve_method
    fiber = Fiber.new do
      proxy = Taski::TaskProxy.new(String, :value)
      proxy.__taski_proxy_resolve__
    end

    result = fiber.resume
    assert_equal [:need_dep, String, :value], result

    result = fiber.resume("resolved_value")
    assert_equal "resolved_value", result
  end

  def test_proxy_respond_to_proxy_resolve
    fiber = Fiber.new do
      proxy = Taski::TaskProxy.new(String, :value)
      proxy.respond_to?(:__taski_proxy_resolve__)
    end

    # respond_to? for __taski_proxy_resolve__ returns true without resolving
    result = fiber.resume
    assert_equal true, result
  end

  def test_proxy_respond_to_delegates_after_resolve
    fiber = Fiber.new do
      proxy = Taski::TaskProxy.new(String, :value)
      proxy.respond_to?(:upcase)
    end

    # respond_to? for other methods triggers resolution
    result = fiber.resume
    assert_equal [:need_dep, String, :value], result

    result = fiber.resume("hello")
    assert_equal true, result
  end

  def test_proxy_raises_error_on_taski_error
    fiber = Fiber.new do
      proxy = Taski::TaskProxy.new(String, :value)
      proxy.to_s
    end

    result = fiber.resume
    assert_equal [:need_dep, String, :value], result

    error = StandardError.new("dep failed")
    assert_raises(StandardError) do
      fiber.resume([:_taski_error, error])
    end
  end

  def test_proxy_equal_method
    fiber = Fiber.new do
      proxy = Taski::TaskProxy.new(String, :value)
      obj = "hello"
      proxy.equal?(obj)
    end

    result = fiber.resume
    assert_equal [:need_dep, String, :value], result

    obj = "hello"
    result = fiber.resume(obj)
    assert_equal true, result
  end

  # --- Taski::AwaitHandle ---

  def test_await_handle_yields_need_dep_in_fiber
    klass = Class.new
    fiber = Fiber.new do
      Thread.current[:taski_fiber_context] = true
      handle = Taski::AwaitHandle.new(klass)
      handle.value
    ensure
      Thread.current[:taski_fiber_context] = nil
    end

    result = fiber.resume
    assert_equal [:need_dep, klass, :value], result

    result = fiber.resume("awaited_value")
    assert_equal "awaited_value", result
  end

  def test_await_handle_raises_on_taski_error
    klass = Class.new
    fiber = Fiber.new do
      Thread.current[:taski_fiber_context] = true
      handle = Taski::AwaitHandle.new(klass)
      handle.value
    ensure
      Thread.current[:taski_fiber_context] = nil
    end

    fiber.resume
    error = StandardError.new("dep failed")
    assert_raises(StandardError) do
      fiber.resume([:_taski_error, error])
    end
  end
end
