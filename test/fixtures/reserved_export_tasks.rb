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
end
