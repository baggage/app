require_relative 'helper'

class UnsubscribeTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Baggage::App
  end

  def test_unsubscribe
    s = Baggage::Subscriber.new
    s.subscribe(:email => 'user@domain.com')
    old_id = s.id
    old_email_token = s.doc[:email_token]
    old_admin_token = s.doc[:admin_token]

    get "/unsubscribe/#{s.id}?token=#{s.doc[:admin_token]}"
    expected = {:message => 'unsubscribed'}.to_json
    assert_equal expected, last_response.body
    assert last_response.ok?

    assert_raise ( RuntimeError ) { s.read }
  end

end
