require_relative 'helper'

class PingTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Baggage::App
  end

  def test_ping
    get '/ping'
    expected = {:message => 'pong'}.to_json
    assert_equal expected, last_response.body
    assert last_response.ok?
  end

end
