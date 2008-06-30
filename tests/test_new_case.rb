require '../fogbugz-api'
require 'yaml'

fb = FogBugz.new(ARGV[0],ARGV[1])

fb.logon(ARGV[2],ARGV[3])

params = {
  "sTitle" => "ruby-fogbugz-api testing #{Time.now.strftime("%m/%d %H:%M")}",
  "sProject" => "Sample Project",
  "sArea" => "User Interface",
  "sFixFor" => "Test Release",
  "sCategory" => "Bug",
  "sPriority" => 6,
  "sEvent" => "This is the first message in the case hopefully."
}

mycase = fb.new_case(params)

File.open("test_new_case.yaml","w") { |f| YAML.dump(mycase,f) }

fb.logoff
