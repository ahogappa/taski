# Steepfile

D = Steep::Diagnostic

target :lib do
  signature "sig"

  check "lib"

  library "monitor", "prism"

  # Configure diagnostics with lenient settings for metaprogramming-heavy code
  configure_code_diagnostics do |hash|
    hash[D::Ruby::UnannotatedEmptyCollection] = :information
    hash[D::Ruby::UnknownInstanceVariable] = :information
    hash[D::Ruby::FallbackAny] = :information
    hash[D::Ruby::NoMethod] = :warning
    hash[D::Ruby::UndeclaredMethodDefinition] = :information
  end
end
