require 'net/http'
require 'json'
require 'time'
require 'uri'

HANDLE      = ENV.fetch('BSKY_HANDLE')
PASSWORD    = ENV.fetch('BSKY_APP_PASSWORD')
DAYS_TO_KEEP = ENV.fetch('DAYS_TO_KEEP', '60').to_i
BASE_URL    = 'https://bsky.social/xrpc'

def post_json(path, body)
  uri = URI("#{BASE_URL}/#{path}")
  req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
  req.body = body.to_json
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
end

def get_json(path, params, token)
  uri = URI("#{BASE_URL}/#{path}")
  uri.query = URI.encode_www_form(params)
  req = Net::HTTP::Get.new(uri, 'Authorization' => "Bearer #{token}")
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
end

def login
  res = post_json('com.atproto.server.createSession', { identifier: HANDLE, password: PASSWORD })
  raise "Login failed: #{res.body}" unless res.is_a?(Net::HTTPSuccess)
  JSON.parse(res.body)
end

def get_posts(session)
  posts  = []
  cursor = nil
  loop do
    params = { actor: session['did'], limit: 100 }
    params[:cursor] = cursor if cursor
    res = get_json('app.bsky.feed.getAuthorFeed', params, session['accessJwt'])
    raise "Failed to fetch posts: #{res.body}" unless res.is_a?(Net::HTTPSuccess)
    data   = JSON.parse(res.body)
    feed   = data['feed'] || []
    break if feed.empty?
    posts.concat(feed)
    cursor = data['cursor']
    break unless cursor
  end
  posts
end

def delete_post(session, uri_str)
  rkey = uri_str.split('/').last
  res  = post_json('com.atproto.repo.deleteRecord', {
    repo:       session['did'],
    collection: 'app.bsky.feed.post',
    rkey:       rkey
  })
  # deleteRecordはtokenが必要なのでヘッダーを付与する必要がある
  # Net::HTTPではbodyと別にheaderを渡せないため、手動でリクエストを組む
  uri     = URI("#{BASE_URL}/com.atproto.repo.deleteRecord")
  req     = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{session['accessJwt']}")
  req.body = { repo: session['did'], collection: 'app.bsky.feed.post', rkey: rkey }.to_json
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
end

def main
  session = login
  posts   = get_posts(session)
  cutoff  = Time.now.utc - (DAYS_TO_KEEP * 24 * 60 * 60)
  deleted = 0

  posts.each do |item|
    post       = item['post']
    created_at = Time.parse(post['record']['createdAt']).utc
    next unless created_at < cutoff

    delete_post(session, post['uri'])
    puts "Deleted: #{post['uri']} (#{created_at.to_date})"
    deleted += 1
  end

  puts "Done. Deleted #{deleted} posts."
end

main
