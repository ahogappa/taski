# frozen_string_literal: true

require "taski"

# Fixture for verifying that exporting a name which collides with an existing
# method (here Module#name) no longer breaks the framework. With method_missing
# resolution, `ExportsName.name` keeps Module#name's behavior (returns the class
# name) and static analysis / execution work normally; the :name export is
# simply unreachable via `.name`.
module ReservedExportFixtures
  class ExportsName < Taski::Task
    exports :name

    def run
      @name = "artifact-name"
    end
  end

  # Subclass inheritance of exports.
  class BaseExport < Taski::Task
    exports :value

    def run
      @value = "base-value"
    end
  end

  # Inherits :value (and run) without re-declaring.
  class InheritsExport < BaseExport
  end

  # Adds its own export on top of the inherited one.
  class AddsExport < BaseExport
    exports :extra

    def run
      @value = "base-value"
      @extra = "extra-value"
    end
  end

  # Depends on a subclass that inherits its export — exercises the
  # public_send(:value) path through the registry/proxy resolution.
  class ConsumesInherited < Taski::Task
    exports :combined

    def run
      @combined = "got: #{InheritsExport.value}"
    end
  end

  # Two `exports` calls on one class — both names must resolve (accumulate, not
  # clobber the earlier call).
  class TwiceExports < Taski::Task
    exports :first
    exports :second

    def run
      @first = "first-value"
      @second = "second-value"
    end
  end

  # Export name given as a String must work the same as a Symbol, because the
  # call site (method_missing) always receives a Symbol.
  class StringExport < Taski::Task
    exports "strval"

    def run
      @strval = "string-export-value"
    end
  end
end
