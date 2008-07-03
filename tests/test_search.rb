require 'rubygems' rescue nil
require File.join(File.dirname(__FILE__), '..', 'lib', 'fogbugz-api')
require 'yaml'

fb = FogBugz.new(ARGV[0],ARGV[1])

fb.logon(ARGV[2],ARGV[3])

mycase = fb.search("api")

File.open("test_search.yaml","w") { |f| YAML.dump(mycase,f) }

fb.logoff
