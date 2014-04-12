require_relative 'helper'

class SubscribeTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Baggage::App
  end

  def test_subscribe
    get '/subscribe/user@domain.com'
    expected = {:message => 'subscription sent'}.to_json
    assert_equal expected, last_response.body
    assert last_response.ok?
  end

  def test_subscribe_param_name_valid
    get '/subscribe/user@domain?name=testing'
    expected = {:message => 'subscription sent'}.to_json
    assert_equal expected, last_response.body
    assert last_response.ok?
  end

  def test_subscribe_param_name_invalid
    get '/subscribe/user@domain?name=test%40ing'
    expected = 'Invalid Parameter: name'
    assert_equal expected, last_response.body
    assert_equal false, last_response.ok?
  end

  def test_subscribe_param_name_valid
    get '/subscribe/user@domain?expires=10'
    expected = {:message => 'subscription sent'}.to_json
    assert_equal expected, last_response.body
    assert last_response.ok?
  end

  def test_subscribe_param_name_invalid
    get '/subscribe/user@domain?expires=1000'
    expected = 'Invalid Parameter: expires'
    assert_equal expected, last_response.body
    assert_equal false, last_response.ok?
  end
end
