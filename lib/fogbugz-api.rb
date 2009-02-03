# TODO - remove require of rubygems?
require 'rubygems' rescue nil
require 'hpricot'
require 'net/https'
require 'cgi'
require 'date'

class FogBugzError < StandardError; end

# FogBugz class
class FogBugz

  # Version of the FogBuz API this was written for.  If the minversion returned
  # by FogBugz is greater than this value this library will not function.
  # TODO
  # 1. If API mismatch... destroy Object?
  API_VERSION = 5

  # This is an array of all possible values that can be returned on a case.
  # For methods that ask for cols wanted for a case this array will be used if
  # their is nothing else specified.
  CASE_COLUMNS = %w(ixBug fOpen sTitle sLatestTextSummary ixBugEventLatestText
    ixProject sProject ixArea sArea ixGroup ixPersonAssignedTo sPersonAssignedTo
    sEmailAssignedTo ixPersonOpenedBy ixPersonResolvedBy ixPersonClosedBy
    ixPersonLastEditedBy ixStatus sStatus ixPriority sPriority ixFixFor sFixFor
    dtFixFor sVersion sComputer hrsOrigEst hrsCurrEst hrsElapsed c sCustomerEmail
    ixMailbox ixCategory sCategory dtOpened dtResolved dtClosed ixBugEventLatest
    dtLastUpdated fReplied fForwarded sTicket ixDiscussTopic dtDue sReleaseNotes
    ixBugEventLastView dtLastView ixRelatedBugs sScoutDescription sScoutMessage
    fScoutStopReporting fSubscribed events)
  
  ERROR_CODES = {"0"=>"FogBugz not initialized.  Database may be down or needs to be upgraded",
                 "1"=>"Log On problem - Incorrect Username or Password",
                 "2"=>"Log On problem - multiple matches for username",
                 "3"=>"You are not logged on.",
                 "4"=>"Argument is missing from query",
                 "5"=>"Edit problem - the case you are trying to edit could not be found",
                 "6"=>"Edit problem - the action you are trying to perform on this case is not permitted",
                 "7"=>"Time tracking problem - you can't add a time interval to this case because the case can't be found, is closed, has no estimate, or you don't have permission",
                 "8"=>"New case problem - you can't write to any project",
                 "9"=>"Case has changed since last view",
                 "10"=>"Search problem - an error occurred in search.",
                 "12"=>"Wiki creation problem",
                 "13"=>"Wiki permission problem",
                 "14"=>"Wiki load error",
                 "15"=>"Wiki template error",
                 "16"=>"Wiki commit error",
                 "17"=>"No such project",
                 "18"=>"No such user",
                 "19"=>"Area creation problem",
                 "20"=>"FixFor creation problem",
                 "21"=>"Project creation problem",
                 "22"=>"User creation problem"}

  attr_reader :url, :token, :use_ssl, :api_version, :api_minversion, :api_url

  # Creates an instance of the FogBugz class.  
  # 
  # * url: URL to your FogBugz installation.  URL only as in my.fogbugz.com
  #   without the http or https.
  # * use_ssl: Does this server use SSL?  true/false
  # * token: Already have a token for the server?  You can provide that here.
  #
  # Connects to the specified FogBugz installation and grabs the api.xml file
  # to get other information such as API version, API minimum version, and the
  # API endpoint. Also sets http/https connection to the server and sets the
  # token if provided. FogBugzError will be raise if the minimum API version
  # returned by FogBugz is greater than API_VERSION of this class.
  #
  # Example Usage:
  #
  # fb = FogBugz.new("my.fogbugz.com",true)
  #
  def initialize(url,use_ssl=false,token=nil)
    @url = url
    @use_ssl = use_ssl
    connect

    # Attempt to grap api.xml file from the server specified by url.  Will let
    # us know API is functional and verion matches this class
    result = Hpricot.XML(@connection.get("/api.xml").body)

    @api_version = (result/"version").inner_html.to_i
    @api_minversion = (result/"minversion").inner_html.to_i
    @api_url = "/" + (result/"url").inner_html

    # Make sure this class will work w/ API version
    raise FogBugzError, "API version mismatch" if (API_VERSION < @api_minversion)

    @token = token ? token : ""
  end

  # Validates a user with FogBugz.  Saves the returned token for use with other
  # commands.
  #
  # If a token was already specified with new it will be overwritten with the
  # token picked up by a successful authentication.
  def logon(email,password)
    cmd = {"cmd" => "logon", "email" => email, "password" => password}

    result = Hpricot.XML(@connection.post(@api_url, to_params(cmd)).body)

    if (result/"error").length >= 1
      # error code 1 = bad login
      # error code 2 = ambiguous name
      case (result/"error").first["code"]
        when "1"
          raise FogBugzError, (result/"error").inner_html
        when "2"
          ambiguous_users = []
          (result/"person").each do |person|
            ambiguous_users << CDATA_REGEXP.match(person.inner_html)[1]
          end
          raise FogBugzError, (result/"error").inner_html + " " + ambiguous_users.join(", ")
      end  # case
    elsif (result/"token").length == 1
      # successful login
      @token = CDATA_REGEXP.match((result/"token").inner_html)[1]
    end
  end

  def logoff
    cmd = {"cmd" => "logoff", "token" => @token}
    result = Hpricot.XML(@connection.post(@api_url, to_params(cmd)).body)
    @token = ""
  end

  def filters
    cmd = {"cmd" => "listFilters", "token" => @token}
    result = Hpricot.XML(@connection.post(@api_url, to_params(cmd)).body)
    return_value = Hash.new
    (result/"filter").each do |filter|
      # create hash for each new project
      filter_name = filter.inner_html
      return_value[filter_name] = Hash.new
      return_value[filter_name]["name"] = filter_name
      return_value[filter_name] = filter.attributes.merge(return_value[filter_name])
    end
    return_value
  end

  def projects(fWrite=false, ixProject=nil)
    return_value = Hash.new
    cmd = {"cmd" => "listProjects", "token" => @token}
    cmd = {"fWrite"=>"1"}.merge(cmd) if fWrite
    cmd = {"ixProject"=>ixProject}.merge(cmd) if ixProject
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return list_process(result,"project","sProject")
  end

  # Returns an integer, which is ixProject for the project created
  # TODO - change to accept Has of parameters?
  def new_project(sProject, ixPersonPrimaryContact, fAllowPublicSubmit, ixGroup, fInbox)

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
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return (result/"ixProject").inner_html.to_i
  end

  # Returns details about a specific project.  
  # 
  # * project: Either the id (ixProject) or the name (sProject).  
  #
  # Value returned is a Hash containing all properties of the located project.  nil is returned for unsuccessful search.
  def project(project=nil)
    return nil if not project
    cmd = {"cmd" => "viewProject", "token" => @token}
    cmd = {"ixProject" => project.to_s}.merge(cmd) if project.class == Fixnum
    cmd = {"sProject" => project}.merge(cmd) if project.class == String
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return_value =  list_process(result,"project","sProject")
    return_value[return_value.keys[0]]
  end

  def areas(fWrite=false, ixProject=nil, ixArea=nil)
    return_value = Hash.new
    cmd = {"cmd" => "listAreas", "token" => @token}
    cmd = {"fWrite"=>"1"}.merge(cmd) if fWrite
    cmd = {"ixProject"=>ixProject}.merge(cmd) if ixProject
    cmd = {"ixArea" => ixArea}.merge(cmd) if ixArea
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return list_process(result,"area","sArea")
  end
  
  # Creates a new area within a specific project
  #
  # * ixProject: ID of the project to contain the new area.
  # * sArea: Title of the new area.
  # * ixPersonPrimaryContact: ID of the person who will be the primary contact for this area.  -1 will set to the Project's primary contact, which is the default if not specified.
  def new_area(ixProject,sArea,ixPersonPrimaryContact=-1)
    cmd = {"cmd" => "newArea", "token" => @token, "ixProject" => ixProject.to_s, "sArea" => sArea.to_s, "ixPersonPrimaryContact" => ixPersonPrimaryContact.to_s}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return (result/"ixArea").inner_html.to_i    
  end

  # Returns details about a specific area
  #
  # * area: Either the id of an area (ixArea) or the name of an area (sArea).  If passing name, then the ID of the project the area belongs to needs to be passed.
  # * ixProject: ID of a project which contains specific area.  Needed if wanting details for area by name.
  #
  # Value returned is a Hash of containing all properties of the located area.  nil is returned for unsuccessful search.
  def area(area=nil,ixProject=nil)
    return nil if not area
    cmd = {"cmd" => "viewArea", "token" => @token}
    cmd = {"ixArea" => area.to_s}.merge(cmd) if area.class == Fixnum
    cmd = {"sArea" => area}.merge(cmd) if area.class == String
    cmd = {"ixProject" => ixProject.to_s}.merge(cmd) if ixProject
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return_value = list_process(result,"area","sArea")
    return_value[return_value.keys[0]]
  end

  def fix_fors(ixProject=nil,ixFixFor=nil)
    return_value = Hash.new
    cmd = {"cmd" => "listFixFors", "token" => @token}
    {"ixProject"=>ixProject}.merge(cmd) if ixProject
    {"ixFixFor" => ixFixFor}.merge(cmd) if ixFixFor
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return list_process(result,"fixfor","sFixFor")
  end

  # Returns details about a specific Fix For (releases)
  #
  # * fix_for: Either the id of a Fix For (ixFixFor) or the name of a Fix For (sFixFor).  If passing name, then the ID of the project the area belongs to needs to be passed.
  # * ixProject: ID of a project which contains specific Fix For.  Needed if wanting details for Fix For by name.
  #
  # Value returned is a Hash containing all properties of the located Fix For.  nil is returned for unsuccessful search.
  def fix_for(fix_for,ixProject=nil)
    return nil if not fix_for
    cmd = {"cmd" => "viewFixFor", "token" => @token}
    cmd = {"ixFixFor" => fix_for.to_s}.merge(cmd) if fix_for.class == Fixnum
    cmd = {"sFixFor" => fix_for}.merge(cmd) if fix_for.class == String
    cmd = {"ixProject" => ixProject.to_s}.merge(cmd) if ixProject
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return_value = list_process(result,"fixfor","sFixFor")
    return_value[return_value.keys[0]]
  end
  
  # Creates a new FixFor within FogBugz.
  #
  # * sFixFor: Title for the new FixFor
  # * fAssignable: Can cases be assigned to this FixFor?  true/false  Default is true.
  # * ixProject: ID of the project this FixFor belongs to.  If -1 (which is default when not specified) this will be a global FixFor.
  # * dtRelease: Release date for the new FixFor.  If not passed, no release date will be set.  Expecting DateTime class if value is passed.
  def new_fix_for(sFixFor,fAssignable=true,ixProject=-1,dtRelease=nil)
    return nil if dtRelease and dtRelease.class != DateTime
    cmd = {"cmd" => "newFixFor","token"=>@token,"sFixFor"=>sFixFor,"fAssignable"=>(fAssignable) ? "1" : "0","ixProject"=>ixProject.to_s}
    cmd = {"dtRelease"=>dtRelease}.merge(cmd) if dtRelease
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return (result/"ixFixFor").inner_html.to_i        
  end

  def categories
    cmd = {"cmd" => "listCategories", "token" => @token}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return list_process(result,"category","sCategory")
  end
  
  # Returns details about a specific Category
  #
  # * ixCategory: The id of the Category to view.
  # 
  # Value returned is a Hash containing all properties of the located Category.  nil is returned for unsucessful search.
  def category(ixCategory)
    cmd = {"cmd" => "viewCategory", "token" => @token, "ixCategory" => ixCategory.to_s}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return_value = list_process(result,"category","sCategory")
    return_value[return_value.keys[0]]    
  end

  def priorities
    cmd = {"cmd" => "listPriorities", "token" => @token}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return list_process(result,"priority","sPriority")
  end
  
  # Returns details about a specific priority
  #
  # * ixPriority: The id of the Priority to view
  # 
  # Value returned is a Hash containing all properties of the located Priority.  nil is returned for unsuccessful search.
  def priority(ixPriority)
    cmd = {"cmd" => "viewPriority", "token" => @token, "ixPriority" => ixPriority.to_s}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return_value = list_process(result,"priority","sPriority")
    return_value[return_value.keys[0]]        
  end

  # Returns list of people in corresponding categories.  
  #
  # * fIncludeNormal: Only include Normal users.  If no options specified,
  #   fIncludeNormal=1 is assumed.
  # * fIncludeCommunity: true/false Will include Community users in return.
  # * fIncludeVirtual: true/false Will include Virtual users in return.
  def people(fIncludeNormal="1", fIncludeCommunity=nil, fIncludeVirtual=nil)
    cmd = {
      "cmd" => "listPeople",
      "token" => @token,
      "fIncludeNormal" => fIncludeNormal
    }
    cmd = {"fIncludeCommunity" => "1"}.merge(cmd) if fIncludeCommunity
    cmd = {"fIncludeVirtual" => "1"}.merge(cmd) if fIncludeVirtual
    result = Hpricot.XML(@connection.post(@api_url, to_params(cmd)).body)
    return list_process(result,"person","sFullName")
  end

  # Returns details for a specific FogBugz user.  Can search by person's ID or their email address.
  #
  # * ixPerson: ID for the person to display
  # * sEmail: Email address for the person to display.
  #
  # Note: If you specify both, Email search seems to take precedence. 
  #
  # Value returned is a Hash of containing all properties of the located person.  nil is returned for unsuccessful search.
  def person(ixPerson=nil,sEmail=nil)
    return nil if not ixPerson || sEmail
    cmd = {"cmd" => "viewPerson", "token" => @token}
    cmd = {"ixPerson" => ixPerson.to_s}.merge(cmd) if ixPerson
    cmd = {"sEmail" => sEmail}.merge(cmd) if sEmail
    result = Hpricot.XML(@connection.post(@api_url, to_params(cmd)).body)
    return_value = list_process(result,"person","sFullName")
    return_value[return_value.keys[0]]
  end
  
  # Creates a new Person within FogBugz.
  #
  # * sEmail: Email address of the new Person.
  # * sFullname: Fullname of the new Person.
  # * nType: Type for the new user.  0 = Normal User, 1 = Administrator, 2 = Community User, 3 = Virtual User
  # * fActive: Is the new Person active? true/false
  def new_person(sEmail,sFullname,nType,fActive=true)
    cmd = {"cmd" => "newPerson", "token" => @token, "sEmail" => sEmail.to_s, "sFullname" => sFullname.to_s, "nType" => nType.to_s, "fActive" => (fActive) ? "1" : "0"}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return (result/"ixPerson").inner_html.to_i        
  end

  # Returns a list of statuses for a particular category.
  #
  # * ixCategory => category to return statuses for.  If not specified, then all are returned.
  # * fResolved => If = 1 then only resolved statuses are returned.
  def statuses(ixCategory=nil,fResolved=nil)
    cmd = {
      "cmd" => "listStatuses",
      "token" => @token
    }
    cmd = {"ixCategory"=>ixCategory}.merge(cmd) if ixCategory
    cmd = {"fResolved"=>fResolved}.merge(cmd) if fResolved
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return list_process(result,"status","sStatus")
  end

  # Returns details about a specific status
  #
  # * ixStatus: The id of the Status to view
  # 
  # Value returned is a Hash containing all properties of the located Status.  nil is returned for unsuccessful search.  
  def status(ixStatus)
    cmd = {"cmd" => "viewStatus", "token" => @token, "ixStatus" => ixStatus.to_s}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return_value = list_process(result,"status","sStatus")
    return_value[return_value.keys[0]]            
  end

  # Returns a list of mailboxes that you have access to.
  def mailboxes
    cmd = {
      "cmd" => "listMailboxes",
      "token" => @token
    }
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    # usually lists were keyed w/ a name field.  Mailboxes just
    # weren't working for me so I'm going with ixMailbox value
    return list_process(result,"mailbox","ixMailbox")
  end

  # Returns details about a specific mailbox
  #
  # * ixMailbox: The id of the Mailbox to view
  # 
  # Value returned is a Hash containing all properties of the located Mailbox.  nil is returned for unsuccessful search.    
  def mailbox(ixMailbox)
    cmd = {"cmd" => "viewMailbox", "token" => @token, "ixMailbox" => ixMailbox.to_s}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return_value = list_process(result,"mailbox","ixMailbox")
    return_value[return_value.keys[0]]    
  end

  # Searches for FogBugz cases
  #
  # * q: Query for searching. Should hopefully work just like the Search box
  #   within the FogBugz application.
  # * cols: Columns of information to be returned for each case found.  Consult
  #   FogBugz API documentation for a list.  If this is not specified the
  #   CASE_COLUMNS will be used.  This will request every possible datapoint (as
  #   of API version 5) for each case.
  # * max: Maximum number of cases to be returned for your search.  Will return
  #   all if not specified.
  def search(q, cols=CASE_COLUMNS, max=nil)
    # TODO - shoudl I worry about the "operations" returned
    # in the <case>?
    
    cmd = {"cmd" => "search","token" => @token,"q" => q, "cols" => cols.join(",")}
    # ixBug is the key for the hash returned so I'm adding it to the cols array just in case
    cmd = {"cols" => (cols + ["ixBug"])}.merge(cmd) if not cols.include?("ixBug")
    cmd = {"max" => max}.merge(cmd) if max
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return_value = list_process(result,"case","ixBug")
    # if one of the returned cols = events, then process 
    # this list and replace its spot in the Hash
    # with this instead of a string of XML
    return_value.each do |key,value|
      return_value[key]["events"] = list_process(Hpricot.XML(return_value[key]["events"]),"event","ixBugEvent") if return_value[key].has_key?("events")
    end
    return_value
  end

  # Creates a FogBugz case.  
  #
  # * params: must be a hash keyed with values from the FogBugz API docs.
  #   sTitle, ixProject (or sProject), etc...
  # * cols: columns to be returned about the case which gets created.  Ff not
  #   passed will use constant list (all) provided with Class
  def new_case(params, cols=CASE_COLUMNS)
    case_process("new",params,cols)
  end
  
  # Returns information about a specific Person's working schedule
  #
  # * ixPerson: ID of the person to list working schedule.  If omitted currently logged in person is listed.
  def working_schedule(ixPerson=nil)
    cmd = {"cmd"=>"listWorkingSchedule","token"=>@token}
    cmd = {"ixPerson"=>ixPerson.to_s}.merge(cmd) if ixPerson
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    return_value = list_process(result,"workingSchedule","ixPerson")
    return_value = return_value[return_value.keys[0]] 
    Hpricot.XML(return_value["rgWorkDays"]).each_child do |e|
        return_value[e.name] = (e.inner_html == "true" ? true : false) if e.class == Hpricot::Elem
    end
    return_value
  end

  # start working on this case and charge time to it (start the stopwatch)
  #
  # * ixBug: ID of the case you want to start working on  
  def start_work(ixBug)
    cmd = {"cmd"=>"startWork","token"=>@token,"ixBug"=>ixBug.to_s}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    raise FogBugzError, "Code: #{(result/"error")[0]["code"]} - #{(result/"error").inner_html}" if (result/"error").inner_html != ""
  end
  
  # stop working on everything (stop the stopwatch)
  def stop_work
    cmd = {"cmd"=>"stopWork","token"=>@token}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    raise FogBugzError, "Code: #{(result/"error")[0]["code"]} - #{(result/"error").inner_html}" if (result/"error").inner_html != ""
  end
  
  # list all of the checkins that have been associated with the specified case
  def checkins(ixBug)
    cmd = {"cmd"=>"listCheckins","token"=>@token,"ixBug"=>ixBug.to_s}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    raise FogBugzError, "Code: #{(result/"error")[0]["code"]} - #{(result/"error").inner_html}" if (result/"error").inner_html != ""
    list_process(result,"checkin","ixCVS")
  end
  
  # list all wikis in FogBugz
  def wikis
    cmd = {"cmd"=>"listWikis","token"=>@token}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    raise FogBugzError, "Code: #{(result/"error")[0]["code"]} - #{(result/"error").inner_html}" if (result/"error").inner_html != ""
    list_process(result,"wiki","ixWiki")
  end
  
  # list all articles in a specified wiki
  #
  # ixWiki: ID of the wiki to list articles
  def articles(ixWiki)
    cmd = {"cmd"=>"listArticles","token"=>@token,"ixWiki"=>ixWiki.to_s}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    raise FogBugzError, "Code: #{(result/"error")[0]["code"]} - #{(result/"error").inner_html}" if (result/"error").inner_html != ""
    list_process(result,"article","ixWikiPage")
  end
  
  # view contents of a specific wiki article
  # TODO - add ability to specify page revision
  def article(ixWikiPage)
    cmd = {"cmd"=>"viewArticle","token"=>@token,"ixWikiPage"=>ixWikiPage.to_s}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    raise FogBugzError, "Code: #{(result/"error")[0]["code"]} - #{(result/"error").inner_html}" if (result/"error").inner_html != ""
    return_value = list_process(result,"wikipage","sBody")
    return_value[return_value.keys[0]]
  end
  
  # list revisions of a specific wiki page
  # ixWikiPage: ID of the wiki page to list revisions.
  def revisions(ixWikiPage)
    cmd = {"cmd"=>"listRevisions","token"=>@token,"ixWikiPage"=>ixWikiPage.to_s}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    raise FogBugzError, "Code: #{(result/"error")[0]["code"]} - #{(result/"error").inner_html}" if (result/"error").inner_html != ""
    list_process(result,"revision","nRevision")    
  end
  
  # list wiki templates
  def templates
    cmd = {"cmd"=>"listTemplates","token"=>@token}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    raise FogBugzError, "Code: #{(result/"error")[0]["code"]} - #{(result/"error").inner_html}" if (result/"error").inner_html != ""
    list_process(result,"template","ixTemplate")        
  end
  
  # lists all readable discussion groups
  def discussion_groups
    cmd = {"cmd"=>"listDiscussGroups","token"=>@token}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    raise FogBugzError, "Code: #{(result/"error")[0]["code"]} - #{(result/"error").inner_html}" if (result/"error").inner_html != ""
    list_process(result,"discussion","ixDiscussGroup")          
  end
  
  # get back info on this person such as their timezone offset, preferred columns, etc..
  def settings
    cmd = {"cmd"=>"viewSettings","token"=>@token,"ixPerson"=>"4"}
    result = Hpricot.XML(@connection.post(@api_url,to_params(cmd)).body)
    raise FogBugzError, "Code: #{(result/"error")[0]["code"]} - #{(result/"error").inner_html}" if (result/"error").inner_html != ""
    return_value = Hash.new
    (result/"settings")[0].each_child do |e|
      if e.inner_html =~ CDATA_REGEXP
        return_value[e.name] = CDATA_REGEXP.match(e.inner_html)[1]
      else
        return_value[e.name] = e.inner_html
      end
    end
    return_value
  end
  
  protected

  CDATA_REGEXP = /<!\[CDATA\[(.*?)\]\]>/

  def fogbugz_error?(xml)
  
  end
  # Makes connection to the FogBugz server
  #
  # Assumes port 443 for SSL connections and 80 for non-SSL connections.
  # Possibly should provide a way to override this.
  def connect
    @connection = Net::HTTP.new(@url, @use_ssl ? 443 : 80) 
    @connection.use_ssl = @use_ssl
    @connection.verify_mode = OpenSSL::SSL::VERIFY_NONE if @use_ssl
  end

  def case_process(cmd,params,cols)
    cmd = {
      "cmd" => cmd,
      "token" => @token,
      "cols" => cols.join(",")
    }.merge(params)
    result = Hpricot.XML(@connection.post(@api_url, to_params(cmd)).body)
    return_value = list_process(result,"case","ixBug")
    # if one of the returned cols = events, then process 
    # this list and replace its spot in the Hash
    # with this instead of a string of XML
    return_value.each do |key,value|
      return_value[key]["events"] = list_process(Hpricot.XML(return_value[key]["events"]),"event","ixBugEvent") if return_value[key].has_key?("events")
    end
    return_value[return_value.keys[0]]
  end

  # method used by other list methods to process the XML returned by FogBugz API.
  #
  # * xml => XML to process
  # * element => individual elements within the XML to create Hashes for within the returned value
  # * element_name => key for each individual Hash within the return value.
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
  #       "ixCategory" => 1,
  #       "sCategory" => "Bug",
  #       "sPlural" => "Bugs",
  #       "ixStatusDefault" => 2,
  #       "fIsScheduleItem" => false
  #   },
  #   "Feature" => {
  #       "ixCategory" => 2,
  #       "sCategory" => "Feature",
  #       "sPlural" => "Features",
  #       "ixStatusDefault" => 2,
  #       "fIsScheduleItem" => false
  #   }
  # }
  def list_process(xml, element, element_name)
    return_value = Hash.new
    (xml/"#{element}").each do |item|
      if element_name[0,1] == "s"
        item_name = CDATA_REGEXP.match((item/"#{element_name}").inner_html)[1]
      else
        item_name = (item/"#{element_name}").inner_html 
      end
      return_value[item_name] = Hash.new

      item.each_child do |attribute|
        if attribute.class != Hpricot::Text
          return_value[item_name][attribute.name] = attribute.inner_html
          # convert values to proper types
          return_value[item_name][attribute.name] = CDATA_REGEXP.match(attribute.inner_html)[1] if (attribute.name[0,1] == "s" or attribute.name[0,3] == "evt") and attribute.inner_html != "" and CDATA_REGEXP.match(attribute.inner_html) != nil
          return_value[item_name][attribute.name] = return_value[item_name][attribute.name].to_i if (attribute.name[0,2] == "ix" or attribute.name[0,1] == "n")
          return_value[item_name][attribute.name] = (return_value[item_name][attribute.name] == "true") ? true : false if attribute.name[0,1] == "f"
        end
      end
    end

    return_value
  end

  # Converts a hash such as 
  #   {
  #     :cmd => "logon", 
  #     :email => "austin.moody@gmail.com", 
  #     :password => "yeahwhatever",
  #   }
  # to
  #   "cmd=logon&email=austin.moody@gmail.com&password=yeahwhatever"
  def to_params(hash)
    hash.map{|key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join('&')
  end
end
