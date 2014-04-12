require_relative 'helper'

class UpdateTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Baggage::App
  end

  def test_update
    s = Baggage::Subscriber.new
    s.subscribe(:email => 'user@domain.com')

    get "/update/#{s.id}?token=#{s.doc[:admin_token]}"
    expected = {:message => 'updated'}.to_json
    assert_equal expected, last_response.body
    assert last_response.ok?
  end

  def test_update_param_name_invalid
    s = Baggage::Subscriber.new
    s.subscribe(:email => 'user@domain.com')
    get "/update/#{s.id}?token=#{s.doc[:admin_token]}&name=test%40ing"
    expected = 'Invalid Parameter: name'
    assert_equal expected, last_response.body
    assert_equal false, last_response.ok?
  end

  def test_update_param_name_valid
    s = Baggage::Subscriber.new
    s.subscribe(:email => 'user@domain.com')
    get "/update/#{s.id}?token=#{s.doc[:admin_token]}&name=testing"
    expected = {:message => 'updated'}.to_json
    assert_equal expected, last_response.body
    assert last_response.ok?

    s.read
    assert_equal 'testing', s.doc[:name]
  end

  def test_update_param_expires_invalid
    s = Baggage::Subscriber.new
    s.subscribe(:email => 'user@domain.com')
    get "/update/#{s.id}?token=#{s.doc[:admin_token]}&expires=1000"
    expected = 'Invalid Parameter: expires'
    assert_equal expected, last_response.body
    assert_equal false, last_response.ok?
  end

  def test_update_param_expires_valid
    s = Baggage::Subscriber.new
    s.subscribe(:email => 'user@domain.com')
    get "/update/#{s.id}?token=#{s.doc[:admin_token]}&expires=1"
    expected = {:message => 'updated'}.to_json
    assert_equal expected, last_response.body
    assert last_response.ok?

    assert_operator 86400, :>=, s.get_ttl
  end

end
