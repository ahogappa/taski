# frozen_string_literal: true

module Taski
  module TestHelper
    # Raised when attempting to mock a class that is not a Taski::Task or Taski::Section subclass.
    class InvalidTaskError < ArgumentError
    end

    # Raised when attempting to mock a method that is not an exported method of the task.
    class InvalidMethodError < ArgumentError
    end
  end
end
