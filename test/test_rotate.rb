require_relative 'helper'

class RotateTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Baggage::App
  end

  def test_rotate
    s = Baggage::Subscriber.new
    s.subscribe(:email => 'user@domain.com')
    old_id = s.id
    old_email_token = s.doc[:email_token]
    old_admin_token = s.doc[:admin_token]

    get "/rotate/#{s.id}?token=#{s.doc[:admin_token]}"
    expected = {:message => 'rotated'}.to_json
    assert_equal expected, last_response.body
    assert last_response.ok?

    s.read
    assert_equal old_id, s.id
    assert_not_equal old_email_token, s.doc[:email_token]
    assert_not_equal old_admin_token, s.doc[:admin_token]
  end
end
