#Description
#   A hubot script that interacts with JIRA
#
# Configuration:
#   HUBOT_JIRA_USERNAME - JIRA User Name
#   HUBOT_JIRA_PASSWORD - JIRA Password
#   HUBOT_JIRA_SERVER - location of the JIRA JSON API server
#   HUBOT_JIRA_USER - userid in jira
#
# Commands:
#   createjira <project> [<summary>] [<description>]
#   assignjira <ticketid> to <userid>
#   searchjira <projectname> unassigned
#   commentjira <ticketid> [hello comment1]
#   movejira <ticketid> to [Work in Progress]
#   
#
# Notes:
#   <optional notes required for the script>
#

module.exports = (robot) ->
  options =
    rejectUnauthorized: false
  authToken = 'Basic ' + new Buffer(process.env.HUBOT_JIRA_USERNAME + ':' + process.env.HUBOT_JIRA_PASSWORD).toString('base64')
  auth = "#{process.env.HUBOT_JIRA_USERNAME}:#{process.env.HUBOT_JIRA_PASSWORD}"
 
  if !authToken
    msg.send "An Authorization string is required to use this hubot-jira"

  labsServerUrl=process.env.HUBOT_JIRA_SERVER
  
  robot.respond /status/i, (msg) ->
    msg.send "I\'ve  queried #{robot.brain.get('usage.JIRA') * 1 or 0} JIRA issues with #{robot.brain.get('failure.JIRA') * 1 or 0} failures."
    
  #createjira <project> [<summary>] [<description>]
  robot.hear /createjira (.+) \[(.*?)\] \[(.*?)\]/, (msg) ->
    ticket = JSON.stringify({ "fields": { "project": { "key": msg.match[1] }, "summary": msg.match[2], "description": msg.match[3], "issuetype": { "name": "Support Ticket" }} })
    robot.http(labsServerUrl + "/rest/api/2/issue")
      .header("Content-Type", "application/json").auth(auth).post(ticket) (err, res, body) ->
        msg.send if res.statusCode == 204 then "Success!" else body
        
  # assignjira <ticketid> to <userid>
  robot.hear /assignjira (.+) to (.+)/, (msg) ->
    issue = String(msg.match[1])
    msg.send String(msg.match[2])
    assignee = JSON.stringify({"name": String(msg.match[2])})
    robot.http(labsServerUrl + "/rest/api/2/issue/#{issue}/assignee")
      .header("Content-Type", "application/json").auth(auth).put(assignee) (err, res, body) ->
        msg.send if res.statusCode == 204 then "Success!" else body
  
  # searchjira <project> unassigned
  robot.hear /searchjira (.+) unassigned/, (msg) ->
    jql = "project=#{msg.match[1]} AND resolution=Unresolved AND assignee=Unassigned"
    robot.http(labsServerUrl + "/rest/api/2/search?jql=#{jql}&maxResults=10")
      .auth(auth).get() (err, res, body) ->
        jsonData = JSON.parse(body);
        i=0
        res = "/code "
        while i <= jsonData.issues.length
          issue = jsonData.issues[i];
          if issue?
            msg.send issue.key + ": " + issue.fields.reporter.displayName + " Created: " + issue.fields.summary + '\n'
          i++

  #commentjira <ticketid> [<comment>]
  robot.hear /commentjira (.+) \[(.*?)\]/, (msg) ->
    issue = String(msg.match[1])
    comment = JSON.stringify({"body" : String(msg.match[2])})
    robot.http(labsServerUrl + "/rest/api/2/issue/#{issue}/comment")
      .header("Content-Type", "application/json").auth(auth).post(comment) (err, res, body) ->
        msg.send if res.statusCode == 201 then "Success!" else body
  
  
  # movejira <ticketid> to [Work in Progress]
  robot.hear /movejira (.+) to \[(.*?)\]/, (msg) ->
    issue = msg.match[1]
    msg.send "Getting transitions for #{issue}"
    robot.http(labsServerUrl + "/rest/api/2/issue/#{issue}/transitions")
      .auth(auth).get() (err, res, body) ->
        jsonBody = JSON.parse(body)
        status = jsonBody.transitions.filter (trans) ->
          trans.name.toLowerCase() == msg.match[2].toLowerCase()
        if status.length == 0
          trans = jsonBody.transitions.map (trans) -> trans.name
          msg.send "The only transitions of #{issue} are: #{trans.reduce (t, s) -> t + "," + s}"
          return
        msg.send "Changing the status of #{issue} to #{status[0].name}"
        if String(status[0].name) == "Done"
          transbody = JSON.stringify({transition: status[0], "fields": { "customfield_11607": { "value": "Task Completed", "id": "12092" }}})
        else
          transbody = JSON.stringify({transition: status[0]})
        
        robot.http(labsServerUrl + "/rest/api/2/issue/#{issue}/transitions")
          .header("Content-Type", "application/json").auth(auth).post(transbody) (err, res, body) ->
            msg.send if res.statusCode == 204 then "Success!" else body
  
  robot.respond /jirastatus/, (msg) ->
    robot.http(labsServerUrl + "/rest/api/2/status")
      .auth(auth).get() (err, res, body) ->
        response = "/code "
        for status in JSON.parse(body)
          response += status.name + ": " + status.description + '\n'
        msg.send response

  ###
  #Respond to a JIRA issue number
  robot.hear /\b[A-Z]{2,}-\d+\b/, (msg) ->
   # robot.logger.info "Overheard \"#{msg.message.text.replace(/(\r\n|\n|\r)/gm," ")}\"\; in: #{msg.message.room}\; from: #{msg.message.user.name}" if msg.message.text.search(robot.name) < 0
   issue = escape(msg.match[0])
   robot.http(labsServerUrl + "rest/api/2/search?jql=issue=" + issue)
    .auth(auth).get() (err, res, body) ->
      response = "/code "
      for issues in JSON.parse(body)
        response += issues.name + ": " + issues.description + '\n'
      msg.send response

    #issue = escape(msg.match[0])
    issuePath = "rest/api/latest/issue/#{issue}"
    labsUrl = labsServerUrl + issuePath
    getIssue(msg, labsUrl, authToken)
    robot.brain.set 'usage.JIRA', robot.brain.get('usage.JIRA')+1

  # Execute the rest service and create the attachment fields if successful
  getIssue = (msg, url, authToken) ->
    robot.http(url,options)
    .headers(Accept: 'application/json',Authorization: authToken)
    .get() (err, res, body) ->
      try
        data = JSON.parse body
        msg.send String(data.fields.summary)
        msg.send String(data.fields.customfield_10800)
        
      catch error
        else
          robot.brain.set 'failure.JIRA', robot.brain.get('failure.JIRA')+1
          if res?.statusCode != 404
            robot.logger.error "#{url} failed with statusCode #{res?.statusCode}"
  ###