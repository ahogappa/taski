# Taski

**Taski** is a Ruby-based task runner designed for small, composable processing steps.
In Taski, you define tasks as Ruby classes that expose named values through `define`. Dependencies between tasks are established automatically when one task references the result of another—no need for explicit dependency declarations.

Tasks are executed in a topologically sorted order, ensuring that tasks are built only after their inputs are available. Reverse execution is also supported, making it easy to clean up intermediate files or revert changes after a build.

> **🚧 Development Status:** Taski is currently under active development and the API may change.

> **⚠️ Limitation:** Circular dependencies are **not** supported at this time.

> **ℹ️ Note:** Taski does **not** infer dependencies from file contents or behavior. Instead, dependencies are implicitly established via references between task definitions.

### Features

- Define tasks using Ruby classes
- Implicit dependencies via reference to other task outputs
- Topological execution order
- Reverse execution for cleanup
- Built entirely in Ruby

### Example

```ruby
class TaskA < Taski::Task
  define :task_a_result, -> { "Task A" }

  def build
    puts 'Processing...'
  end
end

class TaskB < Taski::Task
  define :simple_task, -> { "Task result is #{TaskA.task_a_result}" }

  def build
    puts simple_task
  end
end

TaskB.build
# => Processing...
# => Task result is Task A
```

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add taski
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install taski
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/taski.
