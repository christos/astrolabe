Gem::Specification.new do |s|
  s.name        = "astrolabe-cli"
  s.version     = File.read(File.expand_path("lib/astrolabe.rb", __dir__))[/VERSION\s*=\s*"([^"]+)"/, 1]
  s.summary     = "Track GitHub releases for your starred repos"
  s.description = "CLI tool that syncs your GitHub starred repos and shows recent releases, powered by the gh CLI."
  s.authors     = ["Christos Zisopoulos"]
  s.homepage    = "https://github.com/christos/astrolabe"
  s.license     = "MIT"

  s.required_ruby_version = ">= 3.1"

  s.files         = Dir["lib/**/*.rb"]
  s.bindir        = "exe"
  s.executables   = ["astrolabe"]

  s.add_dependency "sqlite3",          "~> 2.6"
  s.add_dependency "tty-spinner",      "~> 0.9"
  s.add_dependency "tty-progressbar",  "~> 0.18"
  s.add_dependency "tty-table",        "~> 0.12"
  s.add_dependency "tty-prompt",       "~> 0.23"
  s.add_dependency "pastel",           "~> 0.8"
  s.add_dependency "tty-markdown",     "~> 0.7"

  s.metadata = {
    "source_code_uri" => "https://github.com/christos/astrolabe",
    "homepage_uri"    => "https://github.com/christos/astrolabe"
  }
end
