Gem::Specification.new do |s|
  s.name    = "fogbugz-api"
  s.version = "0.0.1"
  s.date = "2008-06-30"

  s.summary = "Ruby wrapper for FogBugz API"

  s.authors = ["Austin Moody"]
  s.email = "austin.moody@gmail.com"
  s.homepage = "http://github.com/austinmoody/ruby-fogbugz-api/wikis"

  s.has_rdoc = true
  s.rdoc_options = ["--main", "README.rdoc"]
  s.rdoc_options << "--inline-source"
  s.add_dependency "hpricot", [">= 0.6"]

  s.files = %w(README.rdoc fogbugz-api.rb lib)
end
