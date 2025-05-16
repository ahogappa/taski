# Taski

**Taski** is a Ruby-based task runner designed for small, composable processing steps.
With Taski, you define tasks and the outputs they depend on. Taski then statically resolves task dependencies and determines the correct execution order.

Tasks are executed in a topologically sorted order, ensuring that all dependencies are resolved before a task is run. Reverse execution is also supported, making it easy to clean up intermediate files after a build process.

> **🚧 Development Status:** Taski is currently under active development and the API may change.

> **⚠️ Limitation:** Circular dependencies are **not** supported at this time.

### Features

- Simple and declarative task definitions
- Static dependency resolution
- Topological execution order
- Reverse execution for teardown or cleanup
- Built entirely in Ruby

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add taski
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install taski
```

## Usage

```ruby
class TaskA < Taski::Task
  definition :task_a, -> { "Task A" }

  def build
    task_a
  end
end

class TaskB < Taski::Task
  definition :simple_task, -> { "Task result is #{TaskA.task_a}" }

  def build
    puts simple_task
  end
end

TaskB.build
# => Task result is Task A
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/taski.
