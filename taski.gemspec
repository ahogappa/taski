# frozen_string_literal: true

require_relative "lib/taski/version"

Gem::Specification.new do |spec|
  spec.name = "taski"
  spec.version = Taski::VERSION
  spec.authors = ["ahogappa"]
  spec.email = ["ahogappa@gmail.com"]

  spec.summary = "A simple yet powerful Ruby task runner with static dependency resolution (in development)."
  spec.description = "Taski is a Ruby-based task runner currently under development. It allows you to define small, composable tasks along with the outputs they depend on. Taski statically resolves dependencies and executes tasks in the correct topological order, from the most dependent tasks first. It also supports reverse execution, useful for cleaning up temporary files after a build. **Note:** Taski does not yet support circular dependencies and may change as development progresses."
  spec.homepage = "https://github.com/ahogappa/taski"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ahogappa/taski"
  spec.metadata["changelog_uri"] = "https://github.com/ahogappa/taski"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
