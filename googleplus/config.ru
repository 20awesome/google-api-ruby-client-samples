require 'bundler/setup'
require 'sinatra/base'
require 'omniauth'
require 'google/omniauth'
require 'google/api_client/client_secrets'

class App < Sinatra::Base
  def client
    c = (Thread.current[:client] ||= Google::APIClient.new)
    if session['credentials']
      c.authorization.access_token = session['credentials']['access_token']
      c.authorization.refresh_token = session['credentials']['refresh_token']
    else
      # It's really important to clear these out,
      # since we reuse client objects across requests
      # for performance reasons.
      c.authorization.access_token = nil
      c.authorization.refresh_token = nil
    end
    return c
  end
  
  get '/' do
    erb :index
  end

  get '/whoami' do
    if client.authorization.access_token
      # Get a reference to the discovery document
      plus = client.discovered_api('plus', 'v1')
      
      # Execute the API call.
      result = client.execute(plus.people.get, 'userId' => 'me')
      
      erb :whoami, :locals => { :data => result.data }
    else
      "Missing access token."
    end
  end

  # Support both GET and POST for callbacks
  %w(get post).each do |method|
    send(method, "/auth/:provider/callback") do
      Thread.current[:client] = env['omniauth.auth']['extra']['client']
      
      # Keep track of the tokens. Use a real database in production.
      session['uid'] = env['omniauth.auth']['uid']
      session['credentials'] = env['omniauth.auth']['credentials']

      redirect '/whoami'      
    end
  end

  get '/auth/failure' do
    unless production?
      # Something went wrong. Dump the environment to help debug.
      # DO NOT DO THIS IN PRODUCTION.
      content_type 'application/json'
      MultiJson.encode(request.env)
    else
      content_type 'text/plain'
      "Something went wrong."
    end
  end
  
  template :layout do
    <<-ERB
      <html>
        <body style="font: 13px/16px arial,sans-serif;">
          <%= yield %>
        </body>
      </html>
    ERB
  end

  template :index do
    <<-ERB
      <div class="auth">
        <button style="border-radius: 4px; padding: 8px;" onclick="window.location='/auth/google';">
          <div style="display: inline-block; line-height: 0;">
            <span style="float: left; font: bold 13px/16px arial,sans-serif; margin-right: 4px; margin-top: 7px;">Sign In</span>
            <span style="float: left; font: 13px/16px arial,sans-serif; margin-right: 11px; margin-top: 7px;">on</span>
            <div style="float: left;">
              <img src="https://ssl.gstatic.com/images/icons/gplus-32.png" width="32" height="32" style="border: 0;">
            </div>
            <div style="clear: both;"></div>
          </div>
        </button>
      </div>
    ERB
  end

  template :whoami do
    <<-ERB
      <div class="me">
        Hello, my name is <span style="font: bold 13px/16px arial,sans-serif;"><%= data.display_name %></span>.
      </div>
    ERB
  end
end

use Rack::Session::Cookie

use OmniAuth::Builder do
  client_secrets = Google::APIClient::ClientSecrets.load
  provider OmniAuth::Strategies::Google,
    client_secrets.client_id,
    client_secrets.client_secret,
    :scope => [
      'https://www.googleapis.com/auth/userinfo.profile',
      'https://www.googleapis.com/auth/userinfo.email',
      'https://www.googleapis.com/auth/plus.me'
    ],
    :skip_info => false
end

run App.new
