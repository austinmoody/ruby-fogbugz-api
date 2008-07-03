Gem::Specification.new do |s|
  s.name    = "fogbugz-api"
  s.version = "0.0.2"
  s.date = "2008-07-03"

  s.summary = "Ruby wrapper for FogBugz API"

  s.authors = ["Austin Moody","Gregory McIntyre"]
  s.email = "austin.moody@gmail.com"
  s.homepage = "http://github.com/austinmoody/ruby-fogbugz-api/wikis"

  s.has_rdoc = true
  s.rdoc_options = ["--main", "README.rdoc"]
  s.rdoc_options << "--inline-source"
  s.extra_rdoc_files = ["README.rdoc","LICENSE","TODO"]
  s.add_dependency "hpricot", [">= 0.6"]

  s.files = %w(README.rdoc LICENSE TODO fogbugz-api.rb lib lib/fogbugz-api.rb)
end
