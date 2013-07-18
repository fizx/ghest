require 'sinatra'
require "rack/session/cookie"
require "haml"
require "httparty"

CLIENT_ID = ENV["CLIENT_ID"]
CLIENT_SECRET = ENV["CLIENT_SECRET"]

use Rack::Session::Cookie, :secret => ENV["COOKIE_SECRET"]

get '/' do
  haml :index
end

get '/view' do
  repo= if session["code"]
      Octokit::Client.new(:login => session["self"], session["access_token"]).repo
    else
      Octokit.repo params["user"] + "/" + params["repo"]
    end
  repo.inspect
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