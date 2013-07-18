require 'sinatra'
require "rack/session/cookie"
require "haml"
require "time"
require "httparty"
require "octokit"

CLIENT_ID = ENV["CLIENT_ID"]
CLIENT_SECRET = ENV["CLIENT_SECRET"]

use Rack::Session::Cookie, :secret => ENV["COOKIE_SECRET"]

get '/' do
  haml :index
  if params["repo"]
    client = if session["code"]
        Octokit::Client.new(:login => session["self"], :access_token => session["access_token"])
      else
        Octokit
      end
    name = params["user"] + "/" + params["repo"]
    issues = (client.issues(name, :state => "open") + client.issues(name, :state => "closed")).group_by(&:milestone)
    issues.each do |m, v|
      issues.delete(m) if m.nil? || m.state == "closed" || v.nil?
    end
  
    issues.each do |milestone, related|
      start = Time.now - 2*7*24*60*60
      delta = Time.now - start
      total_open = milestone.open_issues
      creates = []
      closes = []
      related.each do |issue|
        creates << Time.parse(issue.created_at)
        if issue.closed_at
          closes << Time.parse(issue.closed_at)
        end
      end
    
      recent_opened = creates.select{|s| s >= start }.size
      recent_closed = closes.select{|s| s >= start }.size
      rate = (recent_closed - recent_opened) / delta
      puts "rate: #{milestone.title} #{recent_closed} - #{recent_opened}"
    
      optclose = 0
      optopen = 0
      opttime = start
      (1..closes.size).each do |i|
        close = closes[-i]
        later_opens = creates.select{|s| s >= close }.size
        if i > later_opens
          optclose = i
          optopen = later_opens
          opttime = close
        end
      end
      if optclose > 0
        best_rate = (optclose - optopen) / (Time.now - opttime)
        puts "optimist: #{best_rate}"
        milestone.optimistic_completion = Time.now + total_open / best_rate.to_f 
      end
      puts rate
      # puts best_rate
      if rate > 0
        milestone.estimated_completion = Time.now + total_open / rate.to_f 
      end
    end;nil
    @issues = issues
  end
  haml :index
end

get '/callback' do
  code = params["code"]
  rsp = HTTParty.post("https://github.com/login/oauth/access_token", :body =>{
      "client_id" => CLIENT_ID,
      "client_secret" => CLIENT_SECRET,
      "code" => code
    }, :headers => { 'Accept' => 'application/json' } )
  json = rsp.parsed_response
  session["access_token"] = json["access_token"]
  rsp = HTTParty.get("https://api.github.com/user?access_token=#{session["access_token"]}", 
    :headers => { 'Accept' => 'application/json' } )
  rsp.inspect
  session["self"] = rsp.parsed_response["login"]
  redirect to("/")
end