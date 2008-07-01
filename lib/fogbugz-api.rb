%w(hpricot net/https cgi).each { |f| require f }
# TODO
# 1. If API mismatch... destroy Object?

class Hash
  # Adding a to_params method to
  # Hash so that I can easily convert
  # a Hash into parameters for use in
  # a URL.
  #
  # Example: {"cmd"=>"logon", "email"=>"austin.moody@gmail.com", "password"=>"yeahwhatever"}.to_params
  # would result in
  # "cmd=logon&email=austin.moody@gmail.com&password=yeahwhatever"
  def to_params
    return_value = Array.new

    self.each do |key,value|
      #return_value << key + "=" + value.to_s.gsub(" ","%20").gsub("\n","%0a") 
      return_value << key + "=" + CGI.escape(value.to_s)
    end

    return return_value.join("&")
  end
end # class Hash

class FogBugzError < StandardError; end

class FogBugz

  API_VERSION = 5

  # This is an array of all possible values
  # that can be returned on a case.  For 
  # methods that ask for cols wanted for a case
  # this array will be used if their is nothing
  # else specified.
  CASE_COLUMNS = ["ixBug",
                  "fOpen",
                  "sTitle",
                  "sLatestTextSummary",
                  "ixBugEventLatestText",
                  "ixProject",
                  "sProject",
                  "ixArea",
                  "sArea",
                  "ixGroup",
                  "ixPersonAssignedTo",
                  "sPersonAssignedTo",
                  "sEmailAssignedTo",
                  "ixPersonOpenedBy",
                  "ixPersonResolvedBy",
                  "ixPersonClosedBy",
                  "ixPersonLastEditedBy",
                  "ixStatus",
                  "sStatus",
                  "ixPriority",
                  "sPriority",
                  "ixFixFor",
                  "sFixFor",
                  "dtFixFor",
                  "sVersion",
                  "sComputer",
                  "hrsOrigEst",
                  "hrsCurrEst",
                  "hrsElapsed",
                  "c",
                  "sCustomerEmail",
                  "ixMailbox",
                  "ixCategory",
                  "sCategory",
                  "dtOpened",
                  "dtResolved",
                  "dtClosed",
                  "ixBugEventLatest",
                  "dtLastUpdated",
                  "fReplied",
                  "fForwarded",
                  "sTicket",
                  "ixDiscussTopic",
                  "dtDue",
                  "sReleaseNotes",
                  "ixBugEventLastView",
                  "dtLastView",
                  "ixRelatedBugs",
                  "sScoutDescription",
                  "sScoutMessage",
                  "fScoutStopReporting",
                  "fSubscribed",
                  "events"]

  attr_reader   :url,
                :token,
                :use_ssl,
                :api_version,
                :api_minversion,
                :api_url

  # BASIC STUFF

  def initialize(url,use_ssl=false,token=nil)

    @url = url
    @use_ssl = use_ssl
    connect

    # Attempt to grap api.xml file from the server
    # specified by url.  Will let us know API is
    # functional and verion matches this class
    result = Hpricot.XML(@connection.get("/api.xml").body)

    @api_version = (result/"version").inner_html.to_i
    @api_minversion = (result/"version").inner_html.to_i
    @api_url = "/" + (result/"url").inner_html

    # Make sure this class will work w/ API version
    raise FogBugzError, "API version mismatch" if (API_VERSION < @api_minversion)

    @token = token ? token : ""

  end # def initialize

  def connect
    @connection = Net::HTTP.new(@url, @use_ssl ? 443 : 80) 
    @connection.use_ssl = @use_ssl
    @connection.verify_mode = OpenSSL::SSL::VERIFY_NONE if @use_ssl
  end # def connect

  def logon(email,password)
    cmd = {"cmd" => "logon",
              "email" => email,
              "password" => password}

    result = Hpricot.XML(@connection.post(@api_url, cmd.to_params).body)

    if (result/"error").length >= 1
      # error code 1 = bad login
      # error code 2 = ambiguous name
      case (result/"error").first["code"]
        when "1"
          raise FogBugzError, (result/"error").inner_html
        when "2"
          ambiguous_users = []
          (result/"person").each do |person|
            ambiguous_users << /<!\[CDATA\[(.*?)\]\]>/.match(person.inner_html)[1]
          end
          raise FogBugzError, (result/"error").inner_html + " " + ambiguous_users.join(", ")
      end  # case
    elsif (result/"token").length == 1
      # successful login
      @token = /<!\[CDATA\[(.*?)\]\]>/.match((result/"token").inner_html)[1]
    end
  end # def logon

  def logoff
    cmd = {"cmd" => "logoff",
           "token" => @token}

    result = Hpricot.XML(@connection.post(@api_url, cmd.to_params).body)

    @token = ""

  end # def logoff

  # FILTERS
  
  def listFilters

    return_value = Hash.new

    cmd = {"cmd" => "listFilters",
           "token" => @token}

    result = Hpricot.XML(@connection.post(@api_url, cmd.to_params).body)

    # Loop over each project returned
    (result/"filter").each do |filter|

      # create hash for each new project
      filter_name = filter.inner_html
      return_value[filter_name] = Hash.new
      return_value[filter_name]["name"] = filter_name

      return_value[filter_name] = filter.attributes.merge(return_value[filter_name])

    end

    return_value
  end # def listFilters

  #------------------#
  #     Projects     #
  #------------------#

  def listProjects(fWrite=false, ixProject=nil)

    return_value = Hash.new

    cmd = {"cmd" => "listProjects",
           "token" => @token}

    {"fWrite"=>"1"}.merge(cmd) if fWrite
    {"ixProject"=>ixProject}.merge(cmd) if ixProject

    result = Hpricot.XML(@connection.post(@api_url,cmd.to_params).body)

    return list_process(result,"project","sProject")

  end # def listProjects

  # retuns integer, which is ixProject for the project created
  def newProject(sProject,ixPersonPrimaryContact,fAllowPublicSubmit,ixGroup,fInbox)

    # I would have thought that the fAllowPublicSubmit would have been
    # true/false... instead seems to need to be 0 or 1.
    cmd = {
      "cmd" => "newProject",
      "token" => @token,
      "sProject" => sProject,
      "ixPersonPrimaryContact" => ixPersonPrimaryContact.to_s,
      "fAllowPublicSubmit" => fAllowPublicSubmit.to_s,
      "ixGroup" => ixGroup.to_s,
      "fInbox" => fInbox.to_s
    }

    result = Hpricot.XML(@connection.post(@api_url,cmd.to_params).body)

    return (result/"ixProject").inner_html.to_i

  end # def createProject

  #---------------#
  #     AREAS     #
  #---------------#
  def listAreas(fWrite=false, ixProject=nil, ixArea=nil)

    return_value = Hash.new

    cmd = {"cmd" => "listAreas",
           "token" => @token}

    cmd = {"fWrite"=>"1"}.merge(cmd) if fWrite
    cmd = {"ixProject"=>ixProject}.merge(cmd) if ixProject
    cmd = {"ixArea" => ixArea}.merge(cmd) if ixArea

    result = Hpricot.XML(@connection.post(@api_url,cmd.to_params).body)

    return list_process(result,"area","sArea")

  end # def listAreas

  #-----------------#
  #     FixFors     #
  #-----------------#
  def listFixFors(ixProject=nil,ixFixFor=nil)

    return_value = Hash.new

    cmd = {"cmd" => "listFixFors",
           "token" => @token}

    {"ixProject"=>ixProject}.merge(cmd) if ixProject
    {"ixFixFor" => ixFixFor}.merge(cmd) if ixFixFor

    result = Hpricot.XML(@connection.post(@api_url,cmd.to_params).body)

    return list_process(result,"fixfor","sFixFor")

  end # def listFixFors

  #--------------------#
  #     CATEGORIES     #
  #--------------------#
  def listCategories
    cmd = {"cmd" => "listCategories", "token" => @token}

    result = Hpricot.XML(@connection.post(@api_url,cmd.to_params).body)

    return list_process(result,"category","sCategory")
  end # def listCategories

  def listPriorities
    cmd = {"cmd" => "listPriorities", "token" => @token}

    result = Hpricot.XML(@connection.post(@api_url,cmd.to_params).body)

    return list_process(result,"priority","sPriority")
  end # def listPriorities

  def listPeople(fIncludeNormal="1",fIncludeCommunity=nil,fIncludeVirtual=nil)

    cmd = {
      "cmd" => "listPeople",
      "token" => @token,
      "fIncludeNormal" => fIncludeNormal
    }

    cmd = {"fIncludeCommunity" => "1"}.merge(cmd) if fIncludeCommunity
    cmd = {"fIncludeVirtual" => "1"}.merge(cmd) if fIncludeVirtual

    result = Hpricot.XML(@connection.post(@api_url, cmd.to_params).body)

    return list_process(result,"person","sFullName")

  end # def listPeople

  def listStatuses(ixCategory=nil,fResolved=nil)

    cmd = {
      "cmd" => "listStatuses",
      "token" => @token
    }

    cmd = {"ixCategory"=>ixCategory}.merge(cmd) if ixCategory
    cmd = {"fResolved"=>fResolved}.merge(cmd) if fResolved

    result = Hpricot.XML(@connection.post(@api_url,cmd.to_params).body)

    return list_process(result,"status","sStatus")

  end # def listStatuses

  def listMailboxes
    cmd = {
      "cmd" => "listMailboxes",
      "token" => @token
    }

    result = Hpricot.XML(@connection.post(@api_url,cmd.to_params).body)

    # usually lists were keyed w/ a name field.  Mailboxes just
    # weren't working for me so I'm going with ixMailbox value
    return list_process(result,"mailbox","ixMailbox")
  end # def listMailboxes

  # --------------#
  #     CASES     #
  # --------------#
  def search(q,cols=nil,max=nil)
    # assuming cols is passed as an Array
    # TODO - shoudl I worry about the "operations" returned
    # in the <case>?
    
    cmd = {
      "cmd" => "search",
      "token" => @token,
      "q" => q
    }

    if cols
      # user has specified a list of columns they want to see
      cmd = {"cols" => cols.join(",")}.merge(cmd)
    else
      # use the built in CASE_COLUMNS
      cmd = {"cols" => CASE_COLUMNS.join(",")}.merge(cmd)
    end 

    cmd = {"max" => max}.merge(cmd) if max

    result = Hpricot.XML(@connection.post(@api_url,cmd.to_params).body)

    return_value = list_process(result,"case","ixBug")

    # if one of the returned cols = events, then process 
    # this list and replace its spot in the Hash
    # with this instead of a string of XML
    return_value.each do |key,value|
      return_value[key]["events"] = list_process(Hpricot.XML(return_value[key]["events"]),"event","ixBugEvent") if return_value[key].has_key?("events")
    end

    return_value

  end # def search

  # Creates a new FogBugz case.  
  # params -> must be a hash keyed with values from
  #           the FogBugz API docs.  sTitle, ixProject (or sProject), etc...
  # cols -> columns to be returned about the new case.  if not passed will
  #         use constant list (all) provided with Class
  def new_case(params,cols=CASE_COLUMNS)
    
    case_process("new",params,cols)

  end # def new_case

  def case_process(cmd,params,cols)
    cmd = {
      "cmd" => cmd,
      "token" => @token,
      "cols" => cols.join(",")
    }.merge(params)

    result = Hpricot.XML(@connection.post(@api_url, cmd.to_params).body)

    return_value = list_process(result,"case","ixBug")

    # if one of the returned cols = events, then process 
    # this list and replace its spot in the Hash
    # with this instead of a string of XML
    return_value.each do |key,value|
      return_value[key]["events"] = list_process(Hpricot.XML(return_value[key]["events"]),"event","ixBugEvent") if return_value[key].has_key?("events")
    end

    return_value[return_value.keys[0]]

  end # def case_process

  #DEBUG - add protected here
  def list_process(xml,element,element_name)
    # xml => XML to process
    # element => individual elements within the XML to create Hashes for within the returned value
    # element_name => key for each individual Hash within the return value.
    #
    # EXAMPLE XML
    #<response>
    #	<categories>
    #		<category>
    #			<ixCategory>1</ixCategory>
    #			<sCategory><![CDATA[Bug]]></sCategory>
    #			<sPlural><![CDATA[Bugs]]></sPlural>
    #			<ixStatusDefault>2</ixStatusDefault>
    #			<fIsScheduleItem>false</fIsScheduleItem>
    #		</category>
    #		<category>
    #			<ixCategory>2</ixCategory>
    #			<sCategory><![CDATA[Feature]]></sCategory>
    #			<sPlural><![CDATA[Features]]></sPlural>
    #			<ixStatusDefault>8</ixStatusDefault>
    #			<fIsScheduleItem>false</fIsScheduleItem>
    #		</category>
    #	</categories>
    #</response>
    #
    # EXAMPLE CAll
    # list_process(xml, "category", "sCategory")
    #
    # EXAMPLE HASH RETURN
    #
    # {
    #   "Bug" => { 
    #               "ixCategory" => 1,
    #               "sCategory" => "Bug",
    #               "sPlural" => "Bugs",
    #               "ixStatusDefault" => 2,
    #               "fIsScheduleItem" => false
    #           },
    #   "Feature" => {
    #               "ixCategory" => 2,
    #               "sCategory" => "Feature",
    #               "sPlural" => "Features",
    #               "ixStatusDefault" => 2,
    #               "fIsScheduleItem" => false
    #           }
    # }
    return_value = Hash.new
    (xml/"#{element}").each do |item|
      if element_name[0,1] == "s"
        item_name = /<!\[CDATA\[(.*?)\]\]>/.match((item/"#{element_name}").inner_html)[1]
      else
        item_name = (item/"#{element_name}").inner_html 
      end
      return_value[item_name] = Hash.new

      item.each_child do |attribute|
        return_value[item_name][attribute.name] = attribute.inner_html
        # convert values to proper types
        return_value[item_name][attribute.name] = /<!\[CDATA\[(.*?)\]\]>/.match(attribute.inner_html)[1] if (attribute.name[0,1] == "s" or attribute.name[0,3] == "evt") and (attribute.inner_html != "") and /<!\[CDATA\[(.*?)\]\]>/.match(attribute.inner_html) != nil
        return_value[item_name][attribute.name] = return_value[item_name][attribute.name].to_i if (attribute.name[0,2] == "ix" or attribute.name[0,1] == "n")
        return_value[item_name][attribute.name] = (return_value[item_name][attribute.name] == "true") ? true : false if attribute.name[0,1] == "f"

      end
    end

    return_value
  end
end # class FogBugz
