# Steepfile for Taski gem

target :lib do
  signature "sig"

  check "lib"

  # Ignore test and temporary files
  ignore "test"
  ignore "tmp"
  ignore "examples"

  # Standard library dependencies
  library "monitor"
  library "tsort"

  # Use gems from rbs_collection
  collection_config "rbs_collection.yaml"
end
